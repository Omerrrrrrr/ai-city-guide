import React from 'react';
import {
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  View,
  useColorScheme,
} from 'react-native';
import { Link, useLocalSearchParams, useRouter } from 'expo-router';

import { PlaceImage } from '@/components/place-image';
import { ThemedText } from '@/components/themed-text';
import { usePlaces } from '@/src/hooks/use-places';
import { useSavedPlaces } from '@/src/store/saved-places';
import { useRecentlyViewed } from '@/src/store/recently-viewed';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';
import { CATEGORY_EMOJI, formatCategory } from '@/src/utils/categories';
import type { Place } from '@/src/data/places';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

type Tab = 'favorites' | 'plan' | 'visited';

function PlaceListItem({ place }: { place: Place }) {
  const status = getPlaceOpenStatus(place);
  const open = status.state === 'open' || status.state === 'all-day';
  const dark = useColorScheme() === 'dark';
  const cardBg = dark ? '#1A2744' : '#fff';

  return (
    <Link href={{ pathname: '/place/[id]', params: { id: place.id } }} asChild>
      <Pressable style={({ pressed }) => [styles.card, { backgroundColor: cardBg }, pressed && { opacity: 0.75 }]}>
        <PlaceImage place={place} style={styles.cardImage} />
        <View style={styles.cardBody}>
          <ThemedText numberOfLines={2} style={styles.cardName}>{place.name}</ThemedText>
          <ThemedText style={styles.cardCategory}>
            {CATEGORY_EMOJI[place.category] ?? '📍'} {formatCategory(place.category)}
          </ThemedText>
          {place.shortStory ? (
            <ThemedText numberOfLines={1} style={styles.cardStory}>{place.shortStory}</ThemedText>
          ) : null}
          <View style={[styles.statusBadge, open ? styles.badgeOpen : styles.badgeClosed]}>
            <ThemedText style={[styles.statusBadgeText, open ? styles.textOpen : styles.textClosed]}>
              {status.shortLabel}
            </ThemedText>
          </View>
        </View>
        <ThemedText style={styles.chev}>›</ThemedText>
      </Pressable>
    </Link>
  );
}

