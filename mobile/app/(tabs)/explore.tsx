import React from 'react';
import { Link, useLocalSearchParams } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';

import { PlaceImage } from '@/components/place-image';
import { PlaceMiniMap } from '@/components/place-mini-map';
import ParallaxScrollView from '@/components/parallax-scroll-view';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import type { PlaceCategory } from '@/src/data/places';
import { usePlaces } from '@/src/hooks/use-places';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';
import { filterPlaces, getAllTags, getCuratedTags, sortPlacesForBrowse } from '@/src/utils/place-filters';

const CATEGORIES: { id: PlaceCategory | 'all'; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'museum', label: 'Museums' },
  { id: 'landmark', label: 'Landmarks' },
  { id: 'cultural-spot', label: 'Culture' },
  { id: 'walking-area', label: 'Walks' },
  { id: 'beach', label: 'Beaches' },
  { id: 'square-street', label: 'Areas' },
  { id: 'shopping-area', label: 'Shopping' },
  { id: 'viewpoint', label: 'Views' },
  { id: 'cafe', label: 'Cafes' },
  { id: 'restaurant', label: 'Food' },
];

function formatCategory(category: string) {
  return category
    .split('-')
    .map((p) => p.slice(0, 1).toUpperCase() + p.slice(1))
    .join(' ');
}

function formatTag(tag: string) {
  return tag
    .split(' ')
    .map((word) => word.slice(0, 1).toUpperCase() + word.slice(1))
    .join(' ');
}

