import 'dotenv/config';

import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { eq, ilike } from 'drizzle-orm';
import { generateObject, generateText } from 'ai';
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
import { createSlug } from './slug';
import { discoverPlacesForCity, retryImagesForCity } from './place-discovery-service';
import { haversineKm } from './geo';
import { places, cities } from './schema';

const PORT = Number(process.env.PORT ?? 4000);
const OPENAI_API_KEY = process.env.OPENAI_API_KEY?.trim();
const OPENAI_MODEL = process.env.OPENAI_MODEL ?? 'gpt-4o-mini';
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY?.trim();
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL ?? 'anthropic/claude-sonnet-4.5';
const APP_URL = process.env.APP_URL ?? 'http://localhost:4000';
const OPENWEATHER_API_KEY = process.env.OPENWEATHER_API_KEY?.trim();
const MAX_CONTEXT_PLACES = 14;
const MIN_AI_RECOMMENDATIONS = 4;
const MAX_AI_RECOMMENDATIONS = 5;
const AI_PROVIDER = process.env.AI_PROVIDER?.trim().toLowerCase();
const ADMIN_API_TOKEN = process.env.ADMIN_API_TOKEN?.trim() || undefined;
const CORS_ORIGINS = (process.env.CORS_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);
const DEFAULT_DEV_CORS_ORIGINS = ['http://localhost:8081', 'http://localhost:19006'];

function validateEnv() {
  const result = z
    .object({ DATABASE_URL: z.string().trim().min(1, 'DATABASE_URL is required') })
    .safeParse(process.env);

  if (!result.success) {
    for (const issue of result.error.issues) {
      console.error(`Invalid environment configuration - ${issue.path.join('.')}: ${issue.message}`);
    }
    process.exit(1);
  }

  if (!ADMIN_API_TOKEN) {
    console.warn(
      'ADMIN_API_TOKEN is not set. All /admin/* routes will respond 503 until it is configured.'
    );
  }
}

function isAdminPath(url: string) {
  const path = url.split('?')[0];
  return path === '/admin' || path.startsWith('/admin/');
}
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

