// Real, human-verified "free/cheap equipment lending" organizations, one
// per country -- e.g. Norway's BUA lends outdoor/sports gear for free. Not
// discoverable through any single API: no comprehensive multi-country
// directory, federation, or app exists for this (checked directly --
// Peerby/fainin/OLIO are peer-to-peer, not equipment centers, and coverage
// is patchy city-by-city; Wikidata's three relevant classes -- "library of
// things" Q25608610, "tool library" Q6643412, "toy library" Q1143018 -- are
// real and SPARQL-queryable but sparse and inconsistently tagged, missing
// BUA itself). This is a small, hand-curated, human-verified list instead
// of relying on an LLM's own fuzzy training-data recall, which tested live
// as unreliable (asked directly about free kayak equipment in Norway, the
// model didn't mention BUA at all). ~194 countries were checked across
// three research passes before landing on this list -- most genuinely have
// no findable equivalent (concentrated in Western Europe, North America,
// Oceania, plus one each in Turkey and Cyprus).
//
// `country` matches `world-countries`' own `name.common` (the same package
// `country-info.ts` already uses for `/country-info`, which is what
// populates the client's `CityContextSummary.countryName` this list is
// matched against) -- exact strings confirmed via that package directly,
// not guessed.
export interface LocalResource {
  country: string;
  organization: string;
  lends: string;
  /** `null` when research found the organization real but no single
   * canonical website (e.g. a program page inside a larger institution's
   * site with no stable direct URL). */
  website: string | null;
  free: boolean;
  verified: 'wikidata' | 'web-search';
}

export const LOCAL_RESOURCES: LocalResource[] = [
  { country: 'Norway', organization: 'BUA', lends: 'outdoor and sports equipment (skis, bikes, tents, kayaks, and more), 200+ locations', website: 'https://www.bua.io', free: true, verified: 'wikidata' },
  { country: 'United Kingdom', organization: 'Library of Things', lends: 'tools and household items', website: 'https://www.libraryofthings.co.uk', free: true, verified: 'wikidata' },
  { country: 'Sweden', organization: 'Fritidsbanken', lends: 'sports and outdoor equipment, 120+ municipalities', website: 'https://fritidsbanken.se', free: true, verified: 'web-search' },
  { country: 'Switzerland', organization: 'LaFilanda', lends: 'games and toys', website: 'http://lafilanda.ch', free: true, verified: 'wikidata' },
  { country: 'France', organization: 'Maison des Jeux Bretons', lends: 'games and toys', website: 'https://www.maisondesjeuxbretons.fr', free: true, verified: 'wikidata' },
  { country: 'Italy', organization: 'Ludoteca Comunale (Udine)', lends: 'toys', website: 'http://www.comune.udine.it', free: true, verified: 'wikidata' },
  { country: 'Canada', organization: 'Guelph Tool Library', lends: 'tools', website: 'https://guelphtoollibrary.org', free: true, verified: 'wikidata' },
  { country: 'United States', organization: 'Tool Library Alliance', lends: 'tools, via 100+ member tool libraries nationwide', website: 'https://toollibraryalliance.org', free: true, verified: 'web-search' },
  { country: 'New Zealand', organization: 'Beautification Trust Community Tool Library', lends: 'tools', website: 'https://www.beautification.org.nz', free: true, verified: 'web-search' },
  { country: 'Netherlands', organization: 'Speel-o-theek De Schatkist', lends: 'toys and play equipment', website: 'https://speelotheekdeschatkist.nl', free: true, verified: 'web-search' },
  { country: 'Belgium', organization: 'Sport Vlaanderen uitleendienst', lends: 'sports equipment, every Flemish province', website: 'https://sport.vlaanderen', free: true, verified: 'web-search' },
  { country: 'Austria', organization: 'Leila Wien', lends: 'everyday items', website: 'https://leila.wien', free: true, verified: 'web-search' },
  { country: 'Germany', organization: 'Leihladen-Vernetzung', lends: 'tools, kitchen and camping gear, via a nationwide network of independent Leihläden', website: 'https://leihladen-vernetzung.de', free: true, verified: 'web-search' },
  { country: 'Spain', organization: 'Biblioteca de las Cosas (Goethe-Institut Barcelona)', lends: 'tools, sport gear, devices', website: 'https://www.goethe.de/ins/es', free: true, verified: 'web-search' },
  { country: 'Argentina', organization: 'Biblioteca de las cosas (Goethe-Institut Buenos Aires)', lends: 'tools, devices, sport gear', website: 'https://www.goethe.de/ins/ar', free: true, verified: 'web-search' },
  { country: 'Brazil', organization: 'Biblioteca das Coisas (Goethe-Institut Porto Alegre)', lends: 'tools and electronics', website: 'https://www.goethe.de/ins/br', free: true, verified: 'web-search' },
  { country: 'Portugal', organization: 'Coisas à Mão (LIPOR + VivaLab, Porto)', lends: 'DIY, repair, and garden tools', website: null, free: true, verified: 'web-search' },
  { country: 'Lithuania', organization: 'Library of Things (Šiauliai County Povilas Višinskis Public Library)', lends: 'household and hobby items', website: null, free: true, verified: 'web-search' },
  { country: 'Cyprus', organization: 'KyklOIKOdromio', lends: 'DIY tools, garden machinery, kitchen appliances, camping/event equipment', website: 'https://circularlibraryforall.org', free: false, verified: 'web-search' },
  { country: 'Türkiye', organization: 'Nesneler Kütüphanesi (Goethe-Institut Ankara)', lends: 'tools, camping tents, cameras, and more', website: null, free: true, verified: 'web-search' },
];

export function findLocalResource(countryName: string | undefined | null): LocalResource | null {
  if (!countryName) return null;
  const normalized = countryName.trim().toLowerCase();
  return LOCAL_RESOURCES.find((r) => r.country.toLowerCase() === normalized) ?? null;
}