export default function ExploreScreen() {
  const params = useLocalSearchParams<{
    q?: string;
    category?: PlaceCategory | 'all';
    tag?: string | 'all';
    openNow?: string;
  }>();

  const [query, setQuery] = React.useState(params.q ?? '');
  const [category, setCategory] = React.useState<PlaceCategory | 'all'>(params.category ?? 'all');
  const [tag, setTag] = React.useState<string | 'all'>(params.tag ?? 'all');
  const [openNowOnly, setOpenNowOnly] = React.useState(params.openNow === 'true');
  const { data: allPlaces, error, isLoading, refresh } = usePlaces();

  React.useEffect(() => {
    if (typeof params.q === 'string') setQuery(params.q);
    if (typeof params.category === 'string') setCategory(params.category as PlaceCategory | 'all');
    if (typeof params.tag === 'string') setTag(params.tag as string | 'all');
    if (typeof params.openNow === 'string') setOpenNowOnly(params.openNow === 'true');
  }, [params.q, params.category, params.tag, params.openNow]);

  const tags = React.useMemo(() => getAllTags(allPlaces ?? []), [allPlaces]);
  const curatedTags = React.useMemo(() => getCuratedTags(allPlaces ?? []), [allPlaces]);
  const extraTags = React.useMemo(() => {
    const curatedSet = new Set<string>(curatedTags);
    return tags.filter((candidate) => !curatedSet.has(candidate));
  }, [tags, curatedTags]);
  const places = React.useMemo(
    () => sortPlacesForBrowse(filterPlaces(allPlaces ?? [], { query, category, tag, openNow: openNowOnly })),
    [allPlaces, query, category, openNowOnly, tag]
  );
  const openNowCount = React.useMemo(
    () =>
      places.filter((place) => {
        const status = getPlaceOpenStatus(place);
        return status.state === 'open' || status.state === 'all-day';
      }).length,
    [places]
  );
  const photoPlaces = React.useMemo(
    () =>
      [...places]
        .filter((place) => place.image.verified)
        .slice(0, 8),
    [places]
  );

  const hasFilters = query.trim().length > 0 || category !== 'all' || tag !== 'all' || openNowOnly;

  return (
    <ParallaxScrollView
      headerBackgroundColor={{ light: '#D0D0D', dark: '#353636' }}
      headerImage={<View style={styles.header} />}>
      <ThemedView style={styles.titleContainer}>
        <ThemedText type="title">Explore</ThemedText>
        <ThemedText style={styles.subtitle}>
          Browse all matching places. Stronger, higher-quality options are sorted first, while the map lets you explore any location.
        </ThemedText>
        {hasFilters ? (
          <Pressable
            accessibilityRole="button"
            onPress={() => {
              setQuery('');
              setCategory('all');
              setTag('all');
              setOpenNowOnly(false);
            }}
            style={({ pressed }) => pressed && styles.pressed}>
            <ThemedText type="link">Reset</ThemedText>
          </Pressable>
        ) : null}
      </ThemedView>

      <ThemedView style={styles.searchWrap}>
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search places, tags…"
          placeholderTextColor="rgba(127,127,127,0.7)"
          autoCapitalize="none"
          autoCorrect={false}
          style={styles.searchInput}
        />
      </ThemedView>

      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>
        <Pressable
          onPress={() => setOpenNowOnly(false)}
          style={({ pressed }) => [
            styles.chip,
            !openNowOnly && styles.chipActive,
            pressed && styles.chipPressed,
          ]}>
          <ThemedText style={styles.chipText}>All hours</ThemedText>
        </Pressable>
        <Pressable
          onPress={() => setOpenNowOnly((value) => !value)}
          style={({ pressed }) => [
            styles.chip,
            styles.chipStrong,
            openNowOnly && styles.chipOpenNow,
            pressed && styles.chipPressed,
          ]}>
          <ThemedText style={[styles.chipText, openNowOnly && styles.chipOpenNowText]}>Open now</ThemedText>
        </Pressable>
      </ScrollView>

      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>
        {CATEGORIES.map((c) => (
          <Pressable
            key={c.id}
            onPress={() => setCategory(c.id)}
            style={({ pressed }) => [
              styles.chip,
              category === c.id && styles.chipActive,
              pressed && styles.chipPressed,
            ]}>
            <ThemedText style={styles.chipText}>{c.label}</ThemedText>
          </Pressable>
        ))}
      </ScrollView>

      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>
        <Pressable
          onPress={() => setTag('all')}
          style={({ pressed }) => [
            styles.chip,
            tag === 'all' && styles.chipActive,
            pressed && styles.chipPressed,
          ]}>
          <ThemedText style={styles.chipText}>All use cases</ThemedText>
        </Pressable>
        {curatedTags.map((t) => (
          <Pressable
            key={`curated-${t}`}
            onPress={() => setTag(t)}
            style={({ pressed }) => [
              styles.chip,
              styles.chipStrong,
              tag === t && styles.chipActive,
              pressed && styles.chipPressed,
            ]}>
            <ThemedText style={styles.chipText}>{formatTag(t)}</ThemedText>
          </Pressable>
        ))}
      </ScrollView>

      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>
        <Pressable
          onPress={() => setTag('all')}
          style={({ pressed }) => [
            styles.chip,
            pressed && styles.chipPressed,
          ]}>
          <ThemedText style={styles.chipText}>More tags</ThemedText>
        </Pressable>
        {extraTags.map((t) => (
          <Pressable
            key={t}
            onPress={() => setTag(t)}
            style={({ pressed }) => [
              styles.chip,
              tag === t && styles.chipActive,
              pressed && styles.chipPressed,
            ]}>
            <ThemedText style={styles.chipText}>{formatTag(t)}</ThemedText>
          </Pressable>
        ))}
      </ScrollView>

      <ThemedView style={styles.list}>
        {!isLoading && !error && places.length > 0 ? (
          <ThemedView style={styles.summaryCard}>
            <ThemedText style={styles.summaryTitle}>Browse Snapshot</ThemedText>
            <ThemedText style={styles.summaryText}>
              {openNowCount} open now · {photoPlaces.length} verified photo picks · sorted with
              open places first
            </ThemedText>
          </ThemedView>
        ) : null}

        {isLoading ? <ThemedText style={styles.empty}>Loading places…</ThemedText> : null}
        {error ? (
          <View style={styles.statusBlock}>
            <ThemedText style={styles.errorText}>{error}</ThemedText>
            <Pressable onPress={refresh} style={({ pressed }) => pressed && styles.pressed}>
              <ThemedText type="link">Retry</ThemedText>
            </Pressable>
          </View>
        ) : null}

        {!isLoading && !error && photoPlaces.length > 0 ? (
          <ThemedView style={styles.sectionBlock}>
            <View style={styles.sectionHeader}>
              <ThemedText type="subtitle">Photo Picks</ThemedText>
              <ThemedText style={styles.sectionMeta}>
                {photoPlaces.length} verified {photoPlaces.length === 1 ? 'photo' : 'photos'}
              </ThemedText>
            </View>
            <View style={styles.photoGrid}>
              {photoPlaces.map((place) => (
                (() => {
                  const openStatus = getPlaceOpenStatus(place);
                  const isOpenNow = openStatus.state === 'open' || openStatus.state === 'all-day';

                  return (
                    <Link key={`photo-${place.id}`} href={{ pathname: '/place/[id]', params: { id: place.id } }} asChild>
                      <Pressable style={({ pressed }) => [styles.photoCard, pressed && styles.rowPressed]}>
                        <PlaceImage place={place} style={styles.photoCardImage} />
                        <View style={styles.photoCardBody}>
                          <View
                            style={[
                              styles.cardStatusBadge,
                              isOpenNow ? styles.cardStatusBadgeOpen : styles.cardStatusBadgeClosed,
                            ]}>
                            <ThemedText
                              style={[
                                styles.cardStatusText,
                                isOpenNow ? styles.cardStatusTextOpen : styles.cardStatusTextClosed,
                              ]}>
                              {openStatus.shortLabel}
                            </ThemedText>
                          </View>
                          <ThemedText numberOfLines={1} style={styles.photoCardTitle}>
                            {place.name}
                          </ThemedText>
                          <ThemedText numberOfLines={1} style={styles.photoCardMeta}>
                            {formatCategory(place.category)}
                          </ThemedText>
                          <ThemedText numberOfLines={2} style={styles.photoCardStory}>
                            {place.shortStory}
                          </ThemedText>
                        </View>
                      </Pressable>
                    </Link>
                  );
                })()
              ))}
            </View>
          </ThemedView>
        ) : null}

        {!isLoading && !error && places.length > 0 ? (
          <View style={styles.sectionHeader}>
            <ThemedText type="subtitle">All Matches</ThemedText>
            <ThemedText style={styles.sectionMeta}>
              {places.length} place{places.length === 1 ? '' : 's'}
            </ThemedText>
          </View>
        ) : null}

        {places.length > 0 ? (
          <View style={styles.matchGrid}>
            {places.map((place) => (
              (() => {
                const openStatus = getPlaceOpenStatus(place);
                const isOpenNow = openStatus.state === 'open' || openStatus.state === 'all-day';

                return (
                  <View key={place.id} style={styles.matchCard}>
                    <Link href={{ pathname: '/place/[id]', params: { id: place.id } }} asChild>
                      <Pressable style={({ pressed }) => [styles.matchCardTap, pressed && styles.rowPressed]}>
                        <PlaceImage place={place} style={styles.matchCardImage} compact />
                        <View style={styles.matchCardBody}>
                          <View
                            style={[
                              styles.cardStatusBadge,
                              isOpenNow ? styles.cardStatusBadgeOpen : styles.cardStatusBadgeClosed,
                            ]}>
                            <ThemedText
                              style={[
                                styles.cardStatusText,
                                isOpenNow ? styles.cardStatusTextOpen : styles.cardStatusTextClosed,
                              ]}>
                              {openStatus.shortLabel}
                            </ThemedText>
                          </View>
                          <ThemedText numberOfLines={2} style={styles.matchCardTitle}>
                            {place.name}
                          </ThemedText>
                          <ThemedText numberOfLines={1} style={styles.matchCardMeta}>
                            {formatCategory(place.category)}
                          </ThemedText>
                          <ThemedText numberOfLines={3} style={styles.matchCardStory}>
                            {place.shortStory}
                          </ThemedText>
                          <ThemedText numberOfLines={2} style={styles.matchCardTags}>
                            {place.tags.slice(0, 3).map(formatTag).join(', ')}
                          </ThemedText>
                          <PlaceMiniMap place={place} style={styles.matchCardMap} />
                        </View>
                      </Pressable>
                    </Link>
                  </View>
                );
              })()
            ))}
          </View>
        ) : null}

        {!isLoading && !error && places.length === 0 ? (
          <ThemedText style={styles.empty}>No matches. Try a different search or filter.</ThemedText>
        ) : null}
      </ThemedView>
    </ParallaxScrollView>
  );
}

