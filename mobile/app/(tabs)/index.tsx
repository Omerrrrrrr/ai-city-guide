import { Pressable, StyleSheet, TextInput, View } from 'react-native';
import { Link, useRouter } from 'expo-router';
import React from 'react';

import ParallaxScrollView from '@/components/parallax-scroll-view';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import type { Place } from '@/src/data/places';
import { usePlaces } from '@/src/hooks/use-places';
import {
  sortPlacesForBrowse,
  isHighQualityPlace,
} from '@/src/utils/place-filters';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';

const INTENTS: { title: string; params: { category?: string; tag?: string; q?: string; openNow?: string } }[] = [
  { title: 'Open Now', params: { openNow: 'true' } },
  { title: 'Quick Walk', params: { category: 'walking-area', tag: 'short stop' } },
  { title: 'Rainy Day', params: { tag: 'rainy day' } },
  { title: 'Photo Spots', params: { tag: 'photogenic' } },
  { title: 'Family Time', params: { tag: 'family' } },
  { title: 'Local Picks', params: { tag: 'local favorite' } },
];

function formatCategory(category: Place['category']) {
  return category.replace('-', ' ');
}

function formatTag(tag: string) {
  return tag
    .split(' ')
    .map((word) => word.slice(0, 1).toUpperCase() + word.slice(1))
    .join(' ');
}

function PlaceSection({
  title,
  caption,
  places,
}: {
  title: string;
  caption: string;
  places: Place[];
}) {
  if (!places.length) return null;

  return (
    <ThemedView style={styles.subsection}>
      <View style={styles.subsectionHeader}>
        <ThemedText type="subtitle">{title}</ThemedText>
        <ThemedText style={styles.meta}>{caption}</ThemedText>
      </View>

      {places.map((place) => (
        (() => {
          const status = getPlaceOpenStatus(place);
          const isOpenNow = status.state === 'open' || status.state === 'all-day';

          return (
            <Link key={place.id} href={{ pathname: '/place/[id]', params: { id: place.id } }} asChild>
              <Pressable style={({ pressed }) => [styles.featureRow, pressed && styles.pressed]}>
                <View style={styles.featureText}>
                  <View style={styles.featureTopRow}>
                    <ThemedText style={styles.placeName}>{place.name}</ThemedText>
                    <View
                      style={[
                        styles.statusPill,
                        isOpenNow ? styles.statusPillOpen : styles.statusPillClosed,
                      ]}>
                      <ThemedText
                        style={[
                          styles.statusPillText,
                          isOpenNow ? styles.statusPillTextOpen : styles.statusPillTextClosed,
                        ]}>
                        {status.shortLabel}
                      </ThemedText>
                    </View>
                  </View>
                  <ThemedText style={styles.meta}>
                    {formatCategory(place.category)} · {place.tags.slice(0, 3).map(formatTag).join(', ')}
                  </ThemedText>
                </View>
                <ThemedText style={styles.chev}>›</ThemedText>
              </Pressable>
            </Link>
          );
        })()
      ))}
    </ThemedView>
  );
}