async function geocodeCityName(query: string) {
  const params = new URLSearchParams({
    format: 'jsonv2',
    q: query,
    featureType: 'city',
    addressdetails: '1',
    limit: '5',
  });

  const response = await fetch(`https://nominatim.openstreetmap.org/search?${params.toString()}`, {
    headers: {
      'User-Agent': 'AI City Guide/1.0',
      Accept: 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error(`City geocode failed with ${response.status}`);
  }

  const results = (await response.json()) as Array<{
    display_name: string;
    lat: string;
    lon: string;
    address?: { city?: string; town?: string; village?: string; country?: string };
  }>;

  return results.map((result) => ({
    name:
      result.address?.city || result.address?.town || result.address?.village || result.display_name.split(',')[0],
    country: result.address?.country ?? '',
    displayName: result.display_name,
    lat: Number(result.lat),
    lng: Number(result.lon),
  }));
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

  await app.register(cors, {
    origin: CORS_ORIGINS.length > 0 ? CORS_ORIGINS : DEFAULT_DEV_CORS_ORIGINS,
  });
  await app.register(rateLimit, { max: 120, timeWindow: '1 minute' });

  app.addHook('onRequest', async (request, reply) => {
    if (!isAdminPath(request.url)) return;

    if (!ADMIN_API_TOKEN) {
      return reply.code(503).send({
        error: 'Admin routes are disabled. Set ADMIN_API_TOKEN in the backend environment to enable them.',
      });
    }

    const [scheme, token] = (request.headers.authorization ?? '').split(' ');
    if (scheme !== 'Bearer' || token !== ADMIN_API_TOKEN) {
      return reply.code(401).send({ error: 'Unauthorized' });
    }
  });

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

  app.get<{
    Querystring: { city?: string };
  }>('/places', async (request) => {
    const city = request.query?.city?.trim();
    const rows = city ? await db.select().from(places).where(ilike(places.city, city)) : await db.select().from(places);
    return rows.map(toPlaceDto);
  });

  app.get<{
    Querystring: { q?: string; query?: string };
  }>('/cities', async (request, reply) => {
    const query = (request.query?.q ?? request.query?.query)?.trim();
    if (!query || query.length < 2) {
      return reply.code(400).send({ error: 'A query of at least 2 characters is required.' });
    }

    const knownCities = await db.select().from(cities).where(ilike(cities.name, `%${query}%`)).limit(5);
    if (knownCities.length > 0) {
      return { cities: knownCities.map((city) => ({ ...city, isKnown: true })) };
    }

    try {
      const geocoded = await geocodeCityName(query);
      return {
        cities: geocoded.map((result) => ({
          id: null,
          name: result.name,
          country: result.country,
          centerLat: result.lat,
          centerLng: result.lng,
          status: 'discoverable',
          isKnown: false,
        })),
      };
    } catch (error: any) {
      request.log.error(error);
      return reply.code(502).send({ error: error?.message ?? 'City search failed' });
    }
  });

  app.get<{
    Params: { id: string };
  }>('/cities/:id', async (request, reply) => {
    const city = await db.query.cities.findFirst({ where: eq(cities.id, request.params.id) });
    if (!city) {
      return reply.code(404).send({ error: 'City not found' });
    }
    return city;
  });

  app.post<{
    Body: { name: string; country?: string; lat: number; lng: number; radiusKm?: number };
  }>('/cities/discover', async (request, reply) => {
    const parsedBody = z
      .object({
        name: z.string().trim().min(1),
        country: z.string().trim().optional(),
        lat: z.number().min(-90).max(90),
        lng: z.number().min(-180).max(180),
        radiusKm: z.number().min(1).max(25).optional(),
      })
      .safeParse(request.body ?? {});

    if (!parsedBody.success) {
      return reply.code(400).send({ error: parsedBody.error.issues[0]?.message ?? 'Invalid request' });
    }

    const { name, country, lat, lng, radiusKm } = parsedBody.data;

    const nearbyExisting = await db.select().from(cities);
    // Use 8 km to de-duplicate queries for the same city (e.g. slightly
    // different Nominatim results), but small enough that distinct nearby
    // towns like Søgne vs Kristiansand each get their own discovery pass.
    const existing = nearbyExisting.find(
      (city) => haversineKm(lat, lng, city.centerLat, city.centerLng) <= 8
    );

    if (existing) {
      if (existing.status === 'ready' || existing.status === 'discovering') {
        return reply.code(200).send(existing);
      }
    }

    const cityId = existing?.id ?? `${createSlug(name)}-${Date.now().toString(36)}`;

    if (existing) {
      await db.update(cities).set({ status: 'pending', errorMessage: null }).where(eq(cities.id, cityId));
    } else {
      await db.insert(cities).values({
        id: cityId,
        name,
        country: country ?? null,
        centerLat: lat,
        centerLng: lng,
        radiusKm: radiusKm ?? 8,
        status: 'pending',
      });
    }

    const aiProvider = getAiProviderConfig();
    discoverPlacesForCity({ cityId, cityName: name, country, lat, lng, radiusKm, aiProvider }).catch((error) => {
      app.log.error(error, `Background discovery failed for city ${cityId}`);
    });

    const created = await db.query.cities.findFirst({ where: eq(cities.id, cityId) });
    return reply.code(202).send(created);
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

  app.post<{
    Params: { cityId: string };
  }>('/admin/cities/:cityId/rediscover', async (request, reply) => {
    const { cityId } = request.params;
    const city = await db.query.cities.findFirst({ where: eq(cities.id, cityId) });
    if (!city) return reply.code(404).send({ error: 'City not found' });

    await db.update(cities).set({ status: 'pending', errorMessage: null }).where(eq(cities.id, cityId));
    const aiProvider = getAiProviderConfig();
    discoverPlacesForCity({
      cityId,
      cityName: city.name,
      country: city.country ?? undefined,
      lat: city.centerLat,
      lng: city.centerLng,
      radiusKm: city.radiusKm,
      aiProvider,
    }).catch((err) => app.log.error(err, `Rediscovery failed for city ${cityId}`));

    return reply.code(202).send({ message: `Rediscovery started for ${city.name}` });
  });

  app.post<{
    Params: { cityId: string };
  }>('/admin/cities/:cityId/retry-images', async (request, reply) => {
    const { cityId } = request.params;
    const city = await db.query.cities.findFirst({ where: eq(cities.id, cityId) });
    if (!city) return reply.code(404).send({ error: 'City not found' });

    retryImagesForCity(cityId).catch((err) =>
      app.log.error(err, `Image retry failed for city ${cityId}`)
    );

    return reply.code(202).send({ message: `Image retry started for ${city.name}` });
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

  // ── /places/identify — Vision AI: photo + profile → personalized explanation ──
  app.post<{
    Body: {
      imageBase64: string;
      mimeType?: string;
      lat?: number;
      lng?: number;
      userProfile?: {
        name?: string;
        profession?: string;
        interests?: string[];
        faith?: string;
      };
    };
  }>(
    '/places/identify',
    { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } },
    async (request, reply) => {
      const parsedBody = z
        .object({
          imageBase64: z.string().min(1),
          mimeType: z.string().optional().default('image/jpeg'),
          lat: z.number().optional(),
          lng: z.number().optional(),
          userProfile: z
            .object({
              name: z.string().optional(),
              profession: z.string().optional(),
              interests: z.array(z.string()).optional(),
              faith: z.string().optional(),
            })
            .optional(),
        })
        .safeParse(request.body);

      if (!parsedBody.success) {
        return reply.code(400).send({ error: 'Invalid request body' });
      }

      const { imageBase64, mimeType, lat, lng, userProfile } = parsedBody.data;
      const aiProvider = getAiProviderConfig();

      if (!aiProvider) {
        return reply.code(500).send({ error: 'AI is not configured in the backend' });
      }

      // Location is a disambiguation aid, never the sole source of truth — the
      // photo itself always decides. We fetch nearby known places once and reuse
      // the same list both as vision hints and as the preferred fuzzy-match pool.
      let nearbyPlaces: { id: string; name: string; category: string }[] = [];
      let allPlacesForMatch: { id: string; name: string }[] = [];
      if (lat != null && lng != null) {
        try {
          const geoRows = await db
            .select({ id: places.id, name: places.name, category: places.category, lat: places.lat, lng: places.lng })
            .from(places);
          allPlacesForMatch = geoRows;
          nearbyPlaces = geoRows
            .filter((p) => p.lat != null && p.lng != null)
            .map((p) => ({ ...p, distanceKm: haversineKm(lat, lng, p.lat!, p.lng!) }))
            .filter((p) => p.distanceKm <= 0.6)
            .sort((a, b) => a.distanceKm - b.distanceKm)
            .slice(0, 6)
            .map(({ id, name, category }) => ({ id, name, category }));
        } catch { /* non-critical */ }
      }

      const profileLines: string[] = [];
      if (userProfile?.name) profileLines.push(`Name: ${userProfile.name}`);
      if (userProfile?.profession && userProfile.profession !== 'other') {
        profileLines.push(`Profession: ${userProfile.profession}`);
      }
      if (userProfile?.interests?.length) {
        profileLines.push(`Interests: ${userProfile.interests.join(', ')}`);
      }
      if (userProfile?.faith && userProfile.faith !== 'prefer_not_to_say') {
        profileLines.push(
          userProfile.faith === 'secular'
            ? 'Worldview: secular / non-religious'
            : `Faith: ${userProfile.faith}`
        );
      }

      const profileContext =
        profileLines.length > 0
          ? `\n\nUser profile:\n${profileLines.join('\n')}\n\nTailor every sentence to this specific person. An architect should hear about structure and engineering. A Muslim should hear about religious significance. A historian should hear about historical layers. A photographer should hear about light, composition, and visual opportunities. Be specific, not generic.`
          : '';

      const nearbyHint =
        nearbyPlaces.length > 0
          ? ` Known nearby places (within ~600m): ${nearbyPlaces
              .map((p) => `"${p.name}" (${p.category})`)
              .join(', ')}. If the photo genuinely matches one of these, use its exact name.`
          : '';
      const locationHint =
        lat != null && lng != null
          ? ` The user is near coordinates ${lat.toFixed(5)}, ${lng.toFixed(5)}.${nearbyHint} Treat location only as a hint to disambiguate similar-looking places — the photo is the primary evidence. Never identify a place from location alone; if the image doesn't support a nearby candidate, ignore it and describe what the image actually shows.`
          : '';

      try {
        const identifySchema = z.object({
          title: z.string().describe('Name of the place or object (e.g. "Hagia Sophia", "A street café")'),
          subtitle: z.string().describe('One-line category or type (e.g. "Byzantine cathedral turned mosque", "Seaside café")'),
          explanation: z
            .string()
            .describe('3-5 sentence rich explanation tailored to the user profile. If no profile, give a balanced cultural overview.'),
          highlights: z
            .array(z.string())
            .min(2)
            .max(4)
            .describe('2-4 specific highlights relevant to this user. Short, punchy sentences.'),
        });
        const { object } = (await generateObject({
          model: aiProvider.client.chat(aiProvider.model),
          schema: identifySchema,
          messages: [
            {
              role: 'user',
              content: [
                {
                  type: 'image',
                  image: imageBase64,
                  mimeType: mimeType as 'image/jpeg' | 'image/png' | 'image/webp',
                },
                {
                  type: 'text',
                  text: `What is this place? ${locationHint}`,
                },
              ],
            },
          ],
          system: `You are Piri, a deeply knowledgeable personal travel guide. You identify places from photos and explain them in a way that speaks directly to who the user is.${profileContext}`,
        } as any)) as { object: z.infer<typeof identifySchema> };

        // Fuzzy-match the identified title against DB places. Nearby places are
        // checked first (more reliable when GPS is available and multiple places
        // share similar names across cities), falling back to a global search.
        let matchedPlaceId: string | undefined;
        try {
          const normalise = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, '');
          const needle = normalise(object.title);

          for (const p of nearbyPlaces) {
            const hay = normalise(p.name);
            if (hay === needle || hay.includes(needle) || needle.includes(hay)) {
              matchedPlaceId = p.id;
              break;
            }
          }

          if (!matchedPlaceId) {
            const searchPool = allPlacesForMatch.length > 0
              ? allPlacesForMatch
              : await db.select({ id: places.id, name: places.name }).from(places);
            for (const p of searchPool) {
              const hay = normalise(p.name);
              if (hay === needle || hay.includes(needle) || needle.includes(hay)) {
                matchedPlaceId = p.id;
                break;
              }
            }
          }
        } catch { /* non-critical */ }

        return reply.send({ ...object, matchedPlaceId });
      } catch (e: any) {
        app.log.error(e);
        return reply.code(500).send({ error: e.message || 'Failed to identify place' });
      }
    }
  );

  // ── /places/explain — Personalized AI explanation for a known place ──────────
  app.post<{
    Body: {
      placeId: string;
      userProfile?: {
        name?: string;
        profession?: string;
        interests?: string[];
        faith?: string;
      };
    };
  }>(
    '/places/explain',
    { config: { rateLimit: { max: 40, timeWindow: '1 minute' } } },
    async (request, reply) => {
      const parsed = z
        .object({
          placeId: z.string().min(1),
          userProfile: z
            .object({
              name: z.string().optional(),
              profession: z.string().optional(),
              interests: z.array(z.string()).optional(),
              faith: z.string().optional(),
            })
            .optional(),
        })
        .safeParse(request.body);

      if (!parsed.success) {
        return reply.code(400).send({ error: 'Invalid request' });
      }

      const { placeId, userProfile } = parsed.data;
      const aiProvider = getAiProviderConfig();
      if (!aiProvider) {
        return reply.code(503).send({ error: 'AI not configured' });
      }

      const [placeRow] = await db.select().from(places).where(eq(places.id, placeId)).limit(1);
      if (!placeRow) return reply.code(404).send({ error: 'Place not found' });

      const profileLines: string[] = [];
      if (userProfile?.name) profileLines.push(`Name: ${userProfile.name}`);
      if (userProfile?.profession && userProfile.profession !== 'other') {
        profileLines.push(`Profession: ${userProfile.profession}`);
      }
      if (userProfile?.interests?.length) {
        profileLines.push(`Interests: ${userProfile.interests.join(', ')}`);
      }
      if (userProfile?.faith && userProfile.faith !== 'prefer_not_to_say') {
        profileLines.push(
          userProfile.faith === 'secular'
            ? 'Worldview: secular / non-religious'
            : `Faith: ${userProfile.faith}`
        );
      }

      const hasProfile = profileLines.length > 0;
      const profileContext = hasProfile
        ? `\n\nUser profile:\n${profileLines.join('\n')}`
        : '';

      const placeContext = [
        `Name: ${placeRow.name}`,
        `Category: ${placeRow.category}`,
        `Description: ${placeRow.description}`,
        placeRow.shortStory ? `Story: ${placeRow.shortStory}` : null,
        placeRow.tags ? `Tags: ${placeRow.tags}` : null,
        placeRow.factType ? `Type/Facts: ${placeRow.factType}` : null,
        placeRow.localVibeMood ? `Vibe: ${placeRow.localVibeMood}` : null,
        placeRow.localVibeBestFor ? `Best for: ${placeRow.localVibeBestFor}` : null,
        placeRow.rainyDayFit != null ? `Rainy day fit: ${placeRow.rainyDayFit}` : null,
        placeRow.isIndoor != null ? `Indoor: ${placeRow.isIndoor}` : null,
      ]
        .filter(Boolean)
        .join('\n');

      const personalization = hasProfile
        ? `Speak directly to this person. A ${userProfile?.profession ?? 'visitor'} should hear what they uniquely care about — structural details for an architect, spiritual layers for a person of faith, historical depth for a historian. Be specific. Avoid generic tourist-guide language.`
        : `Give a warm, engaging overview that a curious traveler would enjoy.`;

      try {
        const { object } = await generateObject({
          model: aiProvider.client.chat(aiProvider.model),
          maxOutputTokens: 300,
          schema: z.object({
            headline: z
              .string()
              .describe('One punchy sentence that connects this place to who the user is. Max 12 words.'),
            body: z
              .string()
              .describe('2-3 sentences of personalized insight. Speak directly to this person\'s expertise or interests.'),
            highlights: z
              .array(z.string())
              .min(2)
              .max(3)
              .describe('2-3 specific things this particular person would find most interesting here.'),
          }),
          system: `You are Piri, a deeply knowledgeable personal travel guide. Your job is to explain a place in a way that speaks directly to who the user is — their profession, interests, and worldview.${profileContext}

${personalization}`,
          prompt: `Explain this place:\n\n${placeContext}`,
        } as any);

        return reply.send(object);
      } catch (e: any) {
        app.log.error(e);
        return reply.code(500).send({ error: e.message || 'Failed to explain place' });
      }
    }
  );

  // ── /places/recommend ────────────────────────────────────────────────────────
  app.post<{
    Body: {
      query: string;
      city?: string;
      lat?: number;
      lng?: number;
      imageBase64?: string;
      mimeType?: string;
      messages?: Array<{ role: 'user' | 'assistant'; content: string }>;
      userProfile?: {
        name?: string;
        profession?: string;
        interests?: string[];
        faith?: string;
      };
      weather?: {
        condition: string;
        temp: number;
        city: string;
        description: string;
      };
    };
  }>('/places/recommend', { config: { rateLimit: { max: 12, timeWindow: '1 minute' } } }, async (request, reply) => {
    const parsedBody = z
      .object({
        query: z.string().trim().min(1, 'Query is required'),
        city: z.string().trim().min(1).optional(),
        lat: z.number().optional(),
        lng: z.number().optional(),
        imageBase64: z.string().min(1).optional(),
        mimeType: z.string().optional().default('image/jpeg'),
        messages: z.array(chatMessageSchema).max(8).optional(),
        userProfile: z
          .object({
            name: z.string().optional(),
            profession: z.string().optional(),
            interests: z.array(z.string()).optional(),
            faith: z.string().optional(),
          })
          .optional(),
        weather: z
          .object({
            condition: z.string(),
            temp: z.number(),
            city: z.string(),
            description: z.string(),
          })
          .optional(),
      })
      .safeParse(request.body);

    if (!parsedBody.success) {
      return reply.code(400).send({ error: parsedBody.error.issues[0]?.message ?? 'Invalid request' });
    }

    const { query, city, lat, lng, imageBase64, mimeType, messages = [], userProfile, weather } = parsedBody.data;

    const profileLines: string[] = [];
    if (userProfile?.profession && userProfile.profession !== 'other') {
      profileLines.push(`Profession: ${userProfile.profession}`);
    }
    if (userProfile?.interests?.length) {
      profileLines.push(`Interests: ${userProfile.interests.join(', ')}`);
    }
    if (userProfile?.faith && userProfile.faith !== 'prefer_not_to_say') {
      profileLines.push(
        userProfile.faith === 'secular' ? 'Worldview: secular' : `Faith: ${userProfile.faith}`
      );
    }
    const profileContext =
      profileLines.length > 0
        ? `\n\nUser profile:\n${profileLines.join('\n')}\nPersonalize your answer to this person.`
        : '';

    const weatherContext = weather
      ? `\n\nCurrent weather: ${weather.description}, ${weather.temp}°C in ${weather.city}. Condition: ${weather.condition}. ${
          weather.condition === 'rainy' || weather.condition === 'stormy'
            ? 'Strongly prefer indoor venues unless the user specifically asks for outdoor.'
            : weather.condition === 'sunny' && weather.temp > 18
            ? 'Great weather for outdoor venues — highlight terraces, parks, and waterfront spots.'
            : weather.condition === 'snowy'
            ? 'Prefer indoor or cozy venues given the snow.'
            : ''
        }`
      : '';

    const aiProvider = getAiProviderConfig();

    if (!aiProvider) {
      return reply.code(500).send({
        error: 'OPENAI_API_KEY or OPENROUTER_API_KEY is not configured in the backend',
      });
    }

    const allRows = city ? await db.select().from(places).where(ilike(places.city, city)) : await db.select().from(places);
    const cityLabel = city ?? allRows[0]?.city ?? 'this city';
    const conversationSummary = messages
      .slice(-6)
      .map((message) => `${message.role.toUpperCase()}: ${message.content}`)
      .join('\n');
    const userLocation = lat != null && lng != null ? { lat, lng } : undefined;
    const rankedRows = rankPlacesForQuery(allRows, query, conversationSummary, userLocation);
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
      const imageInstructions = imageBase64
        ? `\n\nThe user attached a photo along with their message. Look at it and answer their question with what the photo actually shows — identify it if that's what they're asking, or use it as context for their question. If it clearly matches a place in your shortlist, include that place in recommendations; don't force a match if it doesn't.`
        : '';

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
        system: `You are Piri, a personal travel guide.${profileContext}${weatherContext}
Continue the conversation naturally using the recent chat history when provided.
Keep answers concise (1–3 sentences) and personalized to the user.${imageInstructions}

${placeContext.length > 0
  ? `You have ${placeContext.length} places in your database for ${cityLabel}. Pick 4 places when possible, 5 when there are several strong matches, 3 when unusually narrow. Return ONLY places from the provided shortlist using exact IDs. Spread picks across different place types.`
  : `You have NO places in your database for ${cityLabel} yet. Answer from your own knowledge — give a helpful, accurate response about the place or question. Tell the user you don't have ${cityLabel} mapped yet and suggest they use city search to trigger discovery. Return an empty recommendations array.`
}

Recent conversation:
${conversationSummary || 'No prior conversation.'}

${placeContext.length > 0 ? `Available shortlist:\n${JSON.stringify(placeContext, null, 2)}` : ''}`,
        ...(imageBase64
          ? {
              messages: [
                {
                  role: 'user' as const,
                  content: [
                    { type: 'image' as const, image: imageBase64, mimeType },
                    { type: 'text' as const, text: query },
                  ],
                },
              ],
            }
          : { prompt: query }),
      } as any);

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

  // ── /weather — Proxy OpenWeatherMap current conditions ───────────────────────
  app.get<{ Querystring: { lat: string; lng: string } }>(
    '/weather',
    { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } },
    async (request, reply) => {
      const parsedLat = parseFloat(request.query.lat ?? '');
      const parsedLng = parseFloat(request.query.lng ?? '');

      if (isNaN(parsedLat) || isNaN(parsedLng)) {
        return reply.code(400).send({ error: 'lat and lng query params are required' });
      }

      if (!OPENWEATHER_API_KEY) {
        return reply.code(503).send({ error: 'Weather not configured' });
      }

      try {
        const owUrl = `https://api.openweathermap.org/data/2.5/weather?lat=${parsedLat}&lon=${parsedLng}&units=metric&appid=${OPENWEATHER_API_KEY}`;
        const res = await fetch(owUrl);
        if (!res.ok) throw new Error(`OpenWeather ${res.status}`);
        const data = await res.json() as any;

        const weatherId: number = data.weather?.[0]?.id ?? 800;
        type WeatherCondition = 'sunny' | 'cloudy' | 'rainy' | 'snowy' | 'stormy' | 'foggy';
        let condition: WeatherCondition;
        if (weatherId >= 200 && weatherId < 300) condition = 'stormy';
        else if (weatherId >= 300 && weatherId < 600) condition = 'rainy';
        else if (weatherId >= 600 && weatherId < 700) condition = 'snowy';
        else if (weatherId >= 700 && weatherId < 800) condition = 'foggy';
        else if (weatherId === 800) condition = 'sunny';
        else condition = 'cloudy';

        return reply.send({
          city: data.name as string,
          temp: Math.round(data.main.temp as number),
          feels_like: Math.round(data.main.feels_like as number),
          condition,
          description: (data.weather?.[0]?.description ?? '') as string,
          humidity: data.main.humidity as number,
          wind_speed: Math.round((data.wind?.speed ?? 0) as number),
        });
      } catch (e: any) {
        app.log.error(e);
        return reply.code(500).send({ error: 'Failed to fetch weather' });
      }
    }
  );

  return app;
}

async function main() {
  validateEnv();
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