const styles = StyleSheet.create({
  header: {
    height: 178,
  },
  titleContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
    marginBottom: 12,
  },
  subtitle: {
    opacity: 0.78,
    lineHeight: 20,
    marginTop: 2,
  },
  searchWrap: {
    marginBottom: 12,
  },
  searchInput: {
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 16,
  },
  chips: {
    paddingVertical: 6,
    gap: 8,
    paddingRight: 16,
  },
  chip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
  },
  chipActive: {
    borderColor: 'rgba(127,127,127,0.6)',
  },
  chipStrong: {
    backgroundColor: 'rgba(14,36,56,0.04)',
  },
  chipOpenNow: {
    backgroundColor: 'rgba(18, 183, 106, 0.1)',
    borderColor: 'rgba(18, 183, 106, 0.24)',
  },
  chipOpenNowText: {
    color: '#067647',
    fontWeight: '700',
  },
  chipPressed: {
    opacity: 0.7,
  },
  chipText: {
    fontSize: 14,
    lineHeight: 18,
  },
  list: {
    marginTop: 8,
    gap: 10,
  },
  summaryCard: {
    gap: 4,
    padding: 14,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.18)',
    backgroundColor: 'rgba(14,36,56,0.04)',
  },
  summaryTitle: {
    fontSize: 14,
    lineHeight: 18,
    fontWeight: '700',
  },
  summaryText: {
    fontSize: 13,
    lineHeight: 18,
    opacity: 0.78,
  },
  sectionBlock: {
    gap: 12,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  sectionMeta: {
    fontSize: 13,
    lineHeight: 18,
    opacity: 0.72,
  },
  photoGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  photoCard: {
    width: '48%',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.72)',
  },
  photoCardImage: {
    width: '100%',
    height: 120,
    backgroundColor: 'rgba(127,127,127,0.15)',
  },
  photoCardBody: {
    gap: 4,
    padding: 12,
  },
  cardStatusBadge: {
    alignSelf: 'flex-start',
    paddingHorizontal: 9,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: 1,
  },
  cardStatusBadgeOpen: {
    backgroundColor: 'rgba(18, 183, 106, 0.1)',
    borderColor: 'rgba(18, 183, 106, 0.2)',
  },
  cardStatusBadgeClosed: {
    backgroundColor: 'rgba(217, 45, 32, 0.08)',
    borderColor: 'rgba(217, 45, 32, 0.18)',
  },
  cardStatusText: {
    fontSize: 11,
    lineHeight: 14,
    fontWeight: '700',
  },
  cardStatusTextOpen: {
    color: '#067647',
  },
  cardStatusTextClosed: {
    color: '#B42318',
  },
  photoCardTitle: {
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '700',
  },
  photoCardMeta: {
    fontSize: 12,
    lineHeight: 16,
    opacity: 0.7,
  },
  photoCardStory: {
    fontSize: 13,
    lineHeight: 18,
    opacity: 0.82,
  },
  matchGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  matchCard: {
    width: '48%',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.72)',
  },
  matchCardTap: {
    backgroundColor: 'transparent',
  },
  matchCardImage: {
    width: '100%',
    height: 132,
    backgroundColor: 'rgba(127,127,127,0.15)',
  },
  matchCardMap: {
    width: '100%',
    height: 104,
  },
  matchCardBody: {
    gap: 4,
    padding: 12,
  },
  matchCardTitle: {
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '700',
  },
  matchCardMeta: {
    opacity: 0.72,
    fontSize: 12,
    lineHeight: 16,
  },
  matchCardStory: {
    opacity: 0.86,
    fontSize: 13,
    lineHeight: 18,
  },
  matchCardTags: {
    opacity: 0.78,
    fontSize: 13,
    lineHeight: 18,
    marginBottom: 6,
  },
  row: {
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
  thumb: {
    width: 64,
    height: 64,
    borderRadius: 10,
    backgroundColor: 'rgba(127,127,127,0.15)',
  },
  rowPressed: {
    opacity: 0.7,
  },
  rowText: {
    flex: 1,
    gap: 4,
  },
  rowTitle: {
    fontSize: 16,
    lineHeight: 22,
  },
  rowMeta: {
    opacity: 0.75,
    fontSize: 13,
    lineHeight: 18,
  },
  chev: {
    fontSize: 22,
    lineHeight: 22,
    opacity: 0.6,
  },
  empty: {
    opacity: 0.75,
    lineHeight: 22,
  },
  statusBlock: {
    gap: 6,
  },
  errorText: {
    color: '#B42318',
    lineHeight: 20,
  },
  pressed: {
    opacity: 0.7,
  },
});
