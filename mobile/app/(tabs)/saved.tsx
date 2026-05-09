import React from 'react';
import { Link } from 'expo-router';
import { Pressable, StyleSheet, View } from 'react-native';

import ParallaxScrollView from '@/components/parallax-scroll-view';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { usePlaces } from '@/src/hooks/use-places';
import { useSavedPlaces } from '@/src/store/saved-places';

export default function SavedScreen() {
  const { favoritePlaceIds, planPlaceIds, clearFavorites, clearPlan } = useSavedPlaces();
  const [mode, setMode] = React.useState<'favorites' | 'plan'>('favorites');
  const { data: places, error, isLoading, refresh } = usePlaces();

  const favorites = (places ?? []).filter((p) => favoritePlaceIds[p.id]);
  const plan = planPlaceIds
    .map((id) => places?.find((p) => p.id === id))
    .filter((p): p is NonNullable<typeof places>[number] => Boolean(p));

  const list = mode === 'favorites' ? favorites : plan;

  return (
    <ParallaxScrollView
      headerBackgroundColor={{ light: '#D7E8FF', dark: '#10263A' }}
      headerImage={<View style={styles.header} />}>
      <ThemedView style={styles.titleRow}>
        <ThemedText type="title">Saved</ThemedText>
        {list.length > 0 ? (
          <Pressable
            onPress={mode === 'favorites' ? clearFavorites : clearPlan}
            style={({ pressed }) => pressed && styles.pressed}>
            <ThemedText type="link">Clear</ThemedText>
          </Pressable>
        ) : null}
      </ThemedView>

      <ThemedView style={styles.segment}>
        <Pressable
          onPress={() => setMode('favorites')}
          style={({ pressed }) => [
            styles.segmentButton,
            mode === 'favorites' && styles.segmentButtonActive,
            pressed && styles.pressed,
          ]}>
          <ThemedText style={styles.segmentText}>Favorites</ThemedText>
        </Pressable>
        <Pressable
          onPress={() => setMode('plan')}
          style={({ pressed }) => [
            styles.segmentButton,
            mode === 'plan' && styles.segmentButtonActive,
            pressed && styles.pressed,
          ]}>
          <ThemedText style={styles.segmentText}>Plan</ThemedText>
        </Pressable>
      </ThemedView>

      {isLoading ? <ThemedText style={styles.emptyText}>Loading saved places…</ThemedText> : null}
      {error ? (
        <ThemedView style={styles.statusBlock}>
          <ThemedText style={styles.errorText}>{error}</ThemedText>
          <Pressable onPress={refresh} style={({ pressed }) => pressed && styles.pressed}>
            <ThemedText type="link">Retry</ThemedText>
          </Pressable>
        </ThemedView>
      ) : null}

      {!isLoading && !error && list.length === 0 ? (
        <ThemedText style={styles.emptyText}>
          {mode === 'favorites'
            ? 'No favorites yet. Open a place and tap “Save”.'
            : 'No places in your plan yet. Open a place and tap “Add to plan”.'}
        </ThemedText>
      ) : (
        <ThemedView style={styles.list}>
          {list.map((place) => (
            <Link
              key={place.id}
              href={{ pathname: '/place/[id]', params: { id: place.id } }}
              asChild>
              <Pressable style={({ pressed }) => [styles.row, pressed && styles.pressed]}>
                <ThemedText style={styles.rowTitle}>{place.name}</ThemedText>
                <ThemedText style={styles.chev}>›</ThemedText>
              </Pressable>
            </Link>
          ))}
        </ThemedView>
      )}
    </ParallaxScrollView>
  );
}

const styles = StyleSheet.create({
  header: {
    height: 178,
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    marginBottom: 12,
  },
  emptyText: {
    opacity: 0.8,
    lineHeight: 22,
  },
  statusBlock: {
    gap: 6,
    marginBottom: 12,
  },
  errorText: {
    color: '#B42318',
    lineHeight: 20,
  },
  segment: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 12,
  },
  segmentButton: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 10,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
  },
  segmentButtonActive: {
    borderColor: 'rgba(127,127,127,0.55)',
  },
  segmentText: {
    fontSize: 14,
    lineHeight: 18,
  },
  list: {
    gap: 10,
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
  rowTitle: {
    fontSize: 16,
    lineHeight: 22,
  },
  chev: {
    fontSize: 22,
    lineHeight: 22,
    opacity: 0.6,
  },
  pressed: {
    opacity: 0.7,
  },
});
