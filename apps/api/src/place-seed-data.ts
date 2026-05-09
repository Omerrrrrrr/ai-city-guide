import { places } from './schema';

type PlaceInsert = typeof places.$inferInsert;
type BasePlaceInsert = Omit<
  PlaceInsert,
  | 'imageSourceUrl'
  | 'imageSourceName'
  | 'imageLicense'
  | 'imageAttribution'
  | 'imageVerified'
  | 'imageType'
  | 'importanceTier'
>;

const KRISTIANSAND_PLAN_URL =
  'https://www.visitnorway.com/places-to-go/southern-norway/kristiansand/plan-your-trip/';
const KRISTIANSAND_FOOD_AND_DRINK_URL =
  'https://www.visitnorway.com/places-to-go/southern-norway/kristiansand/food-and-drink/';
const KRISTIANSAND_THINGS_TO_DO_URL =
  'https://www.visitnorway.com/places-to-go/southern-norway/kristiansand/things-to-do/';

const HERO_PLACE_IDS = new Set([
  'posebyen',
  'kristiansand-cathedral',
  'fiskebrygga',
  'bystranda',
  'kilden-theatre',
  'kunstsilo',
  'odderoya',
  'vitensenteret-kristiansand',
  'aquarama-waterpark',
  'hamresanden',
  'dyreparken',
]);

const LONG_TAIL_PLACE_IDS = new Set([
  'gimle-gard',
  'kristiansand-kunsthall',
  'christiansholm-fortress',
  'odderoya-lighthouse',
  'oddernes-church',
  'kristiansand-marina-cafe',
  'cafe-rasmus',
  'radhuscafeen',
  'odderoya-museumshavn',
  'kristiansand-marina',
  'spiren-kafe',
  'blaud-sauna',
]);

type VerifiedImageOverride = Pick<
  PlaceInsert,
  | 'imageUrl'
  | 'imageSourceUrl'
  | 'imageSourceName'
  | 'imageLicense'
  | 'imageAttribution'
  | 'imageVerified'
  | 'imageType'
>;

function wikimediaOverride({
  imageUrl,
  sourceUrl,
  artist,
  license,
}: {
  imageUrl: string;
  sourceUrl: string;
  artist: string;
  license: string;
}): VerifiedImageOverride {
  return {
    imageUrl,
    imageSourceUrl: sourceUrl,
    imageSourceName: 'Wikimedia Commons',
    imageLicense: license,
    imageAttribution: `Photo by ${artist} via Wikimedia Commons (${license}).`,
    imageVerified: true,
    imageType: 'wikimedia',
  };
}

const VERIFIED_IMAGE_OVERRIDES: Partial<Record<string, VerifiedImageOverride>> = {
  posebyen: wikimediaOverride({
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/d/dc/Posebyen_i_Kristiansand.jpg',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Posebyen_i_Kristiansand.jpg',
    artist: 'Knut Arne Gjertsen',
    license: 'CC BY-SA 4.0',
  }),
  'kristiansand-cathedral': wikimediaOverride({
    imageUrl:
      'https://upload.wikimedia.org/wikipedia/commons/d/d1/Domkirken_Kristiansand_NORWAY_nygotisk_Thrap-Meyer_1885_Cathedral_Neo-Gothic_church_2023-10-18_Torvet_Fontenen_Portal_T%C3%A5rn_tower_etc_IMG_4085.jpg',
    sourceUrl:
      'https://commons.wikimedia.org/wiki/File:Domkirken_Kristiansand_NORWAY_nygotisk_Thrap-Meyer_1885_Cathedral_Neo-Gothic_church_2023-10-18_Torvet_Fontenen_Portal_T%C3%A5rn_tower_etc_IMG_4085.jpg',
    artist: 'Wolfmann',
    license: 'CC BY-SA 4.0',
  }),
  fiskebrygga: wikimediaOverride({
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/c/c3/Fiskebrygga%2C_Kristiansand.jpg',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Fiskebrygga,_Kristiansand.jpg',
    artist: 'Sierra200',
    license: 'CC BY-SA 4.0',
  }),
  bystranda: wikimediaOverride({
    imageUrl:
      'https://upload.wikimedia.org/wikipedia/commons/9/98/Bystranda_-_Kristiansand%2C_Norway_2021-08-12_%2801%29.jpg',
    sourceUrl:
      'https://commons.wikimedia.org/wiki/File:Bystranda_-_Kristiansand,_Norway_2021-08-12_(01).jpg',
    artist: 'Ryan Hodnett',
    license: 'CC BY-SA 4.0',
  }),
  kunstsilo: wikimediaOverride({
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/d/d4/Kunstsilo_%28Kristiansand%29.jpg',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Kunstsilo_(Kristiansand).jpg',
    artist: 'Orf3us',
    license: 'CC BY-SA 4.0',
  }),
  'christiansholm-fortress': wikimediaOverride({
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/e/ea/Christiansholm_Fortress.JPG',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Christiansholm_Fortress.JPG',
    artist: 'Carsten R D',
    license: 'CC BY-SA 4.0',
  }),
  'oddernes-church': wikimediaOverride({
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/c/c6/Oddernes_kirke_13_februari_2024.jpg',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Oddernes_kirke_13_februari_2024.jpg',
    artist: 'David Castor',
    license: 'CC0',
  }),
  'aquarama-waterpark': wikimediaOverride({
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/5/5c/Aquarama_21072014.JPG',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Aquarama_21072014.JPG',
    artist: 'Carsten R D',
    license: 'CC BY-SA 4.0',
  }),
  arkivet: wikimediaOverride({
    imageUrl:
      'https://upload.wikimedia.org/wikipedia/commons/0/01/ARKIVET_Peace_and_Human_Rights_Centre_Kristiansand%2C_NORWAY._WWII_Memorial%2C_Minnebauta_over_falne_fra_Agder_1940-45%2C_Vesterveien_4%2C_Bellevue_2023-10-17_IMG_3674.jpg',
    sourceUrl:
      'https://commons.wikimedia.org/wiki/File:ARKIVET_Peace_and_Human_Rights_Centre_Kristiansand,_NORWAY._WWII_Memorial,_Minnebauta_over_falne_fra_Agder_1940-45,_Vesterveien_4,_Bellevue_2023-10-17_IMG_3674.jpg',
    artist: 'Wolfmann',
    license: 'CC BY-SA 4.0',
  }),
};

function getImportanceTier(placeId: string): PlaceInsert['importanceTier'] {
  if (HERO_PLACE_IDS.has(placeId)) return 'hero';
  if (LONG_TAIL_PLACE_IDS.has(placeId)) return 'long-tail';
  return 'supporting';
}

function getLegacyImageType(imageUrl: string): PlaceInsert['imageType'] {
  if (imageUrl.includes('picsum.photos') || imageUrl.includes('unsplash.com')) {
    return 'stock';
  }

  return 'unknown';
}

function getLegacyImageSourceName(imageUrl: string): string {
  if (imageUrl.includes('picsum.photos')) {
    return 'Picsum placeholder image';
  }

  if (imageUrl.includes('unsplash.com')) {
    return 'Unsplash legacy seed image';
  }

  return 'Unverified seed image';
}

function hasTag(place: BasePlaceInsert, tag: string) {
  return place.tags
    .split(',')
    .map((entry) => entry.trim().toLowerCase())
    .includes(tag.toLowerCase());
}

const TAG_PRIORITY = [
  'rainy day',
  'short stop',
  'family',
  'budget',
  'local favorite',
  'waterfront',
  'photogenic',
  'date night',
  'coffee break',
  'meal',
  'indoor',
  'outdoor',
] as const;

function getRawTags(place: BasePlaceInsert) {
  return place.tags
    .split(',')
    .map((entry) => entry.trim().toLowerCase())
    .filter(Boolean);
}

function normalizeTag(tag: string) {
  switch (tag.trim().toLowerCase()) {
    case 'family-friendly':
    case 'kids':
      return 'family';
    case 'photo spot':
      return 'photogenic';
    case 'scenic walk':
      return 'scenic';
    case 'couples':
      return 'date night';
    case 'city beach':
      return 'beach';
    case 'sunny day':
      return 'summer';
    case 'open-air':
      return 'outdoor';
    default:
      return tag.trim().toLowerCase().replace(/-/g, ' ');
  }
}

