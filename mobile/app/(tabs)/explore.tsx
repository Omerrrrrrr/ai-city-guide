import React from 'react';
import {
  Pressable,
  RefreshControl,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  TextInput,
  View,
  useColorScheme,
} from 'react-native';
import { Link, useLocalSearchParams } from 'expo-router';
import { useTranslation } from 'react-i18next';

import { PlaceImage } from '@/components/place-image';
import { FeaturedCardSkeleton, PlaceRowSkeleton, SkeletonBox } from '@/components/skeleton';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { CATEGORY_FILTERS } from '@/src/constants/category-filters';
import type { Place, PlaceCategory } from '@/src/data/places';
import { usePlaces } from '@/src/hooks/use-places';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';
import { filterPlaces, formatTag, getCuratedTags, isHighQualityPlace, sortPlacesForBrowse } from '@/src/utils/place-filters';
import { useCityStore } from '@/src/store/city';
import { CATEGORY_EMOJI, formatCategory } from '@/src/utils/categories';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

function PlaceCard({ place, bg }: { place: Place; bg: string }) {
  const { t } = useTranslation();
  const status = getPlaceOpenStatus(place, t);
  const open = status.state === 'open' || status.state === 'all-day';
  return (
    <Link href={{ pathname: '/place/[id]', params: { id: place.id } }} asChild>
      <Pressable style={({ pressed }) => [styles.card, { backgroundColor: bg }, pressed && { opacity: 0.75 }]}>
        <PlaceImage place={place} style={styles.cardImage} />
        <View style={styles.cardBody}>
          <View style={[styles.statusDot, open ? styles.dotOpen : styles.dotClosed]} />
          <ThemedText numberOfLines={2} style={styles.cardName}>{place.name}</ThemedText>
          <ThemedText numberOfLines={1} style={styles.cardMeta}>{CATEGORY_EMOJI[place.category] ?? '📍'} {formatCategory(place.category, t)}</ThemedText>
          {place.shortStory ? (
            <ThemedText numberOfLines={2} style={styles.cardStory}>{place.shortStory}</ThemedText>
          ) : null}
        </View>
      </Pressable>
    </Link>
  );
}

function HeroCard({ place, bg }: { place: Place; bg: string }) {
  const { t } = useTranslation();
  const status = getPlaceOpenStatus(place, t);
  const open = status.state === 'open' || status.state === 'all-day';
  return (
    <Link href={{ pathname: '/place/[id]', params: { id: place.id } }} asChild>
      <Pressable style={({ pressed }) => [styles.heroCard, { backgroundColor: bg }, pressed && { opacity: 0.85 }]}>
        <PlaceImage place={place} style={styles.heroCardImage} />
        <View style={styles.heroCardOverlay}>
          <View style={[styles.heroStatusPill, open ? styles.pillOpen : styles.pillClosed]}>
            <ThemedText style={[styles.heroStatusText, open ? styles.pillTextOpen : styles.pillTextClosed]}>
              {status.shortLabel}
            </ThemedText>
          </View>
          <ThemedText numberOfLines={2} style={styles.heroCardName} lightColor="#fff" darkColor="#fff">
            {place.name}
          </ThemedText>
          <ThemedText numberOfLines={1} style={styles.heroCardMeta} lightColor="rgba(255,255,255,0.7)" darkColor="rgba(255,255,255,0.7)">
            {CATEGORY_EMOJI[place.category] ?? '📍'} {formatCategory(place.category, t)} · {place.tags[0]}
          </ThemedText>
        </View>
      </Pressable>
    </Link>
  );
}

function SectionRow({ title, places, bg }: { title: string; places: Place[]; bg: string }) {
  if (!places.length) return null;
  return (
    <View style={styles.sectionBlock}>
      <ThemedText style={styles.sectionTitle}>{title}</ThemedText>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.hScroll}>
        {places.map((p) => <PlaceCard key={p.id} place={p} bg={bg} />)}
      </ScrollView>
    </View>
  );
}

