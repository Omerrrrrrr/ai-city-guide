export type ImageCandidateStatus = 'pending' | 'approved' | 'rejected' | 'applied';

export type ImageCandidate = {
  id: string;
  placeId: string;
  placeName: string;
  provider: string;
  status: ImageCandidateStatus;
  confidence: number;
  rank: number;
  searchQuery?: string;
  pageTitle: string;
  imageUrl: string;
  sourceUrl: string;
  sourceName?: string;
  imageLicense?: string;
  imageAttribution?: string;
  imageType: string;
  notes?: string;
  currentPlaceImage: {
    imageUrl: string;
    verified: boolean;
    sourceName?: string;
    imageType?: string;
  };
};

export type DiscoverImageCandidatesResponse = {
  discoveredPlaces: number;
  discoveredCandidates: number;
  results: {
    placeId: string;
    placeName: string;
    discoveredCount: number;
    topCandidate?: {
      id: string;
      pageTitle: string;
      confidence: number;
    };
  }[];
};