function sortTags(tags: Iterable<string>) {
  return Array.from(new Set(tags)).sort((left, right) => {
    const leftIndex = TAG_PRIORITY.indexOf(left as (typeof TAG_PRIORITY)[number]);
    const rightIndex = TAG_PRIORITY.indexOf(right as (typeof TAG_PRIORITY)[number]);
    const leftPriority = leftIndex === -1 ? Number.MAX_SAFE_INTEGER : leftIndex;
    const rightPriority = rightIndex === -1 ? Number.MAX_SAFE_INTEGER : rightIndex;

    if (leftPriority !== rightPriority) {
      return leftPriority - rightPriority;
    }

    return left.localeCompare(right);
  });
}

function withNormalizedTags(place: BasePlaceInsert): BasePlaceInsert {
  const tags = new Set(getRawTags(place).map(normalizeTag));

  if (place.rainyDayFit || place.isIndoor) tags.add('rainy day');
  if ((place.durationMinutes ?? 0) > 0 && (place.durationMinutes ?? 0) <= 45) tags.add('short stop');

  const priceLevel = (place.priceLevel ?? '').toLowerCase();
  if (priceLevel === 'free' || priceLevel === 'low' || priceLevel === 'low to medium') {
    tags.add('budget');
  }

  if (place.category === 'cafe') tags.add('coffee break');
  if (place.category === 'restaurant') tags.add('meal');
  if (place.category === 'beach' || tags.has('waterfront') || tags.has('coastal')) {
    tags.add('waterfront');
  }

  if (
    !place.isIndoor &&
    (place.category === 'walking-area' || place.category === 'beach' || place.category === 'viewpoint')
  ) {
    tags.add('outdoor');
  }

  if (tags.has('couples')) {
    tags.delete('couples');
    tags.add('date night');
  }

  if (tags.has('photo spot')) {
    tags.delete('photo spot');
    tags.add('photogenic');
  }

  if (tags.has('family-friendly')) {
    tags.delete('family-friendly');
    tags.add('family');
  }

  return {
    ...place,
    tags: sortTags(tags).join(','),
  };
}

function inferHoursNote(place: BasePlaceInsert) {
  if (
    place.category === 'walking-area' ||
    place.category === 'beach' ||
    place.category === 'viewpoint' ||
    place.category === 'square-street'
  ) {
    return 'Outdoor public area. The experience is usually best in daylight and can change with weather, wind, and season.';
  }

  if (place.category === 'museum' || place.category === 'cultural-spot') {
    return 'Opening hours can vary by weekday, exhibition program, and season. Check the official source before you go.';
  }

  if (place.category === 'cafe' || place.category === 'restaurant') {
    return 'Hours can shift between weekdays, weekends, and holiday periods. Check the official source before planning a dedicated stop.';
  }

  if (place.category === 'shopping-area') {
    return 'Store and venue hours can differ within the area, especially on Sundays and holidays. Check the official source before you go.';
  }

  return 'Check the official source before you go, especially around holidays and seasonal changes.';
}

function inferBestTime(place: BasePlaceInsert) {
  if (place.category === 'beach') {
    return 'Best on bright afternoons and warm evenings.';
  }

  if (hasTag(place, 'evening') || hasTag(place, 'waterfront')) {
    return 'Best in the late afternoon or evening when the area feels more atmospheric.';
  }

  if (place.category === 'walking-area' || place.category === 'viewpoint') {
    return 'Best in the morning or near golden hour for calmer walks and better light.';
  }

  if (place.category === 'museum' || place.category === 'cultural-spot') {
    return 'Best when you want a slower indoor stop or need a strong rainy-day option.';
  }

  if (place.category === 'cafe') {
    return 'Best for a late-morning break or a quiet afternoon pause.';
  }

  if (place.category === 'restaurant') {
    return 'Best in the evening or as a planned meal stop.';
  }

  if (place.category === 'shopping-area') {
    return 'Best in the daytime when most stores and venues are active.';
  }

  return 'Best during the day.';
}

function inferSeasonality(place: BasePlaceInsert) {
  if (place.isIndoor) {
    return 'Works well year-round.';
  }

  if (place.category === 'beach') {
    return 'Strongest from late spring to early autumn.';
  }

  if (place.category === 'walking-area' || place.category === 'viewpoint') {
    return 'Best from spring to autumn, but still rewarding on clear winter days.';
  }

  if (place.category === 'square-street') {
    return 'Works year-round, but feels most lively in the brighter months.';
  }

  return 'Best checked against weather and season before you go.';
}

function withOperationalMetadata(place: BasePlaceInsert): BasePlaceInsert {
  return {
    ...place,
    hoursNote: place.hoursNote ?? inferHoursNote(place),
    bestTime: place.bestTime ?? inferBestTime(place),
    seasonality: place.seasonality ?? inferSeasonality(place),
    temporarilyClosed: place.temporarilyClosed ?? false,
  };
}

function withImageMetadata(place: BasePlaceInsert): PlaceInsert {
  const verifiedImage = VERIFIED_IMAGE_OVERRIDES[place.id];

  return {
    ...place,
    imageUrl: verifiedImage?.imageUrl ?? place.imageUrl,
    imageSourceUrl: verifiedImage?.imageSourceUrl,
    imageSourceName: verifiedImage?.imageSourceName ?? getLegacyImageSourceName(place.imageUrl),
    imageLicense: verifiedImage?.imageLicense ?? 'Unknown / not yet verified',
    imageAttribution:
      verifiedImage?.imageAttribution ??
      'Hidden in the app until replaced with a verified real place photo.',
    imageVerified: verifiedImage?.imageVerified ?? false,
    imageType: verifiedImage?.imageType ?? getLegacyImageType(place.imageUrl),
    importanceTier: getImportanceTier(place.id),
  };
}

