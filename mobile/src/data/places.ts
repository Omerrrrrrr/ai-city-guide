export type PlaceImageType = 'official' | 'tourism' | 'wikimedia' | 'user' | 'stock' | 'unknown';
export type PlaceImportanceTier = 'hero' | 'supporting' | 'long-tail';
export type OpeningHoursDayKey = '0' | '1' | '2' | '3' | '4' | '5' | '6';
export type OpeningHoursRange = {
  start: string;
  end: string;
};
export type OpeningHoursData = {
  timezone: string;
  mode: 'always-open' | 'scheduled';
  days: Record<OpeningHoursDayKey, OpeningHoursRange[]>;
};

export type PlaceGalleryImage = {
  id: string;
  imageUrl: string;
  sourceUrl?: string;
  sourceName?: string;
  license?: string;
  attribution?: string;
  verified: boolean;
  type: PlaceImageType;
  status: 'applied' | 'approved' | 'pending';
  confidence: number;
  pageTitle?: string;
  notes?: string;
};

export type Place = {
  id: string;
  name: string;
  category: PlaceCategory;
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
  gallery?: PlaceGalleryImage[];
  importanceTier: PlaceImportanceTier;
  shortStory: string;
  verifiedFacts?: {
    address?: string;
    type?: string;
    priceLevel?: string;
    sourceUrl?: string;
  };
  visitInfo?: {
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
  localVibe?: {
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

export type PlaceCategory =
  | 'landmark'
  | 'museum'
  | 'cultural-spot'
  | 'square-street'
  | 'beach'
  | 'walking-area'
  | 'cafe'
  | 'restaurant'
  | 'viewpoint'
  | 'shopping-area'
  | 'lodging'
  | 'nature';