export default function ExploreScreen() {
  const colorScheme = useColorScheme();
  const dark = colorScheme === 'dark';
  const { t } = useTranslation();
  const [refreshing, setRefreshing] = React.useState(false);
  const params = useLocalSearchParams<{
    q?: string;
    category?: PlaceCategory | 'all';
    tag?: string;
    openNow?: string;
  }>();

  const [query, setQuery] = React.useState(params.q ?? '');
  const [category, setCategory] = React.useState<PlaceCategory | 'all'>(params.category ?? 'all');
  const [tag, setTag] = React.useState<string>(params.tag ?? 'all');
  const [openNowOnly, setOpenNowOnly] = React.useState(params.openNow === 'true');

  const { data: allPlaces, isLoading, error, refresh } = usePlaces();
  const { cityName } = useCityStore();

  React.useEffect(() => {
    if (params.q) setQuery(params.q);
    if (params.category) setCategory(params.category as PlaceCategory | 'all');
    if (params.tag) setTag(params.tag);
    if (params.openNow) setOpenNowOnly(params.openNow === 'true');
  }, [params.q, params.category, params.tag, params.openNow]);

  const curatedTags = React.useMemo(() => getCuratedTags(allPlaces ?? []), [allPlaces]);
  const places = React.useMemo(
    () => sortPlacesForBrowse(filterPlaces(allPlaces ?? [], { query, category, tag, openNow: openNowOnly })),
    [allPlaces, query, category, tag, openNowOnly]
  );

  const hasFilters = !!(query.trim() || category !== 'all' || tag !== 'all' || openNowOnly);

  const featured = React.useMemo(
    () => sortPlacesForBrowse(allPlaces ?? []).filter(isHighQualityPlace).slice(0, 6),
    [allPlaces]
  );
  const openNowList = React.useMemo(
    () => (allPlaces ?? []).filter((p) => { const s = getPlaceOpenStatus(p); return s.state === 'open' || s.state === 'all-day'; }).slice(0, 8),
    [allPlaces]
  );
  const rainyDay = React.useMemo(
    () => (allPlaces ?? []).filter((p) => p.tags.includes('rainy day')).slice(0, 6),
    [allPlaces]
  );

  const cardBg = dark ? '#1A2744' : '#fff';

  return (
    <View style={{ flex: 1, backgroundColor: dark ? '#0A0F1E' : '#F4F5F9' }}>
      {/* Header */}
      <SafeAreaView style={{ backgroundColor: NAVY }}>
        <View style={styles.header}>
          <View style={styles.headerTop}>
            <ThemedText style={styles.headerTitle} lightColor="#fff" darkColor="#fff">
              {cityName ?? t('explore.placesFallback')}
            </ThemedText>
            {hasFilters ? (
              <Pressable
                onPress={() => { setQuery(''); setCategory('all'); setTag('all'); setOpenNowOnly(false); }}
                style={({ pressed }) => pressed && { opacity: 0.7 }}>
                <ThemedText style={styles.resetText} lightColor="rgba(255,255,255,0.6)" darkColor="rgba(255,255,255,0.6)">
                  {t('explore.reset')}
                </ThemedText>
              </Pressable>
            ) : null}
          </View>
          <View style={styles.searchRow}>
            <TextInput
              value={query}
              onChangeText={setQuery}
              placeholder={t('common.searchPlaces')}
              placeholderTextColor="rgba(255,255,255,0.4)"
              autoCapitalize="none"
              autoCorrect={false}
              style={styles.searchInput}
            />
          </View>
        </View>
      </SafeAreaView>

      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={async () => {
              setRefreshing(true);
              await refresh();
              setRefreshing(false);
            }}
            tintColor={GOLD}
            colors={[GOLD]}
          />
        }>
        {/* Category chips */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chipRow}>
          {CATEGORY_FILTERS.map((c) => {
            const active = category === c.id;
            return (
              <Pressable
                key={c.id}
                onPress={() => setCategory(c.id)}
                style={[styles.chip, active && styles.chipActive]}>
                <ThemedText style={[styles.chipText, active && styles.chipTextActive]}>
                  {c.emoji ? `${c.emoji} ` : ''}{t(c.labelKey)}
                </ThemedText>
              </Pressable>
            );
          })}
        </ScrollView>

        {/* Tag + open now row */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chipRow}>
          <Pressable
            onPress={() => setOpenNowOnly((v) => !v)}
            style={[styles.chip, openNowOnly && styles.chipOpenNow]}>
            <ThemedText style={[styles.chipText, openNowOnly && styles.chipTextOpenNow]}>
              {t('explore.openNow')}
            </ThemedText>
          </Pressable>
          {curatedTags.map((curatedTag) => {
            const active = tag === curatedTag;
            return (
              <Pressable
                key={curatedTag}
                onPress={() => setTag(active ? 'all' : curatedTag)}
                style={[styles.chip, active && styles.chipActive]}>
                <ThemedText style={[styles.chipText, active && styles.chipTextActive]}>
                  {formatTag(curatedTag, t)}
                </ThemedText>
              </Pressable>
            );
          })}
        </ScrollView>

        {/* Error */}
        {error ? (
          <View style={[styles.errorBlock, { paddingHorizontal: 20, marginTop: 8 }]}>
            <ThemedText style={styles.errorText}>{error}</ThemedText>
            <Pressable onPress={refresh}><ThemedText style={styles.retryText}>{t('common.retry')}</ThemedText></Pressable>
          </View>
        ) : null}

        {/* Loading skeleton */}
        {isLoading && !error && (
          <>
            <View style={styles.heroSection}>
              <SkeletonBox height={220} borderRadius={20} />
            </View>
            <View style={styles.sectionBlock}>
              <ThemedText style={styles.sectionTitle}>{t('explore.sections.openRightNow')}</ThemedText>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.hScroll}>
                {[1, 2, 3].map((n) => <FeaturedCardSkeleton key={n} />)}
              </ScrollView>
            </View>
            <View style={styles.content}>
              <View style={styles.grid}>
                {[1, 2, 3, 4].map((n) => <PlaceRowSkeleton key={n} />)}
              </View>
            </View>
          </>
        )}

        {/* No-filter browsing: sections */}
        {!hasFilters && !isLoading && !error && (
          <>
            {/* Featured hero card */}
            {featured[0] && (
              <View style={styles.heroSection}>
                <HeroCard place={featured[0]} bg={cardBg} />
              </View>
            )}

            <SectionRow title={t('explore.sections.openRightNow')} places={openNowList} bg={cardBg} />
            <SectionRow title={t('explore.sections.featuredPlaces')} places={featured.slice(1)} bg={cardBg} />
            {rainyDay.length > 0 && <SectionRow title={t('explore.sections.rainyDayPicks')} places={rainyDay} bg={cardBg} />}

            {/* All places grid */}
            <View style={styles.content}>
              <ThemedText style={styles.sectionTitle}>{t('explore.sections.allPlaces')}</ThemedText>
              <View style={styles.grid}>
                {places.map((place) => <PlaceCard key={place.id} place={place} bg={cardBg} />)}
              </View>
            </View>
          </>
        )}

        {/* Filtered results: flat grid */}
        {hasFilters && !isLoading && !error && (
          <View style={styles.content}>
            <ThemedText style={styles.countText}>
              {t('explore.placesFound', { count: places.length })}
            </ThemedText>
            <View style={styles.grid}>
              {places.map((place) => <PlaceCard key={place.id} place={place} bg={cardBg} />)}
            </View>
            {places.length === 0 && (
              <ThemedText style={styles.emptyText}>{t('explore.emptyText')}</ThemedText>
            )}
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 16,
    gap: 12,
  },
  headerTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerTitle: {
    fontSize: 26,
    fontWeight: '700',
  },
  resetText: {
    fontSize: 15,
  },
  searchRow: {},
  searchInput: {
    backgroundColor: 'rgba(255,255,255,0.12)',
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 11,
    fontSize: 15,
    color: '#fff',
  },
  chipRow: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    gap: 8,
  },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 50,
    backgroundColor: 'rgba(15,28,63,0.07)',
    borderWidth: 1,
    borderColor: 'rgba(15,28,63,0.12)',
  },
  chipActive: {
    backgroundColor: '#0F1C3F',
    borderColor: '#0F1C3F',
  },
  chipOpenNow: {
    backgroundColor: 'rgba(18,183,106,0.1)',
    borderColor: 'rgba(18,183,106,0.25)',
  },
  chipText: {
    fontSize: 14,
    fontWeight: '500',
  },
  chipTextActive: {
    color: '#fff',
  },
  chipTextOpenNow: {
    color: '#067647',
    fontWeight: '700',
  },
  heroSection: {
    paddingHorizontal: 16,
    paddingTop: 8,
  },
  heroCard: {
    borderRadius: 20,
    overflow: 'hidden',
    height: 220,
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: 5 },
    elevation: 5,
  },
  heroCardImage: { width: '100%', height: '100%' },
  heroCardOverlay: {
    position: 'absolute',
    bottom: 0, left: 0, right: 0,
    padding: 16,
    paddingBottom: 18,
    backgroundColor: 'rgba(0,0,0,0.45)',
    gap: 4,
  },
  heroStatusPill: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8, paddingVertical: 3,
    borderRadius: 50, borderWidth: 1,
    marginBottom: 4,
  },
  pillOpen: { backgroundColor: 'rgba(18,183,106,0.25)', borderColor: 'rgba(18,183,106,0.5)' },
  pillClosed: { backgroundColor: 'rgba(217,45,32,0.2)', borderColor: 'rgba(217,45,32,0.4)' },
  heroStatusText: { fontSize: 10, fontWeight: '700' },
  pillTextOpen: { color: '#6EFAB0' },
  pillTextClosed: { color: '#FFA5A0' },
  heroCardName: { fontSize: 22, fontWeight: '800', lineHeight: 28 },
  heroCardMeta: { fontSize: 13 },
  sectionBlock: {
    paddingTop: 12,
    gap: 8,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    paddingHorizontal: 16,
  },
  hScroll: {
    paddingHorizontal: 16,
    gap: 12,
    paddingBottom: 4,
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 40,
    gap: 12,
    paddingTop: 16,
  },
  countText: {
    fontSize: 13,
    opacity: 0.5,
    fontWeight: '500',
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  card: {
    width: '47.5%',
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOpacity: 0.06,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 3 },
    elevation: 3,
  },
  cardImage: {
    width: '100%',
    height: 130,
  },
  cardBody: {
    padding: 12,
    gap: 5,
  },
  statusDot: {
    width: 7,
    height: 7,
    borderRadius: 4,
  },
  dotOpen: {
    backgroundColor: '#12B76A',
  },
  dotClosed: {
    backgroundColor: '#D92D20',
  },
  cardName: {
    fontSize: 15,
    fontWeight: '700',
    lineHeight: 20,
  },
  cardMeta: {
    fontSize: 12,
    opacity: 0.5,
  },
  cardStory: {
    fontSize: 12,
    opacity: 0.7,
    lineHeight: 17,
  },
  statusText: {
    opacity: 0.5,
    paddingVertical: 8,
  },
  emptyText: {
    opacity: 0.5,
    lineHeight: 22,
    paddingVertical: 8,
  },
  errorBlock: {
    gap: 6,
  },
  errorText: {
    color: '#B42318',
  },
  retryText: {
    color: '#0F1C3F',
    fontWeight: '600',
  },
});