const BASE_PLACE_SEED_DATA = [
  {
    id: 'posebyen',
    city: 'Kristiansand',
    name: 'Posebyen',
    slug: 'posebyen',
    category: 'walking-area',
    tags: 'cozy,historic,photogenic,quiet,short stop',
    description:
      'Historic wooden house district in Kristiansand with narrow streets and white wooden houses.',
    imageUrl:
      'https://images.unsplash.com/photo-1559494007-9f5847c49d97?auto=format&fit=crop&w=1200&q=80',
    shortStory:
      'Posebyen is often described as the calm, slow-breathing heart of Kristiansand where the city still feels intimate and old-fashioned.',
    factType: 'Historic wooden house district',
    address: 'Posebyen, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.visitnorway.com/listings//posebyen-old-town-in-kristiansand/21938/',
    localVibeMood: 'Quiet, cozy, slow pace',
    localVibeBestFor: 'Short relaxed walk, first-time visitors, photo stop',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: false,
    lat: 58.149131,
    lng: 7.998236,
  },
  {
    id: 'kristiansand-cathedral',
    city: 'Kristiansand',
    name: 'Kristiansand Cathedral',
    slug: 'kristiansand-cathedral',
    category: 'landmark',
    tags: 'tourist-friendly,central,short stop,historic',
    description: 'Neo-Gothic cathedral located at the city square in central Kristiansand.',
    imageUrl:
      'https://images.unsplash.com/photo-1515263487990-61b07816b324?auto=format&fit=crop&w=1200&q=80',
    shortStory:
      'The cathedral works as a visual anchor in the center and gives the city core a more ceremonial, historic feel.',
    factType: 'Neo-Gothic cathedral',
    address: 'Gyldenløves gate 9, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.visitnorway.com/listings//kristiansand-cathedral/24622/',
    localVibeMood: 'Central, open, urban',
    localVibeBestFor: 'Orientation point, short cultural stop',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: true,
    lat: 58.146499,
    lng: 7.993891,
  },
  {
    id: 'fiskebrygga',
    city: 'Kristiansand',
    name: 'Fiskebrygga',
    slug: 'fiskebrygga',
    category: 'square-street',
    tags: 'lively,evening,photo spot,waterfront',
    description: 'Harbor promenade with restaurants, canals, fish market activity, and boats.',
    imageUrl:
      'https://images.unsplash.com/photo-1518836434250-d4e30a9b6765?auto=format&fit=crop&w=1200&q=80',
    shortStory:
      'Fiskebrygga is where Kristiansand feels most social, especially when the harbor edge fills up on bright evenings.',
    factType: 'Fish quay and waterfront area',
    address: 'Gravane 8, Kristiansand',
    priceLevel: 'Medium',
    sourceUrl:
      'https://www.visitnorway.com/listings//fiskebrygga-the-fish-quay-in-kristiansand/19910/',
    localVibeMood: 'Lively, social, waterfront',
    localVibeBestFor: 'Evening walk, dinner, harbor atmosphere',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 60,
    rainyDayFit: false,
    lat: 58.141289,
    lng: 7.995022,
  },
  {
    id: 'bystranda',
    city: 'Kristiansand',
    name: 'Bystranda',
    slug: 'bystranda',
    category: 'beach',
    tags: 'family-friendly,sunny day,relax,city beach',
    description:
      'City beach with soft sand, a swimming pier, palm-lined promenade, and quick access from downtown.',
    imageUrl:
      'https://images.unsplash.com/photo-1493559254736-1c8b1a9c0665?auto=format&fit=crop&w=1200&q=80',
    shortStory:
      'Bystranda makes Kristiansand feel unexpectedly southern, with a beach culture that sits right next to the city center.',
    factType: 'Urban beach',
    address: 'Bystranda, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.visitnorway.com/listings//kristiansand-city-beach/19968/',
    localVibeMood: 'Casual, bright, summery',
    localVibeBestFor: 'Warm days, quick swim, family break',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: false,
    lat: 58.145992,
    lng: 8.007201,
  },
  {
    id: 'kilden-theatre',
    city: 'Kristiansand',
    name: 'Kilden Theatre and Concert Hall',
    slug: 'kilden-theatre',
    category: 'cultural-spot',
    tags: 'architecture,evening,indoor,waterfront',
    description: 'Major performing arts venue on the waterfront known for its distinctive oak facade.',
    imageUrl:
      'https://images.unsplash.com/photo-1516483638261-f4dbaf036963?auto=format&fit=crop&w=1200&q=80',
    shortStory:
      'Kilden feels like a big-city cultural building dropped onto the edge of the harbor, and that contrast is part of its appeal.',
    factType: 'Performing arts center',
    address: 'Sjølystveien 2, 4610 Kristiansand',
    priceLevel: 'Ticketed events',
    sourceUrl: 'https://kilden.com/en/kontakt/',
    localVibeMood: 'Architectural, polished, evening focused',
    localVibeBestFor: 'Concert nights, architecture lovers, rainy-day culture',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 120,
    rainyDayFit: true,
    lat: 58.13929,
    lng: 7.997001,
  },
  {
    id: 'kunstsilo',
    city: 'Kristiansand',
    name: 'Kunstsilo',
    slug: 'kunstsilo',
    category: 'museum',
    tags: 'architecture,indoor,design,modern art',
    description:
      'Former grain silo transformed into a major art museum and cultural destination on Odderøya.',
    imageUrl: 'https://picsum.photos/seed/kunstsilo/1200/800',
    shortStory:
      'Kunstsilo gives Kristiansand a striking new skyline landmark and a museum visit that feels unusually spatial and contemporary.',
    factType: 'Art museum',
    address: 'Sjølystveien 8, 4610 Kristiansand',
    priceLevel: 'Ticketed exhibitions',
    sourceUrl: 'https://www.kunstsilo.no/en/visit-us',
    localVibeMood: 'Design-led, modern, cultural',
    localVibeBestFor: 'Rainy days, architecture fans, slow cultural visits',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 120,
    rainyDayFit: true,
    lat: 58.13825,
    lng: 7.997034,
  },
  {
    id: 'odderoya',
    city: 'Kristiansand',
    name: 'Odderøya',
    slug: 'odderoya',
    category: 'walking-area',
    tags: 'scenic walk,photo spot,coastal,local favorite',
    description:
      'Former naval area turned recreational island with marked paths, viewpoints, old cannon positions, and swimming spots.',
    imageUrl: 'https://picsum.photos/seed/odderoya/1200/800',
    shortStory:
      'Odderøya feels like the city opens outward here, with sea views, military traces, and a more expansive sense of space.',
    factType: 'Recreation area',
    address: 'Odderøya, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.visitnorway.com/listings/odderoya/19899/',
    localVibeMood: 'Open, coastal, slightly rugged',
    localVibeBestFor: 'Longer walks, views, first-time visitors with time',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: false,
    lat: 58.135798,
    lng: 8.002974,
  },
  {
    id: 'ravnedalen',
    city: 'Kristiansand',
    name: 'Ravnedalen Valley Nature Park',
    slug: 'ravnedalen',
    category: 'walking-area',
    tags: 'green,quiet,picnic,local favorite',
    description:
      'Historic valley park with a lake, steep hillsides, mature trees, and a summer concert atmosphere.',
    imageUrl: 'https://picsum.photos/seed/ravnedalen/1200/800',
    shortStory:
      'Ravnedalen feels tucked away and a little theatrical, with a cultivated park mood that still feels close to nature.',
    factType: 'Nature park',
    address: 'Ravnedalen, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.visitnorway.com/listings/ravnedalen-valley-nature-park/86344/',
    localVibeMood: 'Leafy, calm, atmospheric',
    localVibeBestFor: 'Relaxed walks, quiet breaks, soft-weather days',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 75,
    rainyDayFit: false,
    lat: 58.155862,
    lng: 7.973199,
  },
  {
    id: 'baneheia',
    city: 'Kristiansand',
    name: 'Baneheia Outdoor Area',
    slug: 'baneheia',
    category: 'walking-area',
    tags: 'scenic walk,local favorite,swim spot,active',
    description:
      'Large outdoor recreation area close to downtown with forest trails, lookouts, lakes, and swimming spots.',
    imageUrl: 'https://picsum.photos/seed/baneheia/1200/800',
    shortStory:
      'Baneheia is where city life gives way to everyday local recreation, with a more active and outdoorsy energy than the harbor front.',
    factType: 'Outdoor recreation area',
    address: 'Baneheia, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.visitnorway.com/listings//baneheia-outdoor-area/19943/',
    localVibeMood: 'Active, natural, local',
    localVibeBestFor: 'Morning walks, jogging, fresh air close to center',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: false,
    lat: 58.153579,
    lng: 7.984191,
  },
  {
    id: 'kristiansand-museum',
    city: 'Kristiansand',
    name: 'Kristiansand Museum',
    slug: 'kristiansand-museum',
    category: 'museum',
    tags: 'historic,family-friendly,open-air,heritage',
    description:
      'Open-air museum with historic houses, miniature old town, and regional heritage exhibits.',
    imageUrl: 'https://picsum.photos/seed/kristiansandmuseum/1200/800',
    shortStory:
      'This museum gives context to the city beyond the center by showing how local streets, farm life, and historic buildings fit together.',
    factType: 'Open-air museum',
    address: 'Vigeveien 22B, Kristiansand',
    priceLevel: 'Ticketed',
    sourceUrl: 'https://www.visitnorway.com/listings//kristiansand-museum/19946/',
    localVibeMood: 'Educational, family-friendly, spacious',
    localVibeBestFor: 'Families, history interest, slower half-day visits',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 120,
    rainyDayFit: false,
    lat: 58.161518,
    lng: 8.029896,
  },
  {
    id: 'natural-history-museum-botanical-garden',
    city: 'Kristiansand',
    name: 'Natural History Museum and Botanical Garden',
    slug: 'natural-history-museum-botanical-garden',
    category: 'museum',
    tags: 'family-friendly,indoor,garden,rainy day',
    description:
      'Natural history museum and botanical garden near the city center with geology, flora, and garden collections.',
    imageUrl: 'https://picsum.photos/seed/naturmuseum/1200/800',
    shortStory:
      'It combines a practical museum visit with a greener, slower setting, which makes it feel broader than a standard indoor stop.',
    factType: 'Natural history museum and botanical garden',
    address: 'Gimleveien 27, Kristiansand',
    priceLevel: 'Ticketed museum / garden access varies',
    sourceUrl:
      'https://www.visitnorway.com/listings//natural-history-museum-and-botanical-garden-in-kristiansand/19945/',
    localVibeMood: 'Calm, curious, family-friendly',
    localVibeBestFor: 'Rainy days, mixed-age groups, learning-oriented visits',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.158861,
    lng: 8.003652,
  },
  {
    id: 'gimle-gard',
    city: 'Kristiansand',
    name: 'Gimle Gård Manor House',
    slug: 'gimle-gard',
    category: 'museum',
    tags: 'historic,quiet,garden,cultural',
    description:
      'Historic manor house from around 1800 with period interiors and landscaped surroundings.',
    imageUrl: 'https://picsum.photos/seed/gimlegard/1200/800',
    shortStory:
      'Gimle Gård feels more intimate and reflective than the bigger museums, with a stronger sense of preserved domestic history.',
    factType: 'Historic manor house museum',
    address: 'Gimle Gård, Kristiansand',
    priceLevel: 'Ticketed',
    sourceUrl:
      'https://www.visitnorway.com/places-to-go/southern-norway/listings-southern-norway/gimle-g%C3%A5rd-manor-house/86366/',
    localVibeMood: 'Quiet, refined, historical',
    localVibeBestFor: 'History lovers, calm visits, paired stop with the botanical garden',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 60,
    rainyDayFit: true,
    lat: 58.158488,
    lng: 8.003081,
  },
  {
    id: 'kristiansand-kunsthall',
    city: 'Kristiansand',
    name: 'Kristiansand Kunsthall',
    slug: 'kristiansand-kunsthall',
    category: 'museum',
    tags: 'contemporary art,indoor,central,free',
    description:
      'Contemporary art venue on the town square with rotating exhibitions in the city center.',
    imageUrl: 'https://picsum.photos/seed/kunsthall/1200/800',
    shortStory:
      'Kunsthall is an easy culture stop when you want something central, current, and lighter than a full museum visit.',
    factType: 'Art gallery',
    address: 'Rådhusgaten 11, Kristiansand',
    priceLevel: 'Free',
    sourceUrl:
      'https://www.visitnorway.com/listings//kristiansand-kunsthall-art-gallery/19883/',
    localVibeMood: 'Minimal, central, contemporary',
    localVibeBestFor: 'Short indoor stop, art breaks between other city-center plans',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 45,
    rainyDayFit: true,
    lat: 58.145711,
    lng: 7.994062,
  },
  {
    id: 'markens',
    city: 'Kristiansand',
    name: 'Markens',
    slug: 'markens',
    category: 'shopping-area',
    tags: 'lively,shopping,central,people-watching',
    description:
      'Main pedestrian street in central Kristiansand with shops, cafes, and steady city-center movement.',
    imageUrl: 'https://picsum.photos/seed/markens/1200/800',
    shortStory:
      'Markens is less about one sight and more about urban rhythm: errands, coffee stops, casual browsing, and passing through.',
    factType: 'Pedestrian shopping street',
    address: 'Markens gate, Kristiansand',
    priceLevel: 'Free to explore',
    sourceUrl: 'https://www.visitnorway.com/en/kristiansand/',
    localVibeMood: 'Busy, central, casual',
    localVibeBestFor: 'Shopping, quick city-center walk, flexible plans',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 45,
    rainyDayFit: false,
    lat: 58.145958,
    lng: 7.991823,
  },
  {
    id: 'christiansholm-fortress',
    city: 'Kristiansand',
    name: 'Christiansholm Fortress',
    slug: 'christiansholm-fortress',
    category: 'landmark',
    tags: 'historic,waterfront,photo spot,short stop',
    description:
      'Historic waterfront fortress dating from 1672 near the marina and city promenade.',
    imageUrl: 'https://picsum.photos/seed/christiansholm/1200/800',
    shortStory:
      'The fortress adds a compact historical counterpoint to the marina and beach area just beside it.',
    factType: 'Historic fortress',
    address: 'Strandpromenaden, Kristiansand',
    priceLevel: 'Free to view from outside',
    sourceUrl:
      'https://www.visitnorway.com/listings/christiansholm-fortress-meeting-venue/158605/',
    localVibeMood: 'Historic, breezy, open',
    localVibeBestFor: 'Short stop, photo break, pairing with waterfront walk',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 20,
    rainyDayFit: false,
    lat: 58.14413,
    lng: 8.003428,
  },
  {
    id: 'odderoya-lighthouse',
    city: 'Kristiansand',
    name: 'Odderøya Lighthouse',
    slug: 'odderoya-lighthouse',
    category: 'viewpoint',
    tags: 'viewpoint,coastal,photo spot,quiet',
    description:
      'Coastal lighthouse viewpoint on Odderøya with wide views over the approach to Kristiansand.',
    imageUrl: 'https://picsum.photos/seed/odderoyafyr/1200/800',
    shortStory:
      'This is one of the better places to feel the meeting point between city, harbor traffic, and open sea.',
    factType: 'Lighthouse viewpoint',
    address: 'Odderøya, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.visitnorway.com/listings/odderoya-lighthouse/204524/',
    localVibeMood: 'Windy, open, contemplative',
    localVibeBestFor: 'Views, sunset walks, photo stops',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: false,
    lat: 58.131441,
    lng: 8.002248,
  },
  {
    id: 'tilstede-mat-og-mer',
    city: 'Kristiansand',
    name: 'Tilstede Mat og Mer',
    slug: 'tilstede-mat-og-mer',
    category: 'restaurant',
    tags: 'cozy,vegetarian,local favorite,lunch',
    description:
      'Relaxed city-center eatery focused on organic ingredients, vegetarian options, and a slower pace.',
    imageUrl: 'https://picsum.photos/seed/tilstede/1200/800',
    shortStory:
      'Tilstede feels more gentle and intentional than a standard lunch stop, especially if you want a calmer break from sightseeing.',
    factType: 'Restaurant and cafe',
    address: 'Markensgt. 29, Kristiansand',
    priceLevel: 'Medium',
    sourceUrl: 'https://www.visitnorway.com/listings//tilstede-mat-og-mer/22566/',
    localVibeMood: 'Calm, wholesome, relaxed',
    localVibeBestFor: 'Lunch, quiet reset, vegetarian-friendly meal',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 60,
    rainyDayFit: true,
    lat: 58.146008,
    lng: 7.991858,
  },
  {
    id: 'kristiansand-marina-cafe',
    city: 'Kristiansand',
    name: 'Kristiansand Marina Cafe',
    slug: 'kristiansand-marina-cafe',
    category: 'cafe',
    tags: 'waterfront,coffee,summer,short stop',
    description:
      'Seasonal marina cafe with outdoor seating close to the waterfront, city beach, and pedestrian streets.',
    imageUrl: 'https://picsum.photos/seed/marinacafe/1200/800',
    shortStory:
      'This is the kind of easy stop that works well when you want to stay near the water without committing to a full meal.',
    factType: 'Seasonal waterfront cafe',
    address: 'Strandpromenaden 14, Kristiansand',
    priceLevel: 'Low to medium',
    sourceUrl: 'https://www.visitnorway.com/listings/kristiansand-marina-cafe/228112/',
    localVibeMood: 'Easygoing, breezy, summer-oriented',
    localVibeBestFor: 'Coffee break, harbor pause, casual meetup',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: false,
    lat: 58.143181,
    lng: 8.001056,
  },
  {
    id: 'oddernes-church',
    city: 'Kristiansand',
    name: 'Oddernes Church',
    slug: 'oddernes-church',
    category: 'landmark',
    tags: 'historic,quiet,hidden gem,short stop',
    description:
      'Stone church from the 12th century with Romanesque character and a calmer setting than the city-center cathedral.',
    imageUrl: 'https://picsum.photos/seed/odderneskirke/1200/800',
    shortStory:
      'Oddernes Church feels older, quieter, and more local in mood than the more prominent cathedral downtown.',
    factType: 'Medieval stone church',
    address: 'Jegersbergvn. 2, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.visitnorway.com/listings/oddernes-church/86380/',
    localVibeMood: 'Quiet, historic, reflective',
    localVibeBestFor: 'Short detour, quieter history stop, repeat visitors',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: true,
    lat: 58.159707,
    lng: 8.013573,
  },
] satisfies BasePlaceInsert[];

