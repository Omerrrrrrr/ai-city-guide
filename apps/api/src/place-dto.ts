import type { PlaceRow } from './schema';
import { parseOpeningHoursJson, type OpeningHoursData } from './opening-hours';

export type PlaceImageType = 'official' | 'tourism' | 'wikimedia' | 'user' | 'stock' | 'unknown';
export type PlaceImportanceTier = 'hero' | 'supporting' | 'long-tail';

export type PlaceDto = {
  id: string;
  name: string;
  category: string;
  tags: string[];
  description: string;
  imageUrl: string;
  image: {
    sourceUrl?: string;
    sourceName?: string;
    license?: string;
    attribution?: string;
    verified: boolean;
    type: PlaceImageType;
  };
  importanceTier: PlaceImportanceTier;
  shortStory: string;
  verifiedFacts: {
    address?: string;
    type?: string;
    priceLevel?: string;
    sourceUrl?: string;
  };
  visitInfo: {
    durationMinutes?: number;
    hoursNote?: string;
    openingHours?: OpeningHoursData;
    hoursVerified: boolean;
    hoursSourceUrl?: string;
    hoursLastCheckedAt?: string;
    bestTime?: string;
    seasonality?: string;
    temporarilyClosed: boolean;
  };
  localVibe: {
    mood?: string;
    bestFor?: string;
  };
  city: string;
  country?: string;
  wiki?: {
    pageTitle?: string;
    pageUrl?: string;
    summary?: string;
    confidence?: number;
    status?: 'matched' | 'not-found';
    rawMetadata?: Record<string, unknown>;
  };
  location?: {
    lat: number;
    lng: number;
  };
};

export function toPlaceDto(row: PlaceRow): PlaceDto {
  const openingHours = parseOpeningHoursJson(row.openingHoursJson);
  let rawWikiMetadata: Record<string, unknown> | undefined;

  if (row.wikiRawMetadataJson) {
    try {
      rawWikiMetadata = JSON.parse(row.wikiRawMetadataJson);
    } catch {
      rawWikiMetadata = undefined;
    }
  }

  return {
    id: row.id,
    name: row.name,
    category: row.category,
    tags: row.tags
      .split(',')
      .map((tag) => tag.trim())
      .filter(Boolean),
    description: row.description,
    imageUrl: row.imageUrl,
    image: {
      sourceUrl: row.imageSourceUrl ?? undefined,
      sourceName: row.imageSourceName ?? undefined,
      license: row.imageLicense ?? undefined,
      attribution: row.imageAttribution ?? undefined,
      verified: row.imageVerified,
      type: (row.imageType as PlaceImageType) ?? 'unknown',
    },
    importanceTier: (row.importanceTier as PlaceImportanceTier) ?? 'supporting',
    shortStory: row.shortStory,
    verifiedFacts: {
      address: row.address ?? undefined,
      type: row.factType ?? undefined,
      priceLevel: row.priceLevel ?? undefined,
      sourceUrl: row.sourceUrl ?? undefined,
    },
    visitInfo: {
      durationMinutes: row.durationMinutes ?? undefined,
      hoursNote: row.hoursNote ?? undefined,
      openingHours,
      hoursVerified: row.hoursVerified ?? false,
      hoursSourceUrl: row.hoursSourceUrl ?? undefined,
      hoursLastCheckedAt: row.hoursLastCheckedAt ?? undefined,
      bestTime: row.bestTime ?? undefined,
      seasonality: row.seasonality ?? undefined,
      temporarilyClosed: row.temporarilyClosed ?? false,
    },
    localVibe: {
      mood: row.localVibeMood ?? undefined,
      bestFor: row.localVibeBestFor ?? undefined,
    },
    city: row.city,
    country: row.country ?? undefined,
    wiki:
      row.wikiStatus || row.wikiSummary || row.wikiPageTitle || row.wikiPageUrl
        ? {
            pageTitle: row.wikiPageTitle ?? undefined,
            pageUrl: row.wikiPageUrl ?? undefined,
            summary: row.wikiSummary ?? undefined,
            confidence: row.wikiMatchConfidence ?? undefined,
            status:
              row.wikiStatus === 'matched' || row.wikiStatus === 'not-found'
                ? row.wikiStatus
                : undefined,
            rawMetadata: rawWikiMetadata,
          }
        : undefined,
    location:
      row.lat != null && row.lng != null
        ? { lat: row.lat, lng: row.lng }
        : undefined,
  };
}
