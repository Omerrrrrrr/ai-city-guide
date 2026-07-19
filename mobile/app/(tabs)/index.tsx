import React from 'react';
import {
  Pressable,
  RefreshControl,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  View,
  useColorScheme,
} from 'react-native';
import { Link, useRouter } from 'expo-router';
import type { TFunction } from 'i18next';
import { useTranslation } from 'react-i18next';

import { PlaceImage } from '@/components/place-image';
import { FeaturedCardSkeleton, PlaceRowSkeleton } from '@/components/skeleton';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import type { Place } from '@/src/data/places';
import { usePlaces, useNearbyUserPlaces } from '@/src/hooks/use-places';
import { useWeather, weatherEmoji, isIndoorWeather, type Weather } from '@/src/hooks/use-weather';
import { isHighQualityPlace, sortPlacesForBrowse, sortPlacesForProfile } from '@/src/utils/place-filters';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';
import { useUserProfile } from '@/src/store/user-profile';
import { useRecentlyViewed } from '@/src/store/recently-viewed';
import { useCityStore } from '@/src/store/city';
import * as Haptics from 'expo-haptics';
import { useCityStatus } from '@/src/hooks/use-city-status';
import { useAutoCity } from '@/src/hooks/use-auto-city';
import { CATEGORY_EMOJI, categoryEmoji, formatCategory } from '@/src/utils/categories';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

function useIntents() {
  const { t } = useTranslation();
  return [
    { key: 'openNow', label: t('home.intents.openNow'), params: { openNow: 'true' } },
    { key: 'rainyDay', label: t('home.intents.rainyDay'), params: { tag: 'rainy day' } },
    { key: 'photoSpots', label: t('home.intents.photoSpots'), params: { tag: 'photogenic' } },
    { key: 'family', label: t('home.intents.family'), params: { tag: 'family' } },
    { key: 'localPicks', label: t('home.intents.localPicks'), params: { tag: 'local favorite' } },
    { key: 'quickStop', label: t('home.intents.quickStop'), params: { tag: 'short stop' } },
  ];
}

function greeting(t: TFunction, name: string) {
  const h = new Date().getHours();
  const key = h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening';
  const base = t(`home.greeting.${key}`);
  return name ? t('home.greeting.withName', { greeting: base, name }) : base;
}

function weatherBannerMessage(t: TFunction, w: Weather): string {
  const { condition, temp } = w;
  if (condition === 'rainy' || condition === 'stormy') {
    return t('home.weatherBanner.rainy');
  }
  if (condition === 'snowy') return t('home.weatherBanner.snowy');
  if (condition === 'sunny' && temp > 22) return t('home.weatherBanner.sunnyHot');
  if (condition === 'sunny' && temp > 16) return t('home.weatherBanner.sunnyMild');
  if (condition === 'foggy') return t('home.weatherBanner.foggy');
  return t('home.weatherBanner.fallback', { description: w.description, city: w.city });
}

function WeatherPill({ weather }: { weather: NonNullable<ReturnType<typeof useWeather>['weather']> }) {
  return (
    <View style={styles.weatherPill}>
      <ThemedText style={styles.weatherEmoji}>
        {weatherEmoji(weather.condition)}
      </ThemedText>
      <ThemedText style={styles.weatherTemp} lightColor="rgba(255,255,255,0.9)" darkColor="rgba(255,255,255,0.9)">
        {weather.temp}°
      </ThemedText>
      <ThemedText style={styles.weatherCity} lightColor="rgba(255,255,255,0.55)" darkColor="rgba(255,255,255,0.55)">
        {weather.city}
      </ThemedText>
    </View>
  );
}

function StatusBadge({ place }: { place: Place }) {
  const { t } = useTranslation();
  const status = getPlaceOpenStatus(place, t);
  const open = status.state === 'open' || status.state === 'all-day';
  return (
    <View style={[styles.badge, open ? styles.badgeOpen : styles.badgeClosed]}>
      <ThemedText style={[styles.badgeText, open ? styles.badgeTextOpen : styles.badgeTextClosed]}>
        {status.shortLabel}
      </ThemedText>
    </View>
  );
}