export default function HomeScreen() {
  const router = useRouter();
  const [query, setQuery] = React.useState('');
  const { data: places, error, isLoading, refresh } = usePlaces();
  const totalPlaces = places?.length ?? 0;
  const rankedPlaces = React.useMemo(() => sortPlacesForBrowse(places ?? []), [places]);
  const foodStops =
    places?.filter((place) => place.category === 'cafe' || place.category === 'restaurant').length ??
    0;
  const indoorOptions =
    places?.filter((place) => place.tags.includes('rainy day')).length ?? 0;
  const openNowCount = (places ?? []).filter((place) => {
    const status = getPlaceOpenStatus(place);
    return status.state === 'open' || status.state === 'all-day';
  }).length;
  const recommendedPlaces = rankedPlaces.filter(isHighQualityPlace).slice(0, 4);
  const featuredPlaces =
    recommendedPlaces.length > 0
      ? recommendedPlaces
      : rankedPlaces.filter((place) => place.importanceTier === 'hero').slice(0, 4);
  const openNowPlaces = rankedPlaces.filter((place) => {
    const status = getPlaceOpenStatus(place);
    return status.state === 'open' || status.state === 'all-day';
  }).slice(0, 4);
  const verifiedNowPlaces = rankedPlaces.filter((place) => {
    const status = getPlaceOpenStatus(place);
    return status.verified && (status.state === 'open' || status.state === 'all-day');
  }).slice(0, 4);
  const rainyDayPlaces = rankedPlaces.filter((place) => place.tags.includes('rainy day')).slice(0, 4);
  const familyPicks = rankedPlaces.filter((place) => place.tags.includes('family')).slice(0, 4);
  const shortStops = rankedPlaces.filter((place) => place.tags.includes('short stop')).slice(0, 4);
  const coffeeBreaks = rankedPlaces
    .filter((place) => place.tags.includes('coffee break') || place.category === 'cafe')
    .slice(0, 4);
  const waterfrontMood = rankedPlaces.filter((place) => place.tags.includes('waterfront')).slice(0, 4);
  const localFavorites = rankedPlaces.filter((place) => place.tags.includes('local favorite')).slice(0, 4);

  return (
    <ParallaxScrollView
      headerBackgroundColor={{ light: '#D9F1EA', dark: '#12332E' }}
      headerImage={
        <View style={styles.heroArt}>
          <View style={styles.heroGlow} />
          <View style={styles.heroCard}>
            <ThemedText type="defaultSemiBold" lightColor="#F7FFFC" darkColor="#F7FFFC">
              Kristiansand
            </ThemedText>
            <ThemedText style={styles.heroHeadline} lightColor="#F7FFFC" darkColor="#F7FFFC">
              Coastal walks, museums, and local favorites in one place.
            </ThemedText>
          </View>
          <View style={[styles.heroBadge, styles.heroBadgeLeft]}>
            <ThemedText style={styles.heroBadgeText} lightColor="#12332E" darkColor="#12332E">
              {totalPlaces ? `${totalPlaces} places` : 'Live API'}
            </ThemedText>
          </View>
          <View style={[styles.heroBadge, styles.heroBadgeRight]}>
            <ThemedText style={styles.heroBadgeText} lightColor="#12332E" darkColor="#12332E">
              {openNowCount ? `${openNowCount} open now` : 'AI + Map'}
            </ThemedText>
          </View>
        </View>
      }>
      <ThemedView style={styles.titleContainer}>
        <ThemedText type="title">AI City Guide</ThemedText>
        <ThemedText style={styles.lead}>
          Search places, browse stronger local coverage, and use the app like a real city companion
          instead of a tiny demo.
        </ThemedText>
      </ThemedView>

      <ThemedView style={styles.sectionContainer}>
        <ThemedText type="subtitle">Start Exploring</ThemedText>

        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search places…"
          placeholderTextColor="rgba(127,127,127,0.7)"
          autoCapitalize="none"
          autoCorrect={false}
          returnKeyType="search"
          onSubmitEditing={() => router.push({ pathname: '/explore', params: { q: query } })}
          style={styles.searchInput}
        />

        <ThemedView style={styles.intentRow}>
          {INTENTS.map((intent) => (
            <Link key={intent.title} href={{ pathname: '/explore', params: intent.params }} asChild>
              <Pressable style={({ pressed }) => [styles.intentChip, pressed && styles.pressed]}>
                <ThemedText style={styles.intentText}>{intent.title}</ThemedText>
              </Pressable>
            </Link>
          ))}
        </ThemedView>

        <ThemedText type="subtitle">Featured</ThemedText>
        {isLoading ? <ThemedText style={styles.meta}>Loading places…</ThemedText> : null}
        {error ? (
          <View style={styles.statusBlock}>
            <ThemedText style={styles.errorText}>{error}</ThemedText>
            <Pressable onPress={refresh} style={({ pressed }) => pressed && styles.pressed}>
              <ThemedText type="link">Retry</ThemedText>
            </Pressable>
          </View>
        ) : null}

        {places?.length ? (
          <ThemedView style={styles.statsRow}>
            <View style={styles.statCard}>
              <ThemedText style={styles.statValue}>{totalPlaces}</ThemedText>
              <ThemedText style={styles.meta}>places live</ThemedText>
            </View>
            <View style={styles.statCard}>
              <ThemedText style={styles.statValue}>{foodStops}</ThemedText>
              <ThemedText style={styles.meta}>food stops</ThemedText>
            </View>
            <View style={styles.statCard}>
              <ThemedText style={styles.statValue}>{indoorOptions}</ThemedText>
              <ThemedText style={styles.meta}>rainy-day picks</ThemedText>
            </View>
          </ThemedView>
        ) : null}

        <PlaceSection
          title="Open Right Now"
          caption="Useful places you can likely go to without waiting."
          places={openNowPlaces}
        />
        <PlaceSection
          title="Verified Hours"
          caption="Places with verified hours that are open right now."
          places={verifiedNowPlaces}
        />
        <PlaceSection
          title="Featured Picks"
          caption="Curated recommendations selected for quality, verification, and local value."
          places={featuredPlaces}
        />
        <PlaceSection
          title="Rainy Day"
          caption="Indoor places when the weather turns."
          places={rainyDayPlaces}
        />
        <PlaceSection
          title="Family Picks"
          caption="Easier choices when you want low-friction family options."
          places={familyPicks}
        />
        <PlaceSection
          title="Short Stops"
          caption="Useful places when you only have 30 to 45 minutes."
          places={shortStops}
        />
        <PlaceSection
          title="Coffee Breaks"
          caption="Short, useful stops that make the city feel lived in."
          places={coffeeBreaks}
        />
        <PlaceSection
          title="Waterfront Mood"
          caption="Harbor edges, sea views, and coastal air."
          places={waterfrontMood}
        />
        <PlaceSection
          title="Local Favorites"
          caption="Places that feel less generic and more lived-in."
          places={localFavorites}
        />
      </ThemedView>
    </ParallaxScrollView>
  );
}

