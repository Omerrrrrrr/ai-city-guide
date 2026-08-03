import React from 'react';
import {
  Dimensions,
  FlatList,
  Image,
  Modal,
  Pressable,
  SafeAreaView,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TextInput,
  View,
  useColorScheme,
} from 'react-native';
import MapView, { Marker, Polyline } from 'react-native-maps';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';

import { PlaceImage } from '@/components/place-image';
import { ThemedText } from '@/components/themed-text';
import { usePlaces } from '@/src/hooks/use-places';
import { useTrips, type TripWaypoint } from '@/src/store/trips';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

const VIEWER_WIDTH = Dimensions.get('window').width;

const PLAYBACK_STEP_MS = 50;
const PLAYBACK_SEGMENT_MS = 450; // compressed travel time between two consecutive breadcrumb points

function interpolate(a: TripWaypoint, b: TripWaypoint, t: number) {
  return { lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t };
}

export default function TripDetailScreen() {
  const { id } = useLocalSearchParams<{ id?: string }>();
  const router = useRouter();
  const { t, i18n } = useTranslation();
  const dark = useColorScheme() === 'dark';
  const { trips, deleteTrip, renameTrip } = useTrips();
  const { data: allPlaces } = usePlaces();

  const trip = trips.find((entry) => entry.id === id);

  const [playing, setPlaying] = React.useState(false);
  const [markerPos, setMarkerPos] = React.useState<{ lat: number; lng: number } | null>(null);
  const playbackRef = React.useRef<{ segment: number; t: number } | null>(null);
  const [editingName, setEditingName] = React.useState(false);
  const [nameInput, setNameInput] = React.useState('');
  const [viewerIndex, setViewerIndex] = React.useState<number | null>(null);

  const stops = React.useMemo(
    () => (trip?.placeIds ?? []).map((placeId) => allPlaces?.find((p) => p.id === placeId)).filter((p) => Boolean(p?.location)),
    [trip, allPlaces]
  );

  React.useEffect(() => {
    if (!playing || !trip || trip.breadcrumb.length < 2) return;
    const interval = setInterval(() => {
      const state = playbackRef.current;
      if (!state) return;
      const nextT = state.t + PLAYBACK_STEP_MS / PLAYBACK_SEGMENT_MS;
      const a = trip.breadcrumb[state.segment];
      const b = trip.breadcrumb[state.segment + 1];

      if (nextT >= 1) {
        const nextSegment = state.segment + 1;
        if (nextSegment >= trip.breadcrumb.length - 1) {
          setMarkerPos({ lat: b.lat, lng: b.lng });
          playbackRef.current = null;
          setPlaying(false);
          return;
        }
        playbackRef.current = { segment: nextSegment, t: 0 };
        setMarkerPos({ lat: b.lat, lng: b.lng });
      } else {
        playbackRef.current = { segment: state.segment, t: nextT };
        setMarkerPos(interpolate(a, b, nextT));
      }
    }, PLAYBACK_STEP_MS);
    return () => clearInterval(interval);
  }, [playing, trip]);

  if (!trip) {
    return (
      <View style={[styles.fullCenter, { backgroundColor: dark ? '#0A0F1E' : '#F4F5F9' }]}>
        <ThemedText style={styles.notFoundText}>{t('trips.notFound')}</ThemedText>
        <Pressable onPress={() => router.back()} style={styles.notFoundBtn}>
          <Text style={styles.notFoundBtnText}>{t('common.cancel')}</Text>
        </Pressable>
      </View>
    );
  }

  const startPlayback = () => {
    if (trip.breadcrumb.length < 2) return;
    playbackRef.current = { segment: 0, t: 0 };
    setMarkerPos({ lat: trip.breadcrumb[0].lat, lng: trip.breadcrumb[0].lng });
    setPlaying(true);
  };

  const stopPlayback = () => {
    setPlaying(false);
    playbackRef.current = null;
    setMarkerPos(null);
  };

  const handleDelete = () => {
    deleteTrip(trip.id);
    router.back();
  };

  const tripDateLabel = new Date(trip.startedAt).toLocaleDateString(i18n.language, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
  const tripTitle = trip.name?.trim() || tripDateLabel;

  const handleShare = async () => {
    const stopNames = stops.map((place) => place!.name).join(' → ');
    const distanceLine =
      trip.distanceMeters != null
        ? t('trips.share.distance', { km: (trip.distanceMeters / 1000).toFixed(1) })
        : '';
    const message = t('trips.share.message', {
      title: tripTitle,
      date: tripDateLabel,
      stops: stopNames || t('trips.share.noStops'),
      distanceLine,
    });
    try {
      await Share.share({ message });
    } catch { /* user cancelled or share failed — non-critical */ }
  };

  const allCoords = [
    ...(trip.routeGeometry ?? []).map(([lat, lng]) => ({ latitude: lat, longitude: lng })),
    ...trip.breadcrumb.map((p) => ({ latitude: p.lat, longitude: p.lng })),
    ...stops.map((p) => ({ latitude: p!.location!.lat, longitude: p!.location!.lng })),
  ];
  const initialRegion = allCoords.length
    ? {
        latitude: allCoords.reduce((s, c) => s + c.latitude, 0) / allCoords.length,
        longitude: allCoords.reduce((s, c) => s + c.longitude, 0) / allCoords.length,
        latitudeDelta: 0.05,
        longitudeDelta: 0.05,
      }
    : undefined;

  return (
    <View style={{ flex: 1, backgroundColor: dark ? '#0A0F1E' : '#F4F5F9' }}>
      <SafeAreaView style={{ backgroundColor: NAVY }}>
        <View style={styles.header}>
          <Pressable onPress={() => router.back()} style={({ pressed }) => pressed && { opacity: 0.7 }}>
            <ThemedText style={styles.backBtn} lightColor="rgba(255,255,255,0.7)" darkColor="rgba(255,255,255,0.7)">
              {t('common.cancel')}
            </ThemedText>
          </Pressable>

          {editingName ? (
            <TextInput
              value={nameInput}
              onChangeText={setNameInput}
              autoFocus
              style={styles.headerTitleInput}
              placeholder={tripDateLabel}
              placeholderTextColor="rgba(255,255,255,0.4)"
              returnKeyType="done"
              onSubmitEditing={() => { renameTrip(trip.id, nameInput.trim()); setEditingName(false); }}
              onBlur={() => { renameTrip(trip.id, nameInput.trim()); setEditingName(false); }}
            />
          ) : (
            <Pressable
              style={styles.headerTitleBtn}
              onPress={() => { setNameInput(trip.name ?? ''); setEditingName(true); }}>
              <ThemedText numberOfLines={1} style={styles.headerTitle} lightColor="#fff" darkColor="#fff">
                {tripTitle}
              </ThemedText>
              <Text style={styles.headerTitleEditHint}>✎</Text>
            </Pressable>
          )}

          <View style={styles.headerActions}>
            <Pressable onPress={handleShare} style={({ pressed }) => pressed && { opacity: 0.7 }}>
              <Text style={styles.shareBtn}>⬆</Text>
            </Pressable>
            <Pressable onPress={handleDelete} style={({ pressed }) => pressed && { opacity: 0.7 }}>
              <ThemedText style={styles.deleteBtn} lightColor="rgba(255,255,255,0.6)" darkColor="rgba(255,255,255,0.6)">
                {t('common.clear')}
              </ThemedText>
            </Pressable>
          </View>
        </View>
      </SafeAreaView>

      <View style={styles.mapWrap}>
        <MapView style={styles.map} initialRegion={initialRegion}>
          {trip.routeGeometry && trip.routeGeometry.length > 1 && (
            <Polyline
              coordinates={trip.routeGeometry.map(([lat, lng]) => ({ latitude: lat, longitude: lng }))}
              strokeColor={GOLD}
              strokeWidth={4}
            />
          )}
          {trip.breadcrumb.length > 1 && (
            <Polyline
              coordinates={trip.breadcrumb.map((p) => ({ latitude: p.lat, longitude: p.lng }))}
              strokeColor={NAVY}
              strokeWidth={4}
            />
          )}
          {stops.map((place, index) => (
            <Marker key={place!.id} coordinate={{ latitude: place!.location!.lat, longitude: place!.location!.lng }}>
              <View style={styles.stopPin}>
                <Text style={styles.stopPinText}>{index + 1}</Text>
              </View>
            </Marker>
          ))}
          {markerPos && (
            <Marker coordinate={{ latitude: markerPos.lat, longitude: markerPos.lng }} anchor={{ x: 0.5, y: 0.5 }}>
              <View style={styles.playbackDot} />
            </Marker>
          )}
        </MapView>

        {trip.breadcrumb.length > 1 && (
          <Pressable style={styles.playBtn} onPress={playing ? stopPlayback : startPlayback}>
            <Text style={styles.playBtnText}>{playing ? `⏸ ${t('trips.pause')}` : `▶ ${t('trips.play')}`}</Text>
          </Pressable>
        )}
      </View>

      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <ThemedText style={styles.sectionLabel}>{t('trips.stopsLabel')}</ThemedText>
        <View style={styles.stopsList}>
          {stops.map((place, index) => (
            <Pressable
              key={place!.id}
              style={({ pressed }) => [styles.stopRow, pressed && { opacity: 0.75 }]}
              onPress={() => router.push({ pathname: '/place/[id]', params: { id: place!.id } })}>
              <View style={styles.stopRowIndex}>
                <Text style={styles.stopRowIndexText}>{index + 1}</Text>
              </View>
              <PlaceImage place={place!} style={styles.stopRowImage} />
              <ThemedText numberOfLines={1} style={styles.stopRowName}>{place!.name}</ThemedText>
            </Pressable>
          ))}
        </View>

        {trip.photos.length > 0 && (
          <>
            <ThemedText style={styles.sectionLabel}>{t('trips.photosLabel')}</ThemedText>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.photosRow}>
              {trip.photos.map((photo, index) => (
                <Pressable key={photo.uri + photo.timestamp} onPress={() => setViewerIndex(index)}>
                  <Image source={{ uri: photo.uri }} style={styles.photo} />
                </Pressable>
              ))}
            </ScrollView>
          </>
        )}
      </ScrollView>

      <Modal
        visible={viewerIndex !== null}
        animationType="fade"
        transparent
        onRequestClose={() => setViewerIndex(null)}>
        <View style={styles.viewerBackdrop}>
          <SafeAreaView style={styles.viewerHeader}>
            <ThemedText style={styles.viewerCount} lightColor="#fff" darkColor="#fff">
              {viewerIndex != null ? `${viewerIndex + 1} / ${trip.photos.length}` : ''}
            </ThemedText>
            <Pressable onPress={() => setViewerIndex(null)} hitSlop={12}>
              <Text style={styles.viewerCloseText}>×</Text>
            </Pressable>
          </SafeAreaView>
          {viewerIndex != null && (
            <FlatList
              style={styles.viewerList}
              data={trip.photos}
              keyExtractor={(photo) => photo.uri + photo.timestamp}
              horizontal
              pagingEnabled
              showsHorizontalScrollIndicator={false}
              initialScrollIndex={viewerIndex}
              getItemLayout={(_, index) => ({ length: VIEWER_WIDTH, offset: VIEWER_WIDTH * index, index })}
              onMomentumScrollEnd={(e) => {
                const nextIndex = Math.round(e.nativeEvent.contentOffset.x / VIEWER_WIDTH);
                setViewerIndex(nextIndex);
              }}
              renderItem={({ item }) => (
                <View style={styles.viewerPage}>
                  <Image source={{ uri: item.uri }} style={styles.viewerImage} resizeMode="contain" />
                </View>
              )}
            />
          )}
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  fullCenter: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 16 },
  notFoundText: { opacity: 0.6 },
  notFoundBtn: { paddingHorizontal: 20, paddingVertical: 10 },
  notFoundBtnText: { color: NAVY, fontWeight: '600' },

  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 16,
  },
  backBtn: { fontSize: 16 },
  headerTitleBtn: { flexDirection: 'row', alignItems: 'center', gap: 6, flexShrink: 1, paddingHorizontal: 8 },
  headerTitle: { fontSize: 17, fontWeight: '700', flexShrink: 1 },
  headerTitleEditHint: { fontSize: 12, color: 'rgba(255,255,255,0.5)' },
  headerTitleInput: {
    flex: 1, marginHorizontal: 8,
    fontSize: 17, fontWeight: '700', color: '#fff',
    borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.4)',
    paddingVertical: 2,
  },
  headerActions: { flexDirection: 'row', alignItems: 'center', gap: 14 },
  shareBtn: { fontSize: 18, color: 'rgba(255,255,255,0.7)' },
  deleteBtn: { fontSize: 15 },

  mapWrap: { height: 280 },
  map: { flex: 1 },
  stopPin: {
    minWidth: 26, height: 26, borderRadius: 13, paddingHorizontal: 6,
    backgroundColor: GOLD, borderWidth: 2.5, borderColor: '#fff',
    alignItems: 'center', justifyContent: 'center',
    shadowColor: '#000', shadowOpacity: 0.3, shadowRadius: 4,
    shadowOffset: { width: 0, height: 2 }, elevation: 4,
  },
  stopPinText: { color: NAVY, fontWeight: '800', fontSize: 13 },
  playbackDot: {
    width: 16, height: 16, borderRadius: 8,
    backgroundColor: '#D9342A', borderWidth: 2, borderColor: '#fff',
  },
  playBtn: {
    position: 'absolute', bottom: 14, alignSelf: 'center',
    backgroundColor: NAVY, borderRadius: 50,
    paddingHorizontal: 20, paddingVertical: 12,
    shadowColor: '#000', shadowOpacity: 0.2, shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 }, elevation: 5,
  },
  playBtnText: { color: '#fff', fontWeight: '700', fontSize: 14 },

  content: { padding: 16, gap: 10, paddingBottom: 40 },
  sectionLabel: {
    fontSize: 12, fontWeight: '700', opacity: 0.45,
    textTransform: 'uppercase', letterSpacing: 0.8,
    marginTop: 8,
  },
  stopsList: { gap: 8 },
  stopRow: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  stopRowIndex: {
    width: 22, height: 22, borderRadius: 11,
    backgroundColor: 'rgba(212,168,67,0.15)',
    alignItems: 'center', justifyContent: 'center',
  },
  stopRowIndexText: { fontSize: 11, fontWeight: '800', color: GOLD },
  stopRowImage: { width: 44, height: 44, borderRadius: 10 },
  stopRowName: { flex: 1, fontSize: 14, fontWeight: '600' },
  photosRow: { gap: 8 },
  photo: { width: 90, height: 90, borderRadius: 12 },

  viewerBackdrop: { flex: 1, backgroundColor: '#000' },
  viewerHeader: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 20, paddingTop: 8,
  },
  viewerCount: { fontSize: 14, fontWeight: '600' },
  viewerCloseText: { fontSize: 30, color: '#fff', lineHeight: 32 },
  viewerList: { flex: 1 },
  viewerPage: { width: VIEWER_WIDTH, alignItems: 'center', justifyContent: 'center' },
  viewerImage: { width: VIEWER_WIDTH, height: '100%' },
});
