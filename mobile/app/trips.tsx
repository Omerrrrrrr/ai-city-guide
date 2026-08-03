import React from 'react';
import { Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View, useColorScheme } from 'react-native';
import MapView, { Polyline } from 'react-native-maps';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';

import { ThemedText } from '@/components/themed-text';
import { useTrips, type Trip } from '@/src/store/trips';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

function formatTripDate(timestamp: number, locale: string) {
  return new Date(timestamp).toLocaleDateString(locale, { day: 'numeric', month: 'short', year: 'numeric' });
}

function TripRow({ trip }: { trip: Trip }) {
  const router = useRouter();
  const { t, i18n } = useTranslation();
  const dark = useColorScheme() === 'dark';
  const cardBg = dark ? '#1A2744' : '#fff';
  const points = trip.breadcrumb.length > 1 ? trip.breadcrumb : null;

  return (
    <Pressable
      style={({ pressed }) => [styles.card, { backgroundColor: cardBg }, pressed && { opacity: 0.8 }]}
      onPress={() => router.push({ pathname: '/trip/[id]', params: { id: trip.id } })}>
      <View style={styles.cardMap}>
        {points ? (
          <MapView
            style={styles.cardMapInner}
            scrollEnabled={false}
            zoomEnabled={false}
            rotateEnabled={false}
            pitchEnabled={false}
            initialRegion={regionForPoints(points.map((p) => ({ lat: p.lat, lng: p.lng })))}>
            <Polyline
              coordinates={points.map((p) => ({ latitude: p.lat, longitude: p.lng }))}
              strokeColor={GOLD}
              strokeWidth={3}
            />
          </MapView>
        ) : (
          <View style={[styles.cardMapInner, styles.cardMapEmpty]}>
            <Text style={styles.cardMapEmptyText}>◈</Text>
          </View>
        )}
      </View>
      <View style={styles.cardBody}>
        <ThemedText numberOfLines={1} style={styles.cardDate}>
          {trip.name?.trim() || formatTripDate(trip.startedAt, i18n.language)}
        </ThemedText>
        <ThemedText style={styles.cardMeta}>
          {t('trips.stopsCount', { count: trip.placeIds.length })}
          {trip.photos.length > 0 ? ` · ${t('trips.photosCount', { count: trip.photos.length })}` : ''}
        </ThemedText>
        {!trip.endedAt && (
          <View style={styles.activeBadge}>
            <ThemedText style={styles.activeBadgeText}>{t('trips.inProgress')}</ThemedText>
          </View>
        )}
      </View>
      <ThemedText style={styles.chev}>›</ThemedText>
    </Pressable>
  );
}

function regionForPoints(points: { lat: number; lng: number }[]) {
  const lats = points.map((p) => p.lat);
  const lngs = points.map((p) => p.lng);
  const minLat = Math.min(...lats);
  const maxLat = Math.max(...lats);
  const minLng = Math.min(...lngs);
  const maxLng = Math.max(...lngs);
  return {
    latitude: (minLat + maxLat) / 2,
    longitude: (minLng + maxLng) / 2,
    latitudeDelta: Math.max(0.01, (maxLat - minLat) * 1.6),
    longitudeDelta: Math.max(0.01, (maxLng - minLng) * 1.6),
  };
}

export default function TripsScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const { trips } = useTrips();
  const dark = useColorScheme() === 'dark';

  return (
    <View style={{ flex: 1, backgroundColor: dark ? '#0A0F1E' : '#F4F5F9' }}>
      <SafeAreaView style={{ backgroundColor: NAVY }}>
        <View style={styles.header}>
          <Pressable onPress={() => router.back()} style={({ pressed }) => pressed && { opacity: 0.7 }}>
            <ThemedText style={styles.backBtn} lightColor="rgba(255,255,255,0.7)" darkColor="rgba(255,255,255,0.7)">
              {t('common.cancel')}
            </ThemedText>
          </Pressable>
          <ThemedText style={styles.headerTitle} lightColor="#fff" darkColor="#fff">{t('trips.title')}</ThemedText>
          <View style={{ width: 56 }} />
        </View>
      </SafeAreaView>

      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        {trips.length === 0 ? (
          <View style={styles.emptyState}>
            <ThemedText style={styles.emptyEmoji}>◈</ThemedText>
            <ThemedText style={styles.emptyTitle}>{t('trips.empty.title')}</ThemedText>
            <ThemedText style={styles.emptyBody}>{t('trips.empty.body')}</ThemedText>
          </View>
        ) : (
          trips.map((trip) => <TripRow key={trip.id} trip={trip} />)
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 16,
  },
  backBtn: { fontSize: 16, width: 56 },
  headerTitle: { fontSize: 17, fontWeight: '700' },
  content: { padding: 16, gap: 12, paddingBottom: 40 },
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
  cardMap: { width: 84, height: 84 },
  cardMapInner: { flex: 1 },
  cardMapEmpty: { alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(15,28,63,0.06)' },
  cardMapEmptyText: { fontSize: 24, color: GOLD },
  cardBody: { flex: 1, padding: 12, gap: 5 },
  cardDate: { fontSize: 15, fontWeight: '700' },
  cardMeta: { fontSize: 13, opacity: 0.55 },
  activeBadge: {
    alignSelf: 'flex-start',
    marginTop: 2,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 50,
    backgroundColor: 'rgba(217,45,32,0.08)',
  },
  activeBadgeText: { fontSize: 11, fontWeight: '700', color: '#B42318' },
  chev: { fontSize: 22, opacity: 0.35, paddingRight: 14 },
  emptyState: { paddingTop: 60, alignItems: 'center', gap: 12, paddingHorizontal: 32 },
  emptyEmoji: { fontSize: 48, opacity: 0.25, color: GOLD },
  emptyTitle: { fontSize: 20, fontWeight: '700', textAlign: 'center' },
  emptyBody: { fontSize: 15, opacity: 0.55, textAlign: 'center', lineHeight: 22 },
});