const styles = StyleSheet.create({
  titleContainer: {
    gap: 10,
    marginBottom: 16,
  },
  lead: {
    opacity: 0.78,
    lineHeight: 22,
  },
  sectionContainer: {
    gap: 10,
  },
  subsection: {
    gap: 10,
    marginTop: 8,
  },
  subsectionHeader: {
    gap: 2,
  },
  searchInput: {
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 16,
  },
  intentRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  intentChip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
  },
  intentText: {
    fontSize: 14,
    lineHeight: 18,
  },
  featureRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingVertical: 12,
    paddingHorizontal: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
  },
  featureText: {
    flex: 1,
    gap: 4,
  },
  featureTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  statsRow: {
    flexDirection: 'row',
    gap: 10,
  },
  statCard: {
    flex: 1,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
    borderRadius: 14,
    paddingHorizontal: 12,
    paddingVertical: 12,
    gap: 4,
  },
  statValue: {
    fontSize: 24,
    lineHeight: 28,
    fontWeight: '700',
  },
  placeName: {
    fontSize: 16,
    lineHeight: 22,
    flex: 1,
  },
  meta: {
    opacity: 0.75,
    fontSize: 13,
    lineHeight: 18,
  },
  statusPill: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 999,
    borderWidth: 1,
  },
  statusPillOpen: {
    backgroundColor: 'rgba(18, 183, 106, 0.1)',
    borderColor: 'rgba(18, 183, 106, 0.2)',
  },
  statusPillClosed: {
    backgroundColor: 'rgba(217, 45, 32, 0.08)',
    borderColor: 'rgba(217, 45, 32, 0.16)',
  },
  statusPillText: {
    fontSize: 11,
    lineHeight: 14,
    fontWeight: '700',
  },
  statusPillTextOpen: {
    color: '#067647',
  },
  statusPillTextClosed: {
    color: '#B42318',
  },
  statusBlock: {
    gap: 6,
  },
  errorText: {
    color: '#B42318',
    lineHeight: 20,
  },
  chev: {
    fontSize: 22,
    lineHeight: 22,
    opacity: 0.6,
  },
  pressed: {
    opacity: 0.7,
  },
  heroArt: {
    flex: 1,
    justifyContent: 'center',
    paddingHorizontal: 24,
    paddingTop: 28,
  },
  heroGlow: {
    position: 'absolute',
    top: 28,
    right: 32,
    width: 180,
    height: 180,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.18)',
  },
  heroCard: {
    maxWidth: 260,
    padding: 18,
    borderRadius: 22,
    backgroundColor: 'rgba(7, 51, 44, 0.78)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    gap: 8,
  },
  heroHeadline: {
    fontSize: 24,
    lineHeight: 30,
    fontWeight: '700',
  },
  heroBadge: {
    position: 'absolute',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    backgroundColor: '#F4FFF9',
  },
  heroBadgeLeft: {
    left: 24,
    bottom: 30,
  },
  heroBadgeRight: {
    right: 24,
    bottom: 72,
  },
  heroBadgeText: {
    fontSize: 13,
    lineHeight: 16,
    fontWeight: '700',
  },
});
