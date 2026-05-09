import 'dotenv/config';

import Fastify from 'fastify';
import cors from '@fastify/cors';
import { eq } from 'drizzle-orm';
import { generateObject } from 'ai';
import { createOpenAI } from '@ai-sdk/openai';
import { z } from 'zod';

import { closeDb, connectDb, db } from './db';
import { ensureSchema } from './ensure-schema';
import {
  buildFallbackReason,
  rankPlacesForQuery,
  selectDiverseShortlist,
} from './ai-recommendations';
import {
  applyApprovedImageCandidates,
  approveImageCandidate,
  discoverImageCandidates,
  getPlaceGalleryImages,
  listImageCandidates,
  rejectImageCandidate,
  reassignImageCandidate,
} from './image-candidate-service';
import { previewGoogleHoursForPlace } from './google-places-hours';
import { openingHoursSchema } from './opening-hours';
import { enrichPlaceWithWikipedia, type AiProviderConfig } from './wiki-enrichment';
import { toPlaceDto } from './place-dto';
import { places } from './schema';

const PORT = Number(process.env.PORT ?? 4000);
const OPENAI_API_KEY = process.env.OPENAI_API_KEY?.trim();
const OPENAI_MODEL = process.env.OPENAI_MODEL ?? 'gpt-4o-mini';
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY?.trim();
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL ?? 'anthropic/claude-sonnet-4.5';
const APP_URL = process.env.APP_URL ?? 'http://localhost:4000';
const MAX_CONTEXT_PLACES = 14;
const MIN_AI_RECOMMENDATIONS = 4;
const MAX_AI_RECOMMENDATIONS = 5;
const AI_PROVIDER = process.env.AI_PROVIDER?.trim().toLowerCase();
const openai = createOpenAI({
  name: 'openai',
  apiKey: OPENAI_API_KEY,
});
const openrouter = createOpenAI({
  name: 'openrouter',
  apiKey: OPENROUTER_API_KEY,
  baseURL: 'https://openrouter.ai/api/v1',
  headers: {
    'HTTP-Referer': APP_URL,
    'X-OpenRouter-Title': 'AI City Guide',
  },
});

const chatMessageSchema = z.object({
  role: z.enum(['user', 'assistant']),
  content: z.string().trim().min(1),
});

const optionalTextInput = z.preprocess(
  (value) => (typeof value === 'string' ? value.trim() : value),
  z.string().min(1).optional()
);

const optionalUrlInput = z.preprocess(
  (value) => (typeof value === 'string' ? value.trim() : value),
  z.string().url().optional()
);

function createSlug(value: string) {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase() || `place-${Date.now()}`;
}

async function reverseGeocode(latitude: number, longitude: number) {
  const response = await fetch(
    `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${latitude}&lon=${longitude}&addressdetails=1`,
    {
      headers: {
        'User-Agent': 'AI City Guide/1.0',
        Accept: 'application/json',
      },
    }
  );

  if (!response.ok) {
    throw new Error(`Reverse geocode failed with ${response.status}`);
  }

  const data = await response.json();
  const address = data.address ?? {};

  return {
    name: data.name ?? '',
    displayName: data.display_name ?? '',
    city:
      address.city || address.town || address.village || address.hamlet || address.county || '',
    country: address.country || '',
    address,
  };
}

type AiProviderName = 'openai' | 'openrouter';

function getAiProviderConfig():
  | {
      provider: AiProviderName;
      model: string;
      client: ReturnType<typeof createOpenAI>;
    }
  | null {
  const openaiConfig =
    OPENAI_API_KEY
      ? {
          provider: 'openai' as const,
          model: OPENAI_MODEL,
          client: openai,
        }
      : null;

  const openrouterConfig =
    OPENROUTER_API_KEY
      ? {
          provider: 'openrouter' as const,
          model: OPENROUTER_MODEL,
          client: openrouter,
        }
      : null;

  if (AI_PROVIDER === 'openai' && openaiConfig) return openaiConfig;
  if (AI_PROVIDER === 'openrouter' && openrouterConfig) return openrouterConfig;
  if (openaiConfig) return openaiConfig;
  if (openrouterConfig) return openrouterConfig;

  return null;
}