function FeaturedCard({ place }: { place: Place }) {
  const { t } = useTranslation();
  return (
    <Link href={{ pathname: '/place/[id]', params: { id: place.id } }} asChild>
      <Pressable style={({ pressed }) => [styles.featCard, pressed && styles.pressed]}>
        <ThemedView style={styles.featCardInner}>
          <PlaceImage place={place} style={styles.featImage} />
          <View style={styles.featBody}>
            <StatusBadge place={place} />
            <ThemedText numberOfLines={2} style={styles.featName}>{place.name}</ThemedText>
            <ThemedText numberOfLines={1} style={styles.featMeta}>
              {categoryEmoji(place.category)} {formatCategory(place.category, t)}
            </ThemedText>
          </View>
        </ThemedView>
      </Pressable>
    </Link>
  );
}

function PlaceRow({ place }: { place: Place }) {
  const { t } = useTranslation();
  return (
    <Link href={{ pathname: '/place/[id]', params: { id: place.id } }} asChild>
      <Pressable style={({ pressed }) => [pressed && styles.pressed]}>
        <ThemedView style={styles.row}>
          <PlaceImage place={place} style={styles.rowThumb} compact />
          <View style={styles.rowBody}>
            <ThemedText numberOfLines={1} style={styles.rowName}>{place.name}</ThemedText>
            <ThemedText numberOfLines={1} style={styles.rowMeta}>
              {categoryEmoji(place.category)} {formatCategory(place.category, t)}{place.tags[0] ? ` · ${place.tags[0]}` : ''}
            </ThemedText>
          </View>
          <StatusBadge place={place} />
        </ThemedView>
      </Pressable>
    </Link>
  );
}

function Section({ title, places, seeAllParams }: { title: string; places: Place[]; seeAllParams?: Record<string, string> }) {
  const router = useRouter();
  const { t } = useTranslation();
  if (!places.length) return null;
  return (
    <View style={styles.section}>
      <View style={styles.sectionHeader}>
        <ThemedText style={styles.sectionTitle}>{title}</ThemedText>
        {seeAllParams && (
          <Pressable
            onPress={() => router.push({ pathname: '/explore', params: seeAllParams })}
            style={({ pressed }) => pressed && { opacity: 0.6 }}>
            <ThemedText style={styles.seeAll}>{t('common.seeAll')}</ThemedText>
          </Pressable>
        )}
      </View>
      {places.map((p) => <PlaceRow key={p.id} place={p} />)}
    </View>
  );
}

function ProfileNudge() {
  const router = useRouter();
  const { t } = useTranslation();
  return (
    <Pressable
      style={({ pressed }) => [styles.profileNudge, pressed && styles.pressed]}
      onPress={() => router.push('/(tabs)/settings')}>
      <View style={styles.profileNudgeLeft}>
        <ThemedText style={styles.profileNudgeTitle} lightColor="#fff" darkColor="#fff">
          {t('home.profileNudge.title')}
        </ThemedText>
        <ThemedText style={styles.profileNudgeBody} lightColor="rgba(255,255,255,0.65)" darkColor="rgba(255,255,255,0.65)">
          {t('home.profileNudge.body')}
        </ThemedText>
      </View>
      <ThemedText style={styles.profileNudgeArrow} lightColor={GOLD} darkColor={GOLD}>›</ThemedText>
    </Pressable>
  );
}

function DiscoveryBanner({ cityName }: { cityName: string }) {
  const { t } = useTranslation();
  const [dots, setDots] = React.useState('');
  React.useEffect(() => {
    const interval = setInterval(() => setDots((d) => (d.length >= 3 ? '' : d + '.')), 600);
    return () => clearInterval(interval);
  }, []);
  return (
    <View style={styles.discoveryBanner}>
      <ThemedText style={styles.discoveryEmoji}>◈</ThemedText>
      <View style={{ flex: 1 }}>
        <ThemedText style={styles.discoveryTitle} lightColor="#fff" darkColor="#fff">
          {t('home.discovery.title', { cityName, dots })}
        </ThemedText>
        <ThemedText style={styles.discoveryBody} lightColor="rgba(255,255,255,0.6)" darkColor="rgba(255,255,255,0.6)">
          {t('home.discovery.body')}
        </ThemedText>
      </View>
    </View>
  );
}