export default function SavedScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ tab?: Tab }>();
  const { favoritePlaceIds, planPlaceIds, clearFavorites, clearPlan } = useSavedPlaces();
  const { viewedIds, clearHistory } = useRecentlyViewed();
  const [tab, setTab] = React.useState<Tab>(params.tab ?? 'favorites');

  React.useEffect(() => {
    if (params.tab && ['favorites', 'plan', 'visited'].includes(params.tab)) {
      setTab(params.tab);
    }
  }, [params.tab]);
  const { data: places, isLoading } = usePlaces();

  const favorites = (places ?? []).filter((p) => favoritePlaceIds[p.id]);
  const plan = planPlaceIds
    .map((id) => places?.find((p) => p.id === id))
    .filter((p): p is Place => Boolean(p));
  const visited = viewedIds
    .map((id) => places?.find((p) => p.id === id))
    .filter((p): p is Place => Boolean(p));

  const list = tab === 'favorites' ? favorites : tab === 'plan' ? plan : visited;

  const handleClear = () => {
    if (tab === 'favorites') clearFavorites();
    else if (tab === 'plan') clearPlan();
    else clearHistory();
  };

  const emptyTitle = tab === 'favorites' ? 'No favorites yet' : tab === 'plan' ? 'Your plan is empty' : 'No places visited yet';
  const emptyBody = tab === 'favorites'
    ? 'Open a place and tap the heart icon to save it here.'
    : tab === 'plan'
      ? 'Open a place and tap "Add to plan" to build your itinerary.'
      : 'Places you open will appear here.';

  const tabs: { id: Tab; label: string; count: number }[] = [
    { id: 'favorites', label: 'Saved', count: favorites.length },
    { id: 'plan', label: 'Plan', count: plan.length },
    { id: 'visited', label: 'Visited', count: visited.length },
  ];

  return (
    <View style={{ flex: 1 }}>
      <SafeAreaView style={{ backgroundColor: NAVY }}>
        <View style={styles.header}>
          <View style={styles.headerTop}>
            <ThemedText style={styles.headerTitle} lightColor="#fff" darkColor="#fff">Collection</ThemedText>
            {list.length > 0 ? (
              <Pressable
                onPress={handleClear}
                style={({ pressed }) => pressed && { opacity: 0.7 }}>
                <ThemedText style={styles.clearText} lightColor="rgba(255,255,255,0.6)" darkColor="rgba(255,255,255,0.6)">
                  Clear
                </ThemedText>
              </Pressable>
            ) : null}
          </View>

          {/* 3-tab segment */}
          <View style={styles.segment}>
            {tabs.map(({ id, label, count }) => {
              const active = tab === id;
              return (
                <Pressable
                  key={id}
                  style={[styles.segBtn, active && styles.segBtnActive]}
                  onPress={() => setTab(id)}>
                  <ThemedText
                    style={[styles.segText, active && styles.segTextActive]}
                    lightColor={active ? NAVY : 'rgba(255,255,255,0.65)'}
                    darkColor={active ? NAVY : 'rgba(255,255,255,0.65)'}>
                    {label}{count > 0 ? ` ${count}` : ''}
                  </ThemedText>
                </Pressable>
              );
            })}
          </View>
        </View>
      </SafeAreaView>

      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.content}>

        {isLoading && <ThemedText style={styles.statusText}>Loading...</ThemedText>}

        {/* Plan optimizer — shown when Plan tab has ≥2 places */}
        {tab === 'plan' && plan.length >= 2 && (
          <Pressable
            style={({ pressed }) => [styles.optimizeBtn, pressed && { opacity: 0.85 }]}
            onPress={() => {
              const placeNames = plan.map((p) => p.name).join(', ');
              const query = `I'm planning to visit: ${placeNames}. Suggest the best order to visit them today, with estimated time at each and any walking or transport tips between them.`;
              router.push({ pathname: '/(tabs)/ai', params: { q: query } } as never);
            }}>
            <ThemedText style={styles.optimizeBtnEmoji}>◈</ThemedText>
            <View style={{ flex: 1 }}>
              <ThemedText style={styles.optimizeBtnTitle} lightColor="#fff" darkColor="#fff">
                Optimize my day with Piri
              </ThemedText>
              <ThemedText style={styles.optimizeBtnSub} lightColor="rgba(255,255,255,0.6)" darkColor="rgba(255,255,255,0.6)">
                Best order, timings & travel tips for {plan.length} places →
              </ThemedText>
            </View>
          </Pressable>
        )}

        {!isLoading && list.length === 0 ? (
          <View style={styles.emptyState}>
            <ThemedText style={styles.emptyEmoji}>
              {tab === 'favorites' ? '♡' : tab === 'plan' ? '＋' : '◎'}
            </ThemedText>
            <ThemedText style={styles.emptyTitle}>{emptyTitle}</ThemedText>
            <ThemedText style={styles.emptyBody}>{emptyBody}</ThemedText>
          </View>
        ) : (
          list.map((place) => <PlaceListItem key={place.id} place={place} />)
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
    gap: 14,
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
  clearText: {
    fontSize: 15,
  },
  segment: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: 12,
    padding: 3,
    gap: 3,
  },
  segBtn: {
    flex: 1,
    paddingVertical: 9,
    borderRadius: 10,
    alignItems: 'center',
  },
  segBtnActive: {
    backgroundColor: '#fff',
  },
  segText: {
    fontSize: 13,
    fontWeight: '600',
  },
  segTextActive: {},
  content: {
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 40,
    gap: 12,
  },
  optimizeBtn: {
    backgroundColor: NAVY,
    borderRadius: 18,
    padding: 18,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    borderWidth: 1,
    borderColor: `rgba(212,168,67,0.3)`,
  },
  optimizeBtnEmoji: {
    fontSize: 26,
    color: GOLD,
  },
  optimizeBtnTitle: {
    fontSize: 15,
    fontWeight: '700',
    marginBottom: 3,
  },
  optimizeBtnSub: {
    fontSize: 13,
    lineHeight: 18,
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOpacity: 0.06,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 3 },
    elevation: 3,
  },
  cardImage: {
    width: 90,
    height: 90,
  },
  cardBody: {
    flex: 1,
    padding: 12,
    gap: 5,
  },
  cardName: {
    fontSize: 15,
    fontWeight: '700',
    lineHeight: 20,
  },
  cardCategory: {
    fontSize: 12,
    opacity: 0.5,
    fontWeight: '500',
  },
  cardStory: {
    fontSize: 13,
    opacity: 0.6,
    lineHeight: 18,
  },
  statusBadge: {
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
  statusBadgeText: {
    fontSize: 11,
    fontWeight: '700',
  },
  textOpen: { color: '#067647' },
  textClosed: { color: '#B42318' },
  chev: {
    fontSize: 22,
    opacity: 0.35,
    paddingRight: 14,
  },
  statusText: {
    opacity: 0.5,
  },
  emptyState: {
    paddingTop: 60,
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 32,
  },
  emptyEmoji: {
    fontSize: 48,
    opacity: 0.25,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '700',
    textAlign: 'center',
  },
  emptyBody: {
    fontSize: 15,
    opacity: 0.55,
    textAlign: 'center',
    lineHeight: 22,
  },
});