async function buildServer() {
  const app = Fastify({ logger: true });

  await app.register(cors, { origin: true });
  app.addHook('onClose', async () => {
    await closeDb();
  });

  app.get('/health', async () => ({ status: 'ok' }));
  app.get('/app-status', async () => {
    const aiProvider = getAiProviderConfig();

    return {
      status: 'ok',
      features: {
        aiRecommendationsEnabled: Boolean(aiProvider),
        aiProvider: aiProvider?.provider ?? null,
        googleHoursPreviewEnabled: Boolean(process.env.GOOGLE_MAPS_API_KEY?.trim()),
      },
    };
  });

  app.get('/places', async () => {
    const rows = await db.select().from(places);
    return rows.map(toPlaceDto);
  });

  app.get<{
    Querystring: { lat: string; lng: string };
  }>('/places/lookup', async (request, reply) => {
    const parsedQuery = z
      .object({
        lat: z.string().regex(/^-?\d+(?:\.\d+)?$/).transform(Number),
        lng: z.string().regex(/^-?\d+(?:\.\d+)?$/).transform(Number),
      })
      .safeParse(request.query);

    if (!parsedQuery.success) {
      return reply.code(400).send({ error: 'Latitude and longitude are required.' });
    }

    const { lat, lng } = parsedQuery.data;
    try {
      const locationInfo = await reverseGeocode(lat, lng);
      const enrichment = await enrichPlaceWithWikipedia(
        {
          name: locationInfo.name || locationInfo.city || 'Selected location',
          category: locationInfo.city || locationInfo.country || 'place',
          tags: [locationInfo.city, locationInfo.country].filter(Boolean),
          lat,
          lng,
        },
        getAiProviderConfig()
      );

      return {
        coordinates: { lat, lng },
        name: locationInfo.name,
        city: locationInfo.city,
        country: locationInfo.country,
        displayName: locationInfo.displayName,
        enrichment,
      };
    } catch (error: any) {
      request.log.error(error);
      return reply.code(502).send({ error: error?.message ?? 'Location lookup failed' });
    }
  });

  app.post<{
    Body: {
      name: string;
      category: string;
      city: string;
      country?: string;
      description: string;
      lat: number;
      lng: number;
      tags?: string;
      shortStory?: string;
    };
  }>('/places', async (request, reply) => {
    const parsedBody = z
      .object({
        name: z.string().trim().min(1),
        category: z.string().trim().min(1),
        city: z.string().trim().min(1),
        country: z.string().trim().min(1).optional(),
        description: z.string().trim().min(1),
        lat: z.number().min(-90).max(90),
        lng: z.number().min(-180).max(180),
        tags: z.string().trim().optional(),
        shortStory: z.string().trim().optional(),
      })
      .safeParse(request.body ?? {});

    if (!parsedBody.success) {
      return reply.code(400).send({ error: parsedBody.error.issues[0]?.message ?? 'Invalid place data' });
    }

    const placeSlug = createSlug(parsedBody.data.name);
    const existing = await db.query.places.findFirst({ where: eq(places.slug, placeSlug) });
    const id = existing ? `${placeSlug}-${Date.now()}` : placeSlug;
    const tags =
      parsedBody.data.tags?.trim() ||
      [parsedBody.data.category, parsedBody.data.city, parsedBody.data.country].filter(Boolean).join(',');

    const [created] = await db
      .insert(places)
      .values({
        id,
        slug: placeSlug,
        name: parsedBody.data.name,
        category: parsedBody.data.category,
        city: parsedBody.data.city,
        country: parsedBody.data.country ?? null,
        description: parsedBody.data.description,
        shortStory: parsedBody.data.shortStory?.trim() || parsedBody.data.description.slice(0, 180),
        tags,
        imageUrl: 'https://placehold.co/600x400?text=New+Place',
        imageVerified: false,
        imageType: 'unknown',
        importanceTier: 'supporting',
        lat: parsedBody.data.lat,
        lng: parsedBody.data.lng,
      })
      .returning();

    return toPlaceDto(created);
  });

  app.get<{
    Querystring: { placeId?: string; status?: 'pending' | 'approved' | 'rejected' | 'applied' };
  }>('/admin/image-candidates', async (request) => {
    const query = z
      .object({
        placeId: z.string().trim().min(1).optional(),
        status: z.enum(['pending', 'approved', 'rejected', 'applied']).optional(),
      })
      .parse(request.query);

    return await listImageCandidates({
      placeQuery: query.placeId,
      status: query.status,
    });
  });

  app.post<{
    Body: { placeId?: string; limit?: number; includeVerified?: boolean };
  }>('/admin/image-candidates/discover', async (request, reply) => {
    const parsedBody = z
      .object({
        placeId: z.string().trim().min(1).optional(),
        limit: z.number().int().min(1).max(10).optional(),
        includeVerified: z.boolean().optional(),
      })
      .safeParse(request.body ?? {});

    if (!parsedBody.success) {
      return reply.code(400).send({ error: parsedBody.error.issues[0]?.message ?? 'Invalid request' });
    }

    const results = await discoverImageCandidates({
      placeQuery: parsedBody.data.placeId,
      limit: parsedBody.data.limit,
      includeVerified: parsedBody.data.includeVerified,
    });

    return {
      discoveredPlaces: results.length,
      discoveredCandidates: results.reduce((sum, result) => sum + result.discoveredCount, 0),
      results,
    };
  });

  app.post<{
    Params: { candidateId: string };
  }>('/admin/image-candidates/:candidateId/approve', async (request, reply) => {
    try {
      const candidate = await approveImageCandidate(request.params.candidateId);
      return { candidate };
    } catch (error: any) {
      return reply.code(404).send({ error: error.message ?? 'Candidate not found' });
    }
  });

  app.post<{
    Params: { candidateId: string };
  }>('/admin/image-candidates/:candidateId/reject', async (request, reply) => {
    try {
      const candidate = await rejectImageCandidate(request.params.candidateId);
      return { candidate };
    } catch (error: any) {
      return reply.code(404).send({ error: error.message ?? 'Candidate not found' });
    }
  });

  app.post<{
    Params: { candidateId: string };
    Body: { placeId: string };
  }>('/admin/image-candidates/:candidateId/reassign', async (request, reply) => {
    const parsedBody = z
      .object({
        placeId: z.string().trim().min(1),
      })
      .safeParse(request.body ?? {});

    if (!parsedBody.success) {
      return reply.code(400).send({ error: parsedBody.error.issues[0]?.message ?? 'Invalid request' });
    }

    try {
      const candidate = await reassignImageCandidate(request.params.candidateId, parsedBody.data.placeId);
      return { candidate };
    } catch (error: any) {
      return reply.code(404).send({ error: error.message ?? 'Reassignment failed' });
    }
  });

  app.post<{
    Params: { candidateId: string };
  }>('/admin/image-candidates/:candidateId/apply', async (request) => {
    const applied = await applyApprovedImageCandidates({
      candidateId: request.params.candidateId,
    });

    return { appliedCount: applied.length, applied };
  });

  app.put<{
    Params: { id: string };
    Body: {
      hoursVerified?: boolean;
      hoursSourceUrl?: string;
      hoursNote?: string;
      openingHours?: z.input<typeof openingHoursSchema> | null;
      temporarilyClosed?: boolean;
    };
  }>('/admin/places/:id/hours', async (request, reply) => {
    const parsedBody = z
      .object({
        hoursVerified: z.boolean().optional(),
        hoursSourceUrl: optionalUrlInput,
        hoursNote: optionalTextInput,
        openingHours: openingHoursSchema.nullable().optional(),
        temporarilyClosed: z.boolean().optional(),
      })
      .safeParse(request.body ?? {});

    if (!parsedBody.success) {
      return reply.code(400).send({ error: parsedBody.error.issues[0]?.message ?? 'Invalid request' });
    }

    const existing = await db.query.places.findFirst({
      where: eq(places.id, request.params.id),
    });

    if (!existing) {
      return reply.code(404).send({ error: 'Place not found' });
    }

    const nextHoursVerified = parsedBody.data.hoursVerified ?? existing.hoursVerified ?? false;
    const nextOpeningHours =
      parsedBody.data.openingHours === undefined
        ? existing.openingHoursJson
        : parsedBody.data.openingHours == null
          ? null
          : JSON.stringify(parsedBody.data.openingHours);

    const [updated] = await db
      .update(places)
      .set({
        hoursVerified: nextHoursVerified,
        hoursSourceUrl:
          parsedBody.data.hoursSourceUrl === undefined
            ? existing.hoursSourceUrl
            : parsedBody.data.hoursSourceUrl ?? null,
        hoursNote:
          parsedBody.data.hoursNote === undefined ? existing.hoursNote : parsedBody.data.hoursNote ?? null,
        openingHoursJson: nextOpeningHours,
        hoursLastCheckedAt: nextHoursVerified ? new Date().toISOString() : null,
        temporarilyClosed:
          parsedBody.data.temporarilyClosed ?? existing.temporarilyClosed ?? false,
      })
      .where(eq(places.id, request.params.id))
      .returning();

    return {
      place: toPlaceDto(updated),
    };
  });

  app.post<{
    Params: { id: string };
  }>('/admin/places/:id/hours/google-preview', async (request, reply) => {
    const place = await db.query.places.findFirst({
      where: eq(places.id, request.params.id),
    });

    if (!place) {
      return reply.code(404).send({ error: 'Place not found' });
    }

    try {
      const previews = await previewGoogleHoursForPlace(place);
      return { previews };
    } catch (error: any) {
      request.log.error(error);

      const message = error?.message ?? 'Google Places preview failed';
      const statusCode = message.includes('GOOGLE_MAPS_API_KEY') ? 500 : 502;
      return reply.code(statusCode).send({ error: message });
    }
  });

  app.get<{
    Params: { id: string };
  }>('/places/:id', async (request, reply) => {
    const row = await db.query.places.findFirst({
      where: eq(places.id, request.params.id),
    });

    if (!row) {
      return reply.code(404).send({ error: 'Not found' });
    }

    const aiProvider = getAiProviderConfig();
    let placeRow = row;

    if (placeRow.wikiStatus == null && placeRow.lat != null && placeRow.lng != null) {
      const enrichment = await enrichPlaceWithWikipedia(
        {
          name: placeRow.name,
          category: placeRow.category,
          tags: placeRow.tags.split(',').map((tag) => tag.trim()).filter(Boolean),
          lat: placeRow.lat,
          lng: placeRow.lng,
        },
        aiProvider
      );

      const [updated] = await db
        .update(places)
        .set({
          wikiPageTitle: enrichment.status === 'matched' ? enrichment.pageTitle : null,
          wikiPageUrl: enrichment.status === 'matched' ? enrichment.pageUrl : null,
          wikiSummary: enrichment.status === 'matched' ? enrichment.summary : null,
          wikiMatchConfidence: enrichment.status === 'matched' ? enrichment.confidence : null,
          wikiStatus: enrichment.status,
          wikiRawMetadataJson: JSON.stringify(enrichment.rawMetadata ?? {}),
        })
        .where(eq(places.id, placeRow.id))
        .returning();

      placeRow = updated;
    }

    const gallery = await getPlaceGalleryImages(placeRow.id, placeRow.imageUrl);

    return {
      ...toPlaceDto(placeRow),
      gallery,
    };
  });

  app.post<{
    Body: { query: string; messages?: Array<{ role: 'user' | 'assistant'; content: string }> };
  }>('/places/recommend', async (request, reply) => {
    const parsedBody = z
      .object({
        query: z.string().trim().min(1, 'Query is required'),
        messages: z.array(chatMessageSchema).max(8).optional(),
      })
      .safeParse(request.body);

    if (!parsedBody.success) {
      return reply.code(400).send({ error: parsedBody.error.issues[0]?.message ?? 'Invalid request' });
    }

    const { query, messages = [] } = parsedBody.data;
    const aiProvider = getAiProviderConfig();

    if (!aiProvider) {
      return reply.code(500).send({
        error: 'OPENAI_API_KEY or OPENROUTER_API_KEY is not configured in the backend',
      });
    }

    const allRows = await db.select().from(places);
    const conversationSummary = messages
      .slice(-6)
      .map((message) => `${message.role.toUpperCase()}: ${message.content}`)
      .join('\n');
    const rankedRows = rankPlacesForQuery(allRows, query, conversationSummary);
    const recommendableRows = rankedRows.filter(
      (entry) => entry.qualityScore >= 36 || entry.row.importanceTier === 'hero'
    );
    const shortlistCandidates = recommendableRows.length > 0 ? recommendableRows : rankedRows;
    const shortlistedEntries = selectDiverseShortlist(shortlistCandidates, MAX_CONTEXT_PLACES);
    const placeById = new Map(allRows.map((row) => [row.id, row]));
    const placeContext = shortlistedEntries.map((entry) => ({
      id: entry.row.id,
      name: entry.row.name,
      category: entry.row.category,
      tags: entry.row.tags.split(',').map((tag) => tag.trim()).filter(Boolean),
      description: entry.row.description.slice(0, 180),
      facts: entry.row.factType,
      mood: entry.row.localVibeMood,
      bestFor: entry.row.localVibeBestFor,
      indoor: entry.row.isIndoor,
      familyFriendly: entry.row.isFamilyFriendly,
      rainyDayFit: entry.row.rainyDayFit,
      bestTime: entry.row.bestTime,
      seasonality: entry.row.seasonality,
      importanceTier: entry.row.importanceTier,
      imageVerified: entry.row.imageVerified,
      hoursVerified: entry.row.hoursVerified,
      distanceKm: entry.distanceKm != null ? Number(entry.distanceKm.toFixed(2)) : undefined,
      matchNotes: entry.reasons.slice(0, 3),
    }));

    try {
      const { object } = await generateObject({
        model: aiProvider.client.chat(aiProvider.model),
        maxOutputTokens: 420,
        schema: z.object({
          answer: z.string().describe('A short conversational reply in 1-2 sentences'),
          recommendations: z.array(
            z.object({
              id: z.string().describe('Place ID from the given list'),
              reason: z.string().describe('1-2 sentence custom explanation of match'),
            })
          ),
        }) as any,
        system: `You are a helpful local guide for Kristiansand.
Continue the conversation naturally using the recent chat history when it is provided.
Based on the user's request, pick 4 places when possible, or 5 when there are several strong matches.
Only return 3 when the request is unusually narrow.
Return ONLY places that exist in the provided shortlist. Use the exact ID.
Spread picks across the strongest relevant place types instead of returning near-duplicates.
Keep the answer concise and useful.

Recent conversation:
${conversationSummary || 'No prior conversation.'}

Available shortlist:
${JSON.stringify(placeContext, null, 2)}`,
        prompt: query,
      });

      const enrichedRecommendations = ((object as any).recommendations ?? [])
        .filter((rec: { id: string; reason: string }) => placeById.has(rec.id))
        .filter(
          (rec: { id: string; reason: string }, index: number, arr: Array<{ id: string; reason: string }>) =>
            arr.findIndex((entry) => entry.id === rec.id) === index
        )
        .map((rec: { id: string; reason: string }) => {
          const row = placeById.get(rec.id);
          if (!row) return null;
          return {
            ...toPlaceDto(row),
            aiReason: rec.reason,
          };
        })
        .filter(Boolean);

      if (enrichedRecommendations.length < MIN_AI_RECOMMENDATIONS) {
        for (const entry of shortlistedEntries) {
          if (enrichedRecommendations.length >= MAX_AI_RECOMMENDATIONS) break;
          if (
            enrichedRecommendations.some(
              (recommendation: ReturnType<typeof toPlaceDto> & { aiReason: string } | null) =>
                recommendation?.id === entry.row.id
            )
          ) {
            continue;
          }

          enrichedRecommendations.push({
            ...toPlaceDto(entry.row),
            aiReason: buildFallbackReason(entry, allRows, query, conversationSummary),
          });
        }
      }

      return {
        answer: (object as any).answer,
        recommendations: enrichedRecommendations,
      };
    } catch (e: any) {
      app.log.error(e);
      return reply.code(500).send({ error: e.message || 'Failed to generate recommendations' });
    }
  });

  return app;
}

async function main() {
  await connectDb();
  await ensureSchema();
  const app = await buildServer();
  let isShuttingDown = false;

  const shutdown = async (signal: string) => {
    if (isShuttingDown) return;
    isShuttingDown = true;

    app.log.info({ signal }, 'Shutting down');

    try {
      await app.close();
      process.exit(0);
    } catch (err) {
      app.log.error(err);
      process.exit(1);
    }
  };

  process.once('SIGINT', () => {
    void shutdown('SIGINT');
  });
  process.once('SIGTERM', () => {
    void shutdown('SIGTERM');
  });

  try {
    await app.listen({ port: PORT, host: '0.0.0.0' });
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

main();