export default function HomeScreen() {
  const colorScheme = useColorScheme();
  const dark = colorScheme === 'dark';
  const router = useRouter();
  const { t } = useTranslation();
  const intents = useIntents();
  const [refreshing, setRefreshing] = React.useState(false);
  const { data: places, isLoading, isStale, error: placesError, refresh: refreshPlaces } = usePlaces();
  const { name, profession, interests, faith } = useUserProfile();
  const { weather } = useWeather();
  const nearbyUser = useNearbyUserPlaces(5);
  const { viewedIds, clearHistory } = useRecentlyViewed();
  const { cityName } = useCityStore();
  const { status: discoveryStatus } = useCityStatus(() => refreshPlaces());
  useAutoCity();

  const recentlyViewed = React.useMemo(
    () => viewedIds.map((vid) => places?.find((p) => p.id === vid)).filter(Boolean) as Place[],
    [viewedIds, places]
  );

  const profile = { profession, interests, faith };
  const hasProfile = !!(profession || interests?.length || faith);

  const ranked = React.useMemo(
    () => hasProfile ? sortPlacesForProfile(places ?? [], profile) : sortPlacesForBrowse(places ?? []),
    [places, profession, interests?.join(','), faith]
  );
  const featured = React.useMemo(
    () => ranked.filter(isHighQualityPlace).slice(0, 8),
    [ranked]
  );
  const openNow = React.useMemo(
    () => ranked.filter((p) => {
      const s = getPlaceOpenStatus(p);
      return s.state === 'open' || s.state === 'all-day';
    }).slice(0, 5),
    [ranked]
  );
  const localFavs = React.useMemo(
    () => ranked.filter((p) => p.tags.includes('local favorite')).slice(0, 5),
    [ranked]
  );
  const rainy = React.useMemo(
    () => ranked.filter((p) => p.tags.includes('rainy day')).slice(0, 4),
    [ranked]
  );

  return (
    <View style={{ flex: 1, backgroundColor: dark ? '#0A0F1E' : '#F4F5F9' }}>
      {/* Header */}
      <SafeAreaView style={{ backgroundColor: NAVY }}>
        <View style={styles.header}>
          <View style={styles.headerTop}>
            <View>
              <ThemedText style={styles.wordmark} lightColor={GOLD} darkColor={GOLD}>PIRI</ThemedText>
              <ThemedText style={styles.greetText} lightColor="rgba(255,255,255,0.75)" darkColor="rgba(255,255,255,0.75)">
                {greeting(t, name)}
              </ThemedText>
              <Pressable
                onPress={() => router.push('/city-picker' as never)}
                style={({ pressed }) => [styles.cityPill, pressed && { opacity: 0.7 }]}>
                <ThemedText style={styles.cityPillText} lightColor="rgba(255,255,255,0.55)" darkColor="rgba(255,255,255,0.55)">
                  {cityName ? t('home.cityPill', { cityName }) : t('common.everywhere')} ›
                </ThemedText>
              </Pressable>
            </View>
            {weather && <WeatherPill weather={weather} />}
          </View>
          <Pressable
            style={styles.headerSearch}
            onPress={() => router.push('/explore' as never)}>
            <ThemedText style={styles.headerSearchText} lightColor="rgba(255,255,255,0.5)" darkColor="rgba(255,255,255,0.5)">
              {t('common.searchPlaces')}
            </ThemedText>
          </Pressable>
        </View>
      </SafeAreaView>

      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.content}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={async () => {
              setRefreshing(true);
              await refreshPlaces();
              setRefreshing(false);
            }}
            tintColor={GOLD}
            colors={[GOLD]}
          />
        }>

        {/* Intent chips */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.intentRow}>
          {intents.map((intent) => {
            const isRainyHighlight =
              intent.key === 'rainyDay' && weather && isIndoorWeather(weather.condition);
            return (
              <Link key={intent.key} href={{ pathname: '/explore', params: intent.params }} asChild>
                <Pressable
                  style={({ pressed }) => [
                    styles.intentChip,
                    isRainyHighlight && styles.intentChipHighlight,
                    pressed && styles.pressed,
                  ]}>
                  <ThemedText
                    style={[styles.intentChipText, isRainyHighlight && styles.intentChipTextHighlight]}>
                    {intent.label}
                  </ThemedText>
                </Pressable>
              </Link>
            );
          })}
        </ScrollView>

        {/* Stale cache indicator */}
        {isStale && !isLoading && (
          <View style={styles.staleBanner}>
            <ThemedText style={styles.staleBannerText}>{t('home.staleBanner')}</ThemedText>
          </View>
        )}

        {/* Error state */}
        {placesError && !isLoading && (
          <View style={styles.errorBanner}>
            <ThemedText style={styles.errorBannerText} lightColor="rgba(255,255,255,0.8)" darkColor="rgba(255,255,255,0.8)">
              {t('home.error')}
            </ThemedText>
            <Pressable
              onPress={refreshPlaces}
              style={({ pressed }) => [styles.errorBannerBtn, pressed && { opacity: 0.7 }]}>
              <ThemedText style={styles.errorBannerBtnText} lightColor={GOLD} darkColor={GOLD}>
                {t('common.retry')}
              </ThemedText>
            </Pressable>
          </View>
        )}

        {/* Profile nudge — only if no profile set */}
        {!hasProfile && !isLoading && (places ?? []).length > 0 && (
          <ProfileNudge />
        )}

        {/* Weather banner */}
        {weather && (
          <Pressable
            style={({ pressed }) => [styles.weatherBanner, pressed && styles.pressed]}
            onPress={() => router.push('/ai')}>
            <View style={styles.weatherBannerLeft}>
              <ThemedText style={styles.weatherBannerEmoji}>
                {weatherEmoji(weather.condition)}
              </ThemedText>
              <View style={{ flex: 1 }}>
                <ThemedText style={styles.weatherBannerMsg} lightColor="#fff" darkColor="#fff">
                  {weatherBannerMessage(t, weather)}
                </ThemedText>
                <ThemedText style={styles.weatherBannerCta} lightColor={GOLD} darkColor={GOLD}>
                  {t('home.weatherBanner.cta')}
                </ThemedText>
              </View>
            </View>
          </Pressable>
        )}

        {/* City discovery progress */}
        {discoveryStatus === 'discovering' && !isLoading && (places ?? []).length === 0 && cityName && (
          <DiscoveryBanner cityName={cityName} />
        )}

        {/* City selected but empty (discovery done, 0 results) */}
        {!isLoading && cityName && discoveryStatus !== 'discovering' && (places ?? []).length === 0 && (
          <View style={styles.cityEmptyBox}>
            <ThemedText style={styles.cityEmptyEmoji}>🏙️</ThemedText>
            <ThemedText style={styles.cityEmptyTitle}>{t('home.cityEmpty.title', { cityName })}</ThemedText>
            <ThemedText style={styles.cityEmptyBody}>{t('home.cityEmpty.body')}</ThemedText>
            <Pressable
              onPress={() => router.push('/city-picker' as never)}
              style={({ pressed }) => [styles.cityEmptyBtn, pressed && { opacity: 0.8 }]}>
              <ThemedText style={styles.cityEmptyBtnText} lightColor={NAVY} darkColor={NAVY}>
                {t('home.cityEmpty.button')}
              </ThemedText>
            </Pressable>
          </View>
        )}

        {/* Featured horizontal scroll */}
        {isLoading ? (
          <View style={styles.section}>
            <ThemedText style={styles.sectionTitle}>{t('home.sections.featured')}</ThemedText>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.featRow}>
              {[1, 2, 3].map((n) => <FeaturedCardSkeleton key={n} />)}
            </ScrollView>
          </View>
        ) : featured.length > 0 ? (
          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <ThemedText style={styles.sectionTitle}>{t('home.sections.featured')}</ThemedText>
              <Pressable
                onPress={() => router.push('/explore' as never)}
                style={({ pressed }) => pressed && { opacity: 0.6 }}>
                <ThemedText style={styles.seeAll}>{t('common.seeAll')}</ThemedText>
              </Pressable>
            </View>
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.featRow}>
              {featured.map((p) => <FeaturedCard key={p.id} place={p} />)}
            </ScrollView>
          </View>
        ) : ranked.length > 0 ? (
          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <ThemedText style={styles.sectionTitle}>{t('home.sections.exploreCity', { cityName })}</ThemedText>
              <Pressable
                onPress={() => router.push('/explore' as never)}
                style={({ pressed }) => pressed && { opacity: 0.6 }}>
                <ThemedText style={styles.seeAll}>{t('common.seeAll')}</ThemedText>
              </Pressable>
            </View>
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.featRow}>
              {ranked.slice(0, 8).map((p) => <FeaturedCard key={p.id} place={p} />)}
            </ScrollView>
          </View>
        ) : null}

        {/* Recently Viewed — horizontal mini scroll */}
        {recentlyViewed.length > 0 && !isLoading && (
          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <ThemedText style={styles.sectionTitle}>{t('home.sections.recentlyViewed')}</ThemedText>
              <Pressable
                onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); clearHistory(); }}
                style={({ pressed }) => pressed && { opacity: 0.6 }}>
                <ThemedText style={styles.seeAll}>{t('common.clear')}</ThemedText>
              </Pressable>
            </View>
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.recentRow}>
              {recentlyViewed.map((p) => (
                <Link key={p.id} href={{ pathname: '/place/[id]', params: { id: p.id } }} asChild>
                  <Pressable style={({ pressed }) => [styles.recentCard, pressed && styles.pressed]}>
                    <PlaceImage place={p} style={styles.recentCardImage} />
                    <ThemedText numberOfLines={2} style={styles.recentCardName}>{p.name}</ThemedText>
                  </Pressable>
                </Link>
              ))}
            </ScrollView>
          </View>
        )}

        {/* Near You */}
        {nearbyUser.length > 0 && (
          <View style={styles.section}>
            <ThemedText style={styles.sectionTitle}>{t('home.sections.nearYou')}</ThemedText>
            {nearbyUser.map((p) => (
              <Link key={p.id} href={{ pathname: '/place/[id]', params: { id: p.id } }} asChild>
                <Pressable style={({ pressed }) => [pressed && styles.pressed]}>
                  <ThemedView style={styles.row}>
                    <PlaceImage place={p} style={styles.rowThumb} compact />
                    <View style={styles.rowBody}>
                      <ThemedText numberOfLines={1} style={styles.rowName}>{p.name}</ThemedText>
                      <ThemedText numberOfLines={1} style={styles.rowMeta}>
                        {categoryEmoji(p.category)}{' '}
                        {p.distanceKm < 1
                          ? t('home.distance.meters', { value: Math.round(p.distanceKm * 1000) })
                          : t('home.distance.km', { value: p.distanceKm.toFixed(1) })}
                      </ThemedText>
                    </View>
                    <StatusBadge place={p} />
                  </ThemedView>
                </Pressable>
              </Link>
            ))}
          </View>
        )}

        {isLoading ? (
          <View style={styles.section}>
            <ThemedText style={styles.sectionTitle}>{t('home.sections.openRightNow')}</ThemedText>
            {[1, 2, 3].map((n) => <PlaceRowSkeleton key={n} />)}
          </View>
        ) : (
          <Section title={t('home.sections.openRightNow')} places={openNow} seeAllParams={{ openNow: 'true' }} />
        )}
        <Section
          title={hasProfile ? t('home.sections.forYou') : t('home.sections.localFavorites')}
          places={localFavs}
          seeAllParams={{ tag: 'local favorite' }}
        />
        <Section title={t('home.sections.rainyDay')} places={rainy} seeAllParams={{ tag: 'rainy day' }} />

        {/* Ask AI banner */}
        <Pressable
          style={({ pressed }) => [styles.aiBanner, pressed && styles.pressed]}
          onPress={() => router.push('/ai')}>
          <View>
            <ThemedText style={styles.aiBannerTitle} lightColor="#fff" darkColor="#fff">
              {t('home.aiBanner.title')}
            </ThemedText>
            <ThemedText style={styles.aiBannerSub} lightColor="rgba(255,255,255,0.7)" darkColor="rgba(255,255,255,0.7)">
              {t('home.aiBanner.sub')}
            </ThemedText>
          </View>
          <ThemedText style={styles.aiBannerArrow} lightColor={GOLD} darkColor={GOLD}>›</ThemedText>
        </Pressable>

      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 16,
    gap: 14,
  },
  headerTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
  },
  weatherPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: 20,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  weatherEmoji: {
    fontSize: 16,
  },
  weatherTemp: {
    fontSize: 15,
    fontWeight: '700',
  },
  weatherCity: {
    fontSize: 13,
    fontWeight: '400',
  },
  intentChipHighlight: {
    backgroundColor: NAVY,
    borderColor: GOLD,
  },
  intentChipTextHighlight: {
    color: GOLD,
    fontWeight: '700',
  },
  wordmark: {
    fontSize: 26,
    fontWeight: '800',
    letterSpacing: 6,
  },
  greetText: {
    fontSize: 14,
    fontWeight: '400',
    marginTop: 1,
  },
  cityPill: {
    marginTop: 4,
    alignSelf: 'flex-start',
  },
  cityPillText: {
    fontSize: 13,
    fontWeight: '500',
  },
  headerSearch: {
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 11,
  },
  headerSearchText: {
    fontSize: 15,
  },
  content: {
    paddingBottom: 40,
    gap: 8,
  },
  intentRow: {
    paddingHorizontal: 20,
    paddingVertical: 14,
    gap: 8,
  },
  intentChip: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 50,
    backgroundColor: 'rgba(15,28,63,0.08)',
    borderWidth: 1,
    borderColor: 'rgba(15,28,63,0.12)',
  },
  intentChipText: {
    fontSize: 14,
    fontWeight: '500',
  },
  section: {
    paddingHorizontal: 20,
    gap: 12,
    marginTop: 8,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  sectionTitle: {
    fontSize: 19,
    fontWeight: '700',
  },
  seeAll: {
    fontSize: 14,
    fontWeight: '600',
    color: GOLD,
  },
  recentRow: {
    gap: 10,
    paddingRight: 20,
  },
  recentCard: {
    width: 100,
    gap: 6,
  },
  recentCardImage: {
    width: 100,
    height: 100,
    borderRadius: 12,
  },
  recentCardName: {
    fontSize: 12,
    fontWeight: '600',
    lineHeight: 16,
    opacity: 0.85,
  },
  featRow: {
    gap: 12,
    paddingRight: 20,
  },
  featCard: {
    width: 180,
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOpacity: 0.08,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
    elevation: 3,
  },
  featCardInner: {
    borderRadius: 16,
    overflow: 'hidden',
  },
  featImage: {
    width: '100%',
    height: 130,
  },
  featBody: {
    padding: 12,
    gap: 6,
  },
  featName: {
    fontSize: 15,
    fontWeight: '700',
    lineHeight: 20,
  },
  featMeta: {
    fontSize: 13,
    opacity: 0.55,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    borderRadius: 14,
    padding: 12,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  rowThumb: {
    width: 60,
    height: 60,
    borderRadius: 10,
  },
  rowBody: {
    flex: 1,
    gap: 4,
  },
  rowName: {
    fontSize: 15,
    fontWeight: '600',
  },
  rowMeta: {
    fontSize: 13,
    opacity: 0.55,
  },
  badge: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 50,
    borderWidth: 1,
  },
  badgeOpen: {
    backgroundColor: 'rgba(18,183,106,0.08)',
    borderColor: 'rgba(18,183,106,0.2)',
  },
  badgeClosed: {
    backgroundColor: 'rgba(217,45,32,0.06)',
    borderColor: 'rgba(217,45,32,0.15)',
  },
  badgeText: {
    fontSize: 11,
    fontWeight: '700',
  },
  badgeTextOpen: {
    color: '#067647',
  },
  badgeTextClosed: {
    color: '#B42318',
  },
  profileNudge: {
    marginHorizontal: 20,
    marginTop: 4,
    backgroundColor: 'rgba(15,28,63,0.7)',
    borderRadius: 18,
    padding: 18,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    borderWidth: 1,
    borderColor: 'rgba(212,168,67,0.2)',
  },
  profileNudgeLeft: {
    flex: 1,
    gap: 4,
  },
  profileNudgeTitle: {
    fontSize: 15,
    fontWeight: '700',
  },
  profileNudgeBody: {
    fontSize: 13,
    lineHeight: 19,
  },
  profileNudgeArrow: {
    fontSize: 24,
    fontWeight: '300',
  },
  discoveryBanner: {
    marginHorizontal: 20,
    marginTop: 8,
    marginBottom: 8,
    backgroundColor: NAVY,
    borderRadius: 18,
    padding: 20,
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 14,
    borderWidth: 1,
    borderColor: `rgba(212,168,67,0.25)`,
  },
  discoveryEmoji: {
    fontSize: 28,
    color: GOLD,
    marginTop: 2,
  },
  discoveryTitle: {
    fontSize: 16,
    fontWeight: '700',
    marginBottom: 4,
  },
  discoveryBody: {
    fontSize: 13,
    lineHeight: 19,
  },
  weatherBanner: {
    marginHorizontal: 20,
    marginTop: 8,
    backgroundColor: 'rgba(15,28,63,0.85)',
    borderRadius: 18,
    padding: 16,
  },
  weatherBannerLeft: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
  },
  weatherBannerEmoji: {
    fontSize: 28,
    marginTop: 2,
  },
  weatherBannerMsg: {
    fontSize: 14,
    lineHeight: 20,
    fontWeight: '500',
    marginBottom: 4,
  },
  weatherBannerCta: {
    fontSize: 13,
    fontWeight: '600',
  },
  aiBanner: {
    marginHorizontal: 20,
    marginTop: 16,
    backgroundColor: NAVY,
    borderRadius: 18,
    padding: 20,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  aiBannerTitle: {
    fontSize: 17,
    fontWeight: '700',
    marginBottom: 4,
  },
  aiBannerSub: {
    fontSize: 14,
    lineHeight: 20,
  },
  aiBannerArrow: {
    fontSize: 28,
    fontWeight: '300',
  },
  pressed: {
    opacity: 0.75,
  },
  staleBanner: {
    marginHorizontal: 20,
    marginTop: 4,
    backgroundColor: 'rgba(127,127,127,0.08)',
    borderRadius: 10,
    paddingVertical: 8,
    paddingHorizontal: 14,
    alignItems: 'center',
  },
  staleBannerText: {
    fontSize: 12,
    opacity: 0.5,
    fontWeight: '500',
  },
  errorBanner: {
    marginHorizontal: 20,
    marginTop: 4,
    backgroundColor: 'rgba(180,35,24,0.1)',
    borderRadius: 14,
    padding: 14,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderWidth: 1,
    borderColor: 'rgba(180,35,24,0.2)',
  },
  errorBannerText: {
    flex: 1,
    fontSize: 14,
    lineHeight: 20,
  },
  errorBannerBtn: {
    paddingLeft: 12,
  },
  errorBannerBtnText: {
    fontSize: 14,
    fontWeight: '700',
  },
  cityEmptyBox: {
    marginHorizontal: 20,
    marginTop: 8,
    padding: 28,
    borderRadius: 20,
    alignItems: 'center',
    gap: 10,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.15)',
  },
  cityEmptyEmoji: {
    fontSize: 40,
    opacity: 0.5,
  },
  cityEmptyTitle: {
    fontSize: 17,
    fontWeight: '700',
    textAlign: 'center',
  },
  cityEmptyBody: {
    fontSize: 14,
    opacity: 0.55,
    textAlign: 'center',
    lineHeight: 20,
  },
  cityEmptyBtn: {
    marginTop: 6,
    backgroundColor: GOLD,
    borderRadius: 12,
    paddingHorizontal: 22,
    paddingVertical: 12,
  },
  cityEmptyBtnText: {
    fontSize: 15,
    fontWeight: '700',
  },
});