const CURATED_PLACE_EXPANSION = [
  {
    id: 'vitensenteret-kristiansand',
    city: 'Kristiansand',
    name: 'Vitensenteret Sørlandet',
    slug: 'vitensenteret-kristiansand',
    category: 'museum',
    tags: 'indoor,family-friendly,rainy day,interactive,kids',
    description:
      'Hands-on science center in central Kristiansand with interactive exhibits that work well for both children and curious adults.',
    imageUrl: 'https://picsum.photos/seed/vitensenteret/1200/800',
    shortStory:
      'Vitensenteret is one of the easiest rainy-day wins in the city because it feels lively, playful, and genuinely engaging instead of purely educational.',
    factType: 'Interactive science center',
    address: 'Markens gate 21, Kristiansand',
    priceLevel: 'Ticketed admission',
    sourceUrl: 'https://vitensor.no/',
    localVibeMood: 'Playful, bright, curious',
    localVibeBestFor: 'Families, rainy afternoons, one to two hour visits',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.14533,
    lng: 7.993287,
  },
  {
    id: 'aquarama-waterpark',
    city: 'Kristiansand',
    name: 'Aquarama Water Park',
    slug: 'aquarama-waterpark',
    category: 'cultural-spot',
    tags: 'indoor,family-friendly,rainy day,wellness,active',
    description:
      'Large water park by Bystranda with pools, slides, and easy access from the city center waterfront.',
    imageUrl: 'https://picsum.photos/seed/aquarama-waterpark/1200/800',
    shortStory:
      'Aquarama gives the city center an all-weather activity hub that feels especially useful when the beach mood disappears.',
    factType: 'Urban water park',
    address: 'Tangen 8, Kristiansand',
    priceLevel: 'Ticketed admission',
    sourceUrl: 'https://www.aquarama.no/',
    localVibeMood: 'Active, family-oriented, all-weather',
    localVibeBestFor: 'Rainy days, kids, high-energy breaks',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 120,
    rainyDayFit: true,
    lat: 58.147185,
    lng: 8.006505,
  },
  {
    id: 'aquarama-spa',
    city: 'Kristiansand',
    name: 'Aquarama Spa',
    slug: 'aquarama-spa',
    category: 'cultural-spot',
    tags: 'indoor,wellness,relax,couples,rainy day',
    description:
      'Spa and wellness area inside Aquarama offering saunas, pools, and a slower adult-focused atmosphere near the waterfront.',
    imageUrl: 'https://picsum.photos/seed/aquarama-spa/1200/800',
    shortStory:
      'The spa is the calmer sibling to the water park and works better when you want a quieter reset than a family activity.',
    factType: 'Urban spa and wellness center',
    address: 'Tangen 8, Kristiansand',
    priceLevel: 'Ticketed admission',
    sourceUrl: 'https://www.aquarama.no/spa/',
    localVibeMood: 'Calm, restorative, polished',
    localVibeBestFor: 'Couples, rainy weather, slow afternoons',
    isIndoor: true,
    isFamilyFriendly: false,
    durationMinutes: 120,
    rainyDayFit: true,
    lat: 58.147185,
    lng: 8.006505,
  },
  {
    id: 'kristiansand-cannon-museum',
    city: 'Kristiansand',
    name: 'Kristiansand Cannon Museum',
    slug: 'kristiansand-cannon-museum',
    category: 'museum',
    tags: 'history,coastal,photogenic,local favorite,outdoor',
    description:
      'Historic coastal fort area at Møvik with one of the world’s largest land-based cannons and wide sea views.',
    imageUrl: 'https://picsum.photos/seed/kanonmuseum/1200/800',
    shortStory:
      'This is one of the more unusual history stops around Kristiansand because the scale of the site feels much bigger than a typical local museum.',
    factType: 'Coastal fort museum',
    address: 'Møvik fort, Kristiansand',
    priceLevel: 'Ticketed in season',
    sourceUrl: 'https://www.vestagdermuseet.no/kristiansand-kanonmuseum/',
    localVibeMood: 'Windy, historic, expansive',
    localVibeBestFor: 'Military history, sea views, half-day detours',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: false,
    lat: 58.090753,
    lng: 7.968191,
  },
  {
    id: 'bragdoya-coast-culture-center',
    city: 'Kristiansand',
    name: 'Bragdøya Coast Culture Center',
    slug: 'bragdoya-coast-culture-center',
    category: 'walking-area',
    tags: 'coastal,summer,local favorite,family-friendly,photogenic',
    description:
      'Island excursion with coastal culture history, walking paths, sea views, and a more relaxed archipelago rhythm than downtown.',
    imageUrl: 'https://picsum.photos/seed/bragdoya/1200/800',
    shortStory:
      'Bragdøya feels like Kristiansand stretched out into a softer island day trip, more breezy and unhurried than the city core.',
    factType: 'Coast culture center and island outing',
    address: 'Bragdøya, Kristiansand',
    priceLevel: 'Free to explore',
    sourceUrl: 'https://www.bragdoya.no/',
    localVibeMood: 'Breezy, maritime, easygoing',
    localVibeBestFor: 'Summer day trips, families, slower exploration',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 120,
    rainyDayFit: false,
    lat: 58.118087,
    lng: 7.994682,
  },
  {
    id: 'posebyhaven',
    city: 'Kristiansand',
    name: 'Posebyhaven',
    slug: 'posebyhaven',
    category: 'cafe',
    tags: 'cozy,local favorite,garden,coffee,photogenic',
    description:
      'Garden cafe tucked into Posebyen where the atmosphere feels softer, greener, and slower than the surrounding streets.',
    imageUrl: 'https://picsum.photos/seed/posebyhaven/1200/800',
    shortStory:
      'Posebyhaven is one of those places that makes the old town feel lived in rather than museum-like.',
    factType: 'Garden cafe in old town',
    address: 'Kristian IVs gate 85, Kristiansand',
    priceLevel: 'Low to medium',
    sourceUrl: 'https://www.visitnorway.com/listings//posebyhaven-in-kristiansand-old-town/230667/',
    localVibeMood: 'Calm, leafy, intimate',
    localVibeBestFor: 'Coffee stop, quieter catch-ups, sunny breaks',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 45,
    rainyDayFit: false,
    lat: 58.1507,
    lng: 7.996215,
  },
  {
    id: 'agder-kunstsenter',
    city: 'Kristiansand',
    name: 'Agder Kunstsenter',
    slug: 'agder-kunstsenter',
    category: 'cultural-spot',
    tags: 'indoor,art,quiet,short stop,local favorite',
    description:
      'Contemporary art center in the city core that works well as a lighter cultural stop between other downtown plans.',
    imageUrl: 'https://picsum.photos/seed/agderkunst/1200/800',
    shortStory:
      'Agder Kunstsenter feels smaller and more local than the headline museums, which is exactly why it rounds out the city well.',
    factType: 'Contemporary art center',
    address: 'Skippergata 24, Kristiansand',
    priceLevel: 'Free or low-cost exhibitions',
    sourceUrl: 'https://agderkunst.no/en/',
    localVibeMood: 'Quiet, creative, local',
    localVibeBestFor: 'Short indoor culture stop, repeat visitors, art-minded walks',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 45,
    rainyDayFit: true,
    lat: 58.146729,
    lng: 7.993164,
  },
  {
    id: 'kristiansand-folkebibliotek',
    city: 'Kristiansand',
    name: 'Kristiansand Public Library',
    slug: 'kristiansand-folkebibliotek',
    category: 'cultural-spot',
    tags: 'indoor,quiet,rainy day,work-friendly,short stop',
    description:
      'Central library with reading spaces and a dependable calm atmosphere for slower time in the city center.',
    imageUrl: 'https://picsum.photos/seed/folkebibliotek/1200/800',
    shortStory:
      'The library is not a headline tourist stop, but it gives the app a more realistic local texture because real city days often need quiet indoor space.',
    factType: 'Public library',
    address: 'Rådhusgata 11, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.kristiansandfolkebibliotek.no/',
    localVibeMood: 'Calm, useful, local',
    localVibeBestFor: 'Rainy breaks, reading time, low-energy plans',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 45,
    rainyDayFit: true,
    lat: 58.145641,
    lng: 7.99418,
  },
  {
    id: 'kristiansand-kino',
    city: 'Kristiansand',
    name: 'Kristiansand Kino',
    slug: 'kristiansand-kino',
    category: 'cultural-spot',
    tags: 'indoor,evening,rainy day,date night,central',
    description:
      'City-center cinema that works as an easy evening plan when you want something casual and weather-proof.',
    imageUrl: 'https://picsum.photos/seed/kristiansandkino/1200/800',
    shortStory:
      'Kino is not the most distinctive venue in town, but it makes the guide feel more complete because it supports real evening decisions.',
    factType: 'City cinema',
    address: 'Vestre Strandgate 9, Kristiansand',
    priceLevel: 'Ticketed admission',
    sourceUrl: 'https://www.kristiansandkino.no/',
    localVibeMood: 'Easy, central, familiar',
    localVibeBestFor: 'Evening fallback plan, rainy nights, date night',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 150,
    rainyDayFit: true,
    lat: 58.142749,
    lng: 7.994359,
  },
  {
    id: 'otterdalsparken',
    city: 'Kristiansand',
    name: 'Otterdalsparken',
    slug: 'otterdalsparken',
    category: 'walking-area',
    tags: 'waterfront,short stop,family-friendly,photogenic,relax',
    description:
      'Waterfront park with fountains, benches, and a short easy pause between the harbor and city-center streets.',
    imageUrl: 'https://picsum.photos/seed/otterdalsparken/1200/800',
    shortStory:
      'Otterdalsparken is less about destination-level sightseeing and more about giving the waterfront some breathing room.',
    factType: 'Waterfront city park',
    address: 'Strandpromenaden, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://www.visitnorway.com/listings/otterdalsparken-park/86347/',
    localVibeMood: 'Relaxed, airy, family-friendly',
    localVibeBestFor: 'Short walks, stroller stops, harbor breaks',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: false,
    lat: 58.145548,
    lng: 8.003558,
  },
  {
    id: 'la-famiglia',
    city: 'Kristiansand',
    name: 'La Famiglia',
    slug: 'la-famiglia',
    category: 'restaurant',
    tags: 'dinner,central,date night,italian,local favorite',
    description:
      'Well-known central restaurant for Italian comfort food with an easy downtown location near the waterfront side of the grid.',
    imageUrl: 'https://picsum.photos/seed/lafamiglia/1200/800',
    shortStory:
      'La Famiglia feels like one of those dependable city-center choices that locals actually reuse instead of mentioning once.',
    factType: 'Italian restaurant',
    address: 'Vestre Strandgate 22, Kristiansand',
    priceLevel: 'Medium',
    sourceUrl: 'https://lafa.no/',
    localVibeMood: 'Warm, social, dependable',
    localVibeBestFor: 'Dinner, easy group plan, casual date night',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.144809,
    lng: 7.991685,
  },
  {
    id: 'herlig-land',
    city: 'Kristiansand',
    name: 'Herlig Land',
    slug: 'herlig-land',
    category: 'cafe',
    tags: 'coffee,lunch,central,cozy,local favorite',
    description:
      'Popular central cafe and bakery stop on Markens with a casual city pulse and a good in-between-plans feel.',
    imageUrl: 'https://picsum.photos/seed/herligland/1200/800',
    shortStory:
      'Herlig Land is more about everyday city rhythm than big tourism, which makes it useful for giving recommendations some realism.',
    factType: 'Cafe and bakery',
    address: 'Markens gate 16, Kristiansand',
    priceLevel: 'Low to medium',
    sourceUrl: KRISTIANSAND_FOOD_AND_DRINK_URL,
    localVibeMood: 'Casual, central, easygoing',
    localVibeBestFor: 'Coffee, light lunch, city-center reset',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 45,
    rainyDayFit: true,
    lat: 58.145139,
    lng: 7.99425,
  },
  {
    id: 'smag-behag',
    city: 'Kristiansand',
    name: 'Smag & Behag Kristiansand',
    slug: 'smag-behag',
    category: 'restaurant',
    tags: 'dinner,indoor,date night,foodie,central',
    description:
      'Refined downtown restaurant that fits when you want a more polished dinner than the casual waterfront staples.',
    imageUrl: 'https://picsum.photos/seed/smagbehag/1200/800',
    shortStory:
      'Smag & Behag gives the city guide a more mature dinner option without drifting into hotel-lobby energy.',
    factType: 'Modern restaurant',
    address: 'Dronningens gate 48A, Kristiansand',
    priceLevel: 'Medium to high',
    sourceUrl: 'https://www.visitnorway.com/listings//smag-behag-kristiansand/221082/',
    localVibeMood: 'Polished, urban, evening-focused',
    localVibeBestFor: 'Date night, nicer dinner, longer meals',
    isIndoor: true,
    isFamilyFriendly: false,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.147054,
    lng: 8.00101,
  },
  {
    id: 'sjohuset-restaurant',
    city: 'Kristiansand',
    name: 'Sjøhuset Restaurant',
    slug: 'sjohuset-restaurant',
    category: 'restaurant',
    tags: 'waterfront,dinner,seafood,photogenic,evening',
    description:
      'Harbor-edge restaurant next to the guest harbor and Otterdalsparken with a distinctly waterfront setting.',
    imageUrl: 'https://picsum.photos/seed/sjohuset/1200/800',
    shortStory:
      'Sjøhuset is one of the places where the harbor view matters almost as much as the meal.',
    factType: 'Waterfront restaurant',
    address: 'Østre Strandgate 12A, Kristiansand',
    priceLevel: 'Medium to high',
    sourceUrl: 'https://www.sjohuset.no/',
    localVibeMood: 'Breezy, social, harbor-facing',
    localVibeBestFor: 'Waterfront dinner, visitors, brighter evenings',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.142397,
    lng: 7.999118,
  },
  {
    id: 'bonder-i-byen',
    city: 'Kristiansand',
    name: 'Bønder i Byen',
    slug: 'bonder-i-byen',
    category: 'cafe',
    tags: 'coffee,lunch,local favorite,cozy,central',
    description:
      'Cafe and bakery known for a more local daytime crowd and a good balance between grab-and-go and sit-down use.',
    imageUrl: 'https://picsum.photos/seed/bonderibyen/1200/800',
    shortStory:
      'Bønder i Byen helps the city feel less tourist-only and more like somewhere people actually live and work.',
    factType: 'Cafe and bakery',
    address: 'Rådhusgata 16, Kristiansand',
    priceLevel: 'Low to medium',
    sourceUrl: 'https://bonderibyen.no/',
    localVibeMood: 'Friendly, useful, everyday-local',
    localVibeBestFor: 'Breakfast, lunch, simple coffee break',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 45,
    rainyDayFit: true,
    lat: 58.146082,
    lng: 7.996135,
  },
  {
    id: 'spiren-kafe',
    city: 'Kristiansand',
    name: 'Spiren Kafé',
    slug: 'spiren-kafe',
    category: 'cafe',
    tags: 'coffee,lunch,central,short stop,cozy',
    description:
      'Small city-center cafe that works well as a quick coffee and cake pause in the middle of downtown plans.',
    imageUrl: 'https://picsum.photos/seed/spirenkafe/1200/800',
    shortStory:
      'Spiren is one of the kinds of modest places that make recommendation results feel grounded instead of over-curated.',
    factType: 'Cafe',
    address: 'Dronningens gate 52, Kristiansand',
    priceLevel: 'Low to medium',
    sourceUrl: KRISTIANSAND_FOOD_AND_DRINK_URL,
    localVibeMood: 'Simple, pleasant, central',
    localVibeBestFor: 'Quick coffee, short stop, low-commitment break',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: true,
    lat: 58.147367,
    lng: 8.001628,
  },
  {
    id: 'cafe-rasmus',
    city: 'Kristiansand',
    name: 'Café Rasmus',
    slug: 'cafe-rasmus',
    category: 'cafe',
    tags: 'coffee,central,short stop,casual,indoor',
    description:
      'Classic downtown cafe stop on Markens that fits best when you want something simple and central rather than destination dining.',
    imageUrl: 'https://picsum.photos/seed/caferasmus/1200/800',
    shortStory:
      'Café Rasmus fills an everyday niche, and that makes it surprisingly valuable inside a city guide dataset.',
    factType: 'Cafe',
    address: 'Markens gate 22A, Kristiansand',
    priceLevel: 'Low to medium',
    sourceUrl: KRISTIANSAND_FOOD_AND_DRINK_URL,
    localVibeMood: 'Casual, central, unpretentious',
    localVibeBestFor: 'Fast break, coffee, short sit-down',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: true,
    lat: 58.145867,
    lng: 7.992741,
  },
  {
    id: 'radhuscafeen',
    city: 'Kristiansand',
    name: 'Rådhuscafeen',
    slug: 'radhuscafeen',
    category: 'cafe',
    tags: 'coffee,lunch,quiet,local favorite,indoor',
    description:
      'A quieter cafe option slightly outside the busiest pedestrian core, useful when you want lower tempo.',
    imageUrl: 'https://picsum.photos/seed/radhuscafeen/1200/800',
    shortStory:
      'Rådhuscafeen gives the dataset a calmer everyday lunch option instead of another interchangeable city-center stop.',
    factType: 'Cafe',
    address: 'Østerveien 6, Kristiansand',
    priceLevel: 'Low to medium',
    sourceUrl: KRISTIANSAND_FOOD_AND_DRINK_URL,
    localVibeMood: 'Low-key, local, quieter',
    localVibeBestFor: 'Lunch, slower coffee, less crowded break',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 45,
    rainyDayFit: true,
    lat: 58.150454,
    lng: 8.006781,
  },
  {
    id: 'sorlandssenteret',
    city: 'Kristiansand',
    name: 'Sørlandssenteret',
    slug: 'sorlandssenteret',
    category: 'shopping-area',
    tags: 'indoor,shopping,rainy day,family-friendly,practical',
    description:
      'Large regional shopping center east of the city core, useful for retail-heavy plans and weather-proof downtime.',
    imageUrl: 'https://picsum.photos/seed/sorlandssenteret/1200/800',
    shortStory:
      'Sørlandssenteret is not romantic, but it makes the guide feel more real because visitors sometimes need practical indoor options too.',
    factType: 'Regional shopping center',
    address: 'Barstølveien 29-35, Kristiansand',
    priceLevel: 'Varies by shop',
    sourceUrl: 'https://thonsenter.no/sorlandssenteret/',
    localVibeMood: 'Practical, busy, all-weather',
    localVibeBestFor: 'Shopping, rainy afternoons, mixed-group plans',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 120,
    rainyDayFit: true,
    lat: 58.178501,
    lng: 8.129119,
  },
  {
    id: 'mother-india',
    city: 'Kristiansand',
    name: 'Mother India',
    slug: 'mother-india',
    category: 'restaurant',
    tags: 'dinner,indoor,central,spiced,date night',
    description:
      'Central Indian restaurant that broadens the dinner mix beyond the standard waterfront choices.',
    imageUrl: 'https://picsum.photos/seed/motherindia/1200/800',
    shortStory:
      'Mother India helps the restaurant list feel more varied and more useful for repeat evenings in town.',
    factType: 'Indian restaurant',
    address: 'Markens gate 6, Kristiansand',
    priceLevel: 'Medium',
    sourceUrl: 'https://www.motherindia.no/',
    localVibeMood: 'Warm, flavorful, evening-friendly',
    localVibeBestFor: 'Dinner, shared plates, alternative to seafood-heavy picks',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.144177,
    lng: 7.996241,
  },
  {
    id: 'christianssand-brewery',
    city: 'Kristiansand',
    name: 'Christianssand Brygghus',
    slug: 'christianssand-brewery',
    category: 'restaurant',
    tags: 'beer,indoor,evening,local favorite,social',
    description:
      'Brewery-focused city spot that fits better for evening social plans than for formal dining.',
    imageUrl: 'https://picsum.photos/seed/christianssandbrygghus/1200/800',
    shortStory:
      'This gives the app a more local evening option with a stronger bar-and-brewery identity than the family-oriented waterfront places.',
    factType: 'Brewpub',
    address: 'Tollbodgata 9, Kristiansand',
    priceLevel: 'Medium',
    sourceUrl: KRISTIANSAND_FOOD_AND_DRINK_URL,
    localVibeMood: 'Social, casual, evening-led',
    localVibeBestFor: 'Beer, friends, casual nights out',
    isIndoor: true,
    isFamilyFriendly: false,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.144521,
    lng: 7.993996,
  },
  {
    id: 'torvet-bistro',
    city: 'Kristiansand',
    name: 'Torvet Bistro',
    slug: 'torvet-bistro',
    category: 'restaurant',
    tags: 'central,dinner,indoor,urban,casual',
    description:
      'Bistro-style central restaurant right by the main square, useful when location matters as much as cuisine.',
    imageUrl: 'https://picsum.photos/seed/torvetbistro/1200/800',
    shortStory:
      'Torvet Bistro is practical in the best way: central, easy to explain, and well suited to mixed plans.',
    factType: 'Bistro restaurant',
    address: 'Rådhusgata 14C, Kristiansand',
    priceLevel: 'Medium',
    sourceUrl: 'https://dronningenkrs.no/',
    localVibeMood: 'Central, easy, urban',
    localVibeBestFor: 'Dinner near the square, meetups, low-friction plans',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 75,
    rainyDayFit: true,
    lat: 58.145867,
    lng: 7.995507,
  },
  {
    id: 'hos-moi',
    city: 'Kristiansand',
    name: 'Hos Moi',
    slug: 'hos-moi',
    category: 'restaurant',
    tags: 'waterfront,dinner,indoor,date night,local favorite',
    description:
      'Restaurant by Nodeviga with a calmer waterside setting than the busiest harbor-front dining cluster.',
    imageUrl: 'https://picsum.photos/seed/hosmoi/1200/800',
    shortStory:
      'Hos Moi feels slightly tucked away compared with the headline waterfront strip, which can be a strength when you want a calmer meal.',
    factType: 'Waterfront restaurant',
    address: 'Nodeviga 2, Kristiansand',
    priceLevel: 'Medium to high',
    sourceUrl: 'https://hosmoi.no/',
    localVibeMood: 'Calm, polished, waterside',
    localVibeBestFor: 'Date night, slower dinner, harbor-side meal',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.140936,
    lng: 7.996668,
  },
  {
    id: 'hamresanden',
    city: 'Kristiansand',
    name: 'Hamresanden',
    slug: 'hamresanden',
    category: 'beach',
    tags: 'beach,summer,photogenic,family-friendly,long walk',
    description:
      'Long sandy beach east of the center that feels broader and more open than Bystranda when you want a larger seaside setting.',
    imageUrl: 'https://picsum.photos/seed/hamresanden/1200/800',
    shortStory:
      'Hamresanden is where the city guide starts to feel like a real regional day planner rather than a tight downtown list.',
    factType: 'Long sandy beach',
    address: 'Hamresanden, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: KRISTIANSAND_THINGS_TO_DO_URL,
    localVibeMood: 'Open, bright, holiday-like',
    localVibeBestFor: 'Sunny days, beach time, longer seaside walks',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 120,
    rainyDayFit: false,
    lat: 58.18847,
    lng: 8.086039,
  },
  {
    id: 'arkivet',
    city: 'Kristiansand',
    name: 'ARKIVET Peace and Human Rights Centre',
    slug: 'arkivet',
    category: 'museum',
    tags: 'indoor,history,rainy day,reflective,educational',
    description:
      'Museum and human rights center focused on war history, memory, and civic reflection in a former Gestapo headquarters.',
    imageUrl: 'https://picsum.photos/seed/arkivet/1200/800',
    shortStory:
      'ARKIVET brings moral weight and historical depth that the lighter tourism places cannot cover.',
    factType: 'Peace and human rights museum',
    address: 'Vesterveien 4, Kristiansand',
    priceLevel: 'Ticketed exhibitions',
    sourceUrl: 'https://arkivet.no/en/',
    localVibeMood: 'Reflective, serious, meaningful',
    localVibeBestFor: 'History visitors, indoor learning, slower museum visits',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.144643,
    lng: 7.981509,
  },
  {
    id: 'kristiansand-camping',
    city: 'Kristiansand',
    name: 'Kristiansand Camping',
    slug: 'kristiansand-camping',
    category: 'cultural-spot',
    tags: 'indoor,fun,group-friendly,rainy day,games',
    description:
      'Indoor mini-golf and social games venue in the city center that works well for groups and casual evenings.',
    imageUrl: 'https://picsum.photos/seed/kristiansandcamping/1200/800',
    shortStory:
      'Kristiansand Camping gives the app a playful social option that is neither a museum nor a restaurant.',
    factType: 'Indoor mini-golf venue',
    address: 'Kristian IVs gate 12, Kristiansand',
    priceLevel: 'Paid activity',
    sourceUrl: KRISTIANSAND_THINGS_TO_DO_URL,
    localVibeMood: 'Playful, social, low-pressure',
    localVibeBestFor: 'Groups, rainy evenings, casual date ideas',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 60,
    rainyDayFit: true,
    lat: 58.14673,
    lng: 7.989401,
  },
  {
    id: 'dyreparken',
    city: 'Kristiansand',
    name: 'Kristiansand Zoo and Amusement Park',
    slug: 'dyreparken',
    category: 'cultural-spot',
    tags: 'family-friendly,kids,full day,major attraction,animals',
    description:
      'Major family attraction east of the city center combining zoo experiences, themed areas, and seasonal rides.',
    imageUrl: 'https://picsum.photos/seed/dyreparken/1200/800',
    shortStory:
      'Dyreparken is the biggest family pull in the region and it makes the guide immediately feel more substantial.',
    factType: 'Zoo and amusement park',
    address: 'Dyreparkveien, Kristiansand',
    priceLevel: 'Ticketed admission',
    sourceUrl: 'https://www.dyreparken.no/',
    localVibeMood: 'High-energy, family-first, full-day',
    localVibeBestFor: 'Families, children, major day trips',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 240,
    rainyDayFit: false,
    lat: 58.185966,
    lng: 8.142344,
  },
  {
    id: 'badelandet',
    city: 'Kristiansand',
    name: 'Badelandet at Dyreparken',
    slug: 'badelandet',
    category: 'cultural-spot',
    tags: 'family-friendly,water,summer,kids,active',
    description:
      'Seasonal water park area at Dyreparken that extends the family attraction mix beyond animals and rides.',
    imageUrl: 'https://picsum.photos/seed/badelandet/1200/800',
    shortStory:
      'Badelandet works best as an add-on for a bigger family day rather than a downtown stop, but it broadens summer recommendations well.',
    factType: 'Seasonal water park',
    address: 'Dyreparken, Kristiansand',
    priceLevel: 'Ticketed admission',
    sourceUrl: 'https://www.dyreparken.no/',
    localVibeMood: 'Lively, summery, child-focused',
    localVibeBestFor: 'Families, hot days, extended Dyreparken plans',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 180,
    rainyDayFit: false,
    lat: 58.185966,
    lng: 8.142344,
  },
  {
    id: 'blaud-sauna',
    city: 'Kristiansand',
    name: 'Blaud Sauna',
    slug: 'blaud-sauna',
    category: 'cultural-spot',
    tags: 'sauna,wellness,waterfront,couples,local favorite',
    description:
      'Floating sauna experience by the waterfront for a more local-feeling wellness plan than a conventional spa.',
    imageUrl: 'https://picsum.photos/seed/blaudsauna/1200/800',
    shortStory:
      'Blaud is one of the newer style-of-place additions that makes the city feel current rather than only classic.',
    factType: 'Floating waterfront sauna',
    address: 'Nodeviga 45, Kristiansand',
    priceLevel: 'Paid activity',
    sourceUrl: 'https://www.blaud.no/',
    localVibeMood: 'Nordic, refreshing, slightly adventurous',
    localVibeBestFor: 'Sauna sessions, couples, local-style reset',
    isIndoor: true,
    isFamilyFriendly: false,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.140989,
    lng: 8.000297,
  },
  {
    id: 'odderoya-museumshavn',
    city: 'Kristiansand',
    name: 'Odderøya Museumshavn',
    slug: 'odderoya-museumshavn',
    category: 'museum',
    tags: 'maritime,photogenic,waterfront,history,short stop',
    description:
      'Small maritime heritage harbor at Nodeviga with historic boats and a stronger old-port atmosphere than the main marina.',
    imageUrl: 'https://picsum.photos/seed/odderoyamuseumshavn/1200/800',
    shortStory:
      'Museumshavn is the kind of smaller specialist place that gives the city guide texture and repeat-visitor depth.',
    factType: 'Maritime heritage harbor',
    address: 'Nodeviga, Kristiansand',
    priceLevel: 'Free to view',
    sourceUrl: KRISTIANSAND_THINGS_TO_DO_URL,
    localVibeMood: 'Maritime, niche, quietly photogenic',
    localVibeBestFor: 'Short harbor detour, maritime interest, slower walks',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 45,
    rainyDayFit: false,
    lat: 58.140541,
    lng: 8.000247,
  },
  {
    id: 'klatreverket-kristiansand',
    city: 'Kristiansand',
    name: 'Klatreverket Kristiansand',
    slug: 'klatreverket-kristiansand',
    category: 'cultural-spot',
    tags: 'indoor,active,rainy day,family-friendly,climbing',
    description:
      'Indoor climbing gym that adds a more active all-weather option beyond museums, cafes, and shopping.',
    imageUrl: 'https://picsum.photos/seed/klatreverket/1200/800',
    shortStory:
      'Klatreverket broadens the guide from sightseeing into something people can actually do on a grey day.',
    factType: 'Indoor climbing gym',
    address: 'Jørgen Moes gate 10, Kristiansand',
    priceLevel: 'Paid activity',
    sourceUrl: 'https://klatreverket.no/',
    localVibeMood: 'Energetic, practical, all-weather',
    localVibeBestFor: 'Active visitors, families, rainy afternoons',
    isIndoor: true,
    isFamilyFriendly: true,
    durationMinutes: 90,
    rainyDayFit: true,
    lat: 58.146859,
    lng: 7.980185,
  },
  {
    id: 'kristiansand-marina',
    city: 'Kristiansand',
    name: 'Kristiansand Marina',
    slug: 'kristiansand-marina',
    category: 'square-street',
    tags: 'waterfront,boats,short stop,summer,photogenic',
    description:
      'Guest harbor edge and promenade area that works as a quick waterfront stroll near Otterdalsparken and Fiskebrygga.',
    imageUrl: 'https://picsum.photos/seed/kristiansandmarina/1200/800',
    shortStory:
      'The marina is not a must-do destination on its own, but it helps the harbor district feel richer and more navigable in the app.',
    factType: 'Guest harbor promenade',
    address: 'Strandpromenaden 14, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: KRISTIANSAND_PLAN_URL,
    localVibeMood: 'Breezy, harbor-side, easy',
    localVibeBestFor: 'Short strolls, boat-watching, filling time near the waterfront',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: false,
    lat: 58.143181,
    lng: 8.001056,
  },
] satisfies BasePlaceInsert[];

export const PLACE_SEED_DATA = [...BASE_PLACE_SEED_DATA, ...CURATED_PLACE_EXPANSION]
  .map(withOperationalMetadata)
  .map(withNormalizedTags)
  .map(withImageMetadata) satisfies PlaceInsert[];
