import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
  useColorScheme,
} from 'react-native';
import MapView, { Marker, Polyline, Region } from 'react-native-maps';
import * as Location from 'expo-location';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { PlaceImage } from '@/components/place-image';
import { ThemedText } from '@/components/themed-text';
import { CATEGORY_FILTERS } from '@/src/constants/category-filters';
import type { Place, PlaceCategory } from '@/src/data/places';
import { usePlaces } from '@/src/hooks/use-places';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';
import { useCityStore } from '@/src/store/city';
import { CATEGORY_EMOJI, formatCategory } from '@/src/utils/categories';
import { fetchDirections } from '@/src/api/routes';
import { useTrips } from '@/src/store/trips';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

const KRISTIANSAND: Region = {
  latitude: 58.146,
  longitude: 7.995,
  latitudeDelta: 0.05,
  longitudeDelta: 0.05,
};

const MAP_CATEGORY_IDS: (PlaceCategory | 'all')[] = [
  'all', 'museum', 'landmark', 'cafe', 'restaurant', 'beach', 'viewpoint', 'nature',
];
const MAP_CATEGORY_FILTERS = CATEGORY_FILTERS.filter((c) => MAP_CATEGORY_IDS.includes(c.id));

export default function MapScreen() {
  const colorScheme = useColorScheme();
  const dark = colorScheme === 'dark';
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const mapRef = React.useRef<MapView>(null);

  const { data: places, error, isLoading } = usePlaces();
  const { cityId } = useCityStore();
  const [locationReady, setLocationReady] = React.useState(false);
  const [region, setRegion] = React.useState<Region>(KRISTIANSAND);
  const [selectedPlace, setSelectedPlace] = React.useState<Place | null>(null);
  const [activeCategory, setActiveCategory] = React.useState<PlaceCategory | 'all'>('all');

  // Route planning
  const { activeTripId, startTrip, endTrip } = useTrips();
  const [routeMode, setRouteMode] = React.useState(false);
  const [plannedStops, setPlannedStops] = React.useState<Place[]>([]);
  const [routeGeometry, setRouteGeometry] = React.useState<[number, number][] | null>(null);
  const [isFetchingRoute, setIsFetchingRoute] = React.useState(false);
  const [routeError, setRouteError] = React.useState<string | null>(null);

  const toggleRouteMode = () => {
    setSelectedPlace(null);
    setRouteMode((prev) => !prev);
    if (activeTripId) return; // keep an in-progress trip's stops/route visible
    setPlannedStops([]);
    setRouteGeometry(null);
    setRouteError(null);
  };

  const toggleStop = (place: Place) => {
    setPlannedStops((prev) =>
      prev.some((p) => p.id === place.id) ? prev.filter((p) => p.id !== place.id) : [...prev, place]
    );
  };

  const handleStartRoute = async () => {
    if (plannedStops.length < 2) return;
    setIsFetchingRoute(true);
    setRouteError(null);
    try {
      const result = await fetchDirections(plannedStops.map((p) => ({ lat: p.location!.lat, lng: p.location!.lng })));
      setRouteGeometry(result.route);
      startTrip(
        plannedStops.map((p) => p.id),
        result.route
      );
    } catch (err) {
      setRouteError(err instanceof Error ? err.message : t('map.route.failed'));
    } finally {
      setIsFetchingRoute(false);
    }
  };

  const handleEndRoute = () => {
    if (activeTripId) endTrip(activeTripId);
    setRouteMode(false);
    setPlannedStops([]);
    setRouteGeometry(null);
  };

  React.useEffect(() => {
    void (async () => {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') { setLocationReady(true); return; }
      try {
        const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
        setRegion({
          latitude: loc.coords.latitude,
          longitude: loc.coords.longitude,
          latitudeDelta: 0.05,
          longitudeDelta: 0.05,
        });
      } catch { /* keep default */ }
      finally { setLocationReady(true); }
    })();
  }, []);

  // Center map once when we first get places for a city.
  // Depends on both cityId and whether places have loaded, because places are
  // empty when cityId first changes (discovery still running) and only arrive later.
  const centeredForCityRef = React.useRef<string | null>(null);
  React.useEffect(() => {
    if (!places?.length || !mapRef.current) return;
    if (centeredForCityRef.current === cityId) return;
    const withLoc = places.filter((p) => p.location);
    if (!withLoc.length) return;
    centeredForCityRef.current = cityId ?? null;
    const avgLat = withLoc.reduce((s, p) => s + p.location!.lat, 0) / withLoc.length;
    const avgLng = withLoc.reduce((s, p) => s + p.location!.lng, 0) / withLoc.length;
    setSelectedPlace(null);
    mapRef.current.animateToRegion({ latitude: avgLat, longitude: avgLng, latitudeDelta: 0.06, longitudeDelta: 0.06 }, 800);
  }, [cityId, places]);

  const goToMyLocation = async () => {
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') return;
    try {
      const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
      mapRef.current?.animateToRegion({
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
        latitudeDelta: 0.02,
        longitudeDelta: 0.02,
      }, 600);
    } catch { /* ignore */ }
  };

  const filteredPlaces = React.useMemo(() => {
    const withLocation = (places ?? []).filter((p) => p.location);
    if (activeCategory === 'all') return withLocation;
    return withLocation.filter((p) => p.category === activeCategory);
  }, [places, activeCategory]);

  if (isLoading || !locationReady) {
    return (
      <View style={[styles.fullCenter, { backgroundColor: dark ? '#0A0F1E' : '#F4F5F9' }]}>
        <ActivityIndicator size="large" color={NAVY} />
        <ThemedText style={styles.loadingText}>{t('map.loading')}</ThemedText>
      </View>
    );
  }

  if (error) {
    return (
      <View style={[styles.fullCenter, { backgroundColor: dark ? '#0A0F1E' : '#F4F5F9' }]}>
        <ThemedText style={styles.errorText}>{error}</ThemedText>
      </View>
    );
  }

  const selectedStatus = selectedPlace ? getPlaceOpenStatus(selectedPlace, t) : null;
  const selectedOpen = selectedStatus?.state === 'open' || selectedStatus?.state === 'all-day';

  return (
    <View style={styles.container}>
      <MapView
        ref={mapRef}
        style={styles.map}
        initialRegion={region}
        showsUserLocation
        showsMyLocationButton={false}
        showsCompass={false}
        onPress={() => setSelectedPlace(null)}>
        {filteredPlaces.map((place) => {
          const isSelected = selectedPlace?.id === place.id;
          const stopIndex = plannedStops.findIndex((p) => p.id === place.id);
          const isStop = stopIndex !== -1;
          return (
            <Marker
              key={place.id}
              coordinate={{ latitude: place.location!.lat, longitude: place.location!.lng }}
              onPress={(e) => {
                e.stopPropagation();
                if (routeMode) {
                  if (!activeTripId) toggleStop(place);
                  return;
                }
                setSelectedPlace(place);
                mapRef.current?.animateToRegion({
                  latitude: place.location!.lat - 0.005,
                  longitude: place.location!.lng,
                  latitudeDelta: 0.025,
                  longitudeDelta: 0.025,
                }, 400);
              }}>
              {isStop ? (
                <View style={styles.stopPin}>
                  <Text style={styles.stopPinText}>{stopIndex + 1}</Text>
                </View>
              ) : (
                <View style={[styles.pin, isSelected && styles.pinSelected]}>
                  <View style={[styles.pinDot, isSelected && styles.pinDotSelected]} />
                </View>
              )}
            </Marker>
          );
        })}
        {routeGeometry && routeGeometry.length > 1 && (
          <Polyline
            coordinates={routeGeometry.map(([lat, lng]) => ({ latitude: lat, longitude: lng }))}
            strokeColor={GOLD}
            strokeWidth={4}
          />
        )}
      </MapView>

      {/* Top: category chips + count pill */}
      <SafeAreaView style={styles.topOverlay} pointerEvents="box-none">
        <View style={[styles.countPill, { marginTop: 10 }]}>
          <Text style={styles.countPillText}>
            {activeCategory === 'all'
              ? t('map.placesCount', { count: filteredPlaces.length })
              : `${filteredPlaces.length} ${t(MAP_CATEGORY_FILTERS.find((c) => c.id === activeCategory)?.labelKey ?? 'categoryFilters.all')}`}
          </Text>
        </View>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.categoryRow}
          pointerEvents="auto">
          {MAP_CATEGORY_FILTERS.map((c) => {
            const active = activeCategory === c.id;
            return (
              <Pressable
                key={c.id}
                onPress={() => { setActiveCategory(c.id); setSelectedPlace(null); }}
                style={[styles.categoryChip, active && styles.categoryChipActive]}>
                <Text style={[styles.categoryChipText, active && styles.categoryChipTextActive]}>
                  {c.emoji ? `${c.emoji} ` : ''}{t(c.labelKey)}
                </Text>
              </Pressable>
            );
          })}
        </ScrollView>
      </SafeAreaView>

      {/* Route planning toggle */}
      <Pressable
        style={({ pressed }) => [
          styles.locationBtn,
          styles.routeToggleBtn,
          { bottom: insets.bottom + (routeMode ? 190 : 96) },
          routeMode && styles.routeToggleBtnActive,
          pressed && { opacity: 0.8 },
        ]}
        onPress={toggleRouteMode}>
        <Text style={[styles.locationBtnText, routeMode && styles.routeToggleTextActive]}>⚐</Text>
      </Pressable>

      {/* My location button */}
      <Pressable
        style={({ pressed }) => [styles.locationBtn, { bottom: insets.bottom + (selectedPlace || routeMode ? 190 : 40) }, pressed && { opacity: 0.8 }]}
        onPress={goToMyLocation}>
        <Text style={styles.locationBtnText}>◎</Text>
      </Pressable>

      {/* Route planning bar */}
      {routeMode && (
        <View style={[styles.bottomCard, { paddingBottom: insets.bottom + 12, backgroundColor: dark ? '#1A2744' : '#fff' }]}>
          {plannedStops.length === 0 ? (
            <ThemedText style={styles.routeHint}>{t('map.route.hint')}</ThemedText>
          ) : (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.stopsRow}>
              {plannedStops.map((stop, index) => (
                <View key={stop.id} style={styles.stopChip}>
                  <Text style={styles.stopChipIndex}>{index + 1}</Text>
                  <Text numberOfLines={1} style={styles.stopChipText}>{stop.name}</Text>
                  {!activeTripId && (
                    <Pressable onPress={() => toggleStop(stop)} hitSlop={8}>
                      <Text style={styles.stopChipRemove}>×</Text>
                    </Pressable>
                  )}
                </View>
              ))}
            </ScrollView>
          )}

          {routeError && <ThemedText style={styles.routeErrorText}>{routeError}</ThemedText>}

          {activeTripId ? (
            <Pressable style={styles.routeActionBtn} onPress={handleEndRoute}>
              <Text style={styles.routeActionBtnText}>{t('map.route.end')}</Text>
            </Pressable>
          ) : (
            plannedStops.length >= 2 && (
              <Pressable
                style={[styles.routeActionBtn, isFetchingRoute && { opacity: 0.6 }]}
                onPress={handleStartRoute}
                disabled={isFetchingRoute}>
                {isFetchingRoute ? (
                  <ActivityIndicator color="#fff" size="small" />
                ) : (
                  <Text style={styles.routeActionBtnText}>{t('map.route.start')}</Text>
                )}
              </Pressable>
            )
          )}
        </View>
      )}

      {/* Selected place card */}
      {!routeMode && selectedPlace && (
        <View style={[styles.bottomCard, { paddingBottom: insets.bottom + 12, backgroundColor: dark ? '#1A2744' : '#fff' }]}>
          <Pressable
            style={({ pressed }) => [styles.bottomCardInner, pressed && { opacity: 0.92 }]}
            onPress={() => router.push(`/place/${selectedPlace.id}`)}>
            <PlaceImage place={selectedPlace} style={styles.bottomCardImage} />
            <View style={styles.bottomCardBody}>
              <ThemedText numberOfLines={1} style={styles.bottomCardName}>{selectedPlace.name}</ThemedText>
              <ThemedText numberOfLines={1} style={styles.bottomCardMeta}>
                {CATEGORY_EMOJI[selectedPlace.category] ?? '📍'} {formatCategory(selectedPlace.category, t)}
                {selectedPlace.tags[0] ? ` · ${selectedPlace.tags[0]}` : ''}
              </ThemedText>
              {selectedStatus && (
                <View style={[styles.bottomCardBadge, selectedOpen ? styles.badgeOpen : styles.badgeClosed]}>
                  <ThemedText style={[styles.bottomCardBadgeText, selectedOpen ? styles.badgeTextOpen : styles.badgeTextClosed]}>
                    {selectedStatus.shortLabel}
                  </ThemedText>
                </View>
              )}
            </View>
            <View style={styles.bottomCardChev}>
              <ThemedText style={styles.bottomCardChevText}>›</ThemedText>
            </View>
          </Pressable>
          <Pressable
            style={styles.dismissBtn}
            onPress={() => setSelectedPlace(null)}>
            <Text style={styles.dismissBtnText}>×</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  map: { flex: 1 },
  fullCenter: {
    flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12,
  },
  loadingText: { opacity: 0.6 },
  errorText: { color: '#B42318', textAlign: 'center', paddingHorizontal: 32 },

  // Pin
  pin: {
    width: 24, height: 24, borderRadius: 12,
    backgroundColor: NAVY,
    borderWidth: 2.5, borderColor: '#fff',
    alignItems: 'center', justifyContent: 'center',
    shadowColor: '#000', shadowOpacity: 0.25, shadowRadius: 4,
    shadowOffset: { width: 0, height: 2 }, elevation: 4,
  },
  pinSelected: {
    width: 32, height: 32, borderRadius: 16,
    backgroundColor: GOLD, borderColor: '#fff', borderWidth: 3,
    shadowOpacity: 0.35, shadowRadius: 6,
  },
  pinDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: GOLD },
  pinDotSelected: { backgroundColor: NAVY },

  // Top overlay
  topOverlay: {
    position: 'absolute', top: 0, left: 0, right: 0,
    alignItems: 'center',
    pointerEvents: 'box-none',
  } as any,
  countPill: {
    backgroundColor: NAVY,
    paddingHorizontal: 16, paddingVertical: 8,
    borderRadius: 50,
    shadowColor: '#000', shadowOpacity: 0.15, shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 }, elevation: 4,
  },
  countPillText: { color: '#fff', fontWeight: '600', fontSize: 14 },
  categoryRow: { paddingHorizontal: 16, paddingVertical: 8, gap: 8 },
  categoryChip: {
    paddingHorizontal: 14, paddingVertical: 7, borderRadius: 50,
    backgroundColor: 'rgba(255,255,255,0.92)',
    borderWidth: 1, borderColor: 'rgba(0,0,0,0.1)',
    shadowColor: '#000', shadowOpacity: 0.08, shadowRadius: 4,
    shadowOffset: { width: 0, height: 2 }, elevation: 2,
  },
  categoryChipActive: { backgroundColor: NAVY, borderColor: NAVY },
  categoryChipText: { fontSize: 13, fontWeight: '600', color: '#333' },
  categoryChipTextActive: { color: '#fff' },

  // Location button
  locationBtn: {
    position: 'absolute', right: 16,
    width: 48, height: 48, borderRadius: 24,
    backgroundColor: '#fff',
    alignItems: 'center', justifyContent: 'center',
    shadowColor: '#000', shadowOpacity: 0.15, shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 }, elevation: 4,
  },
  locationBtnText: { fontSize: 22, color: NAVY },

  // Bottom card
  bottomCard: {
    position: 'absolute', bottom: 0, left: 0, right: 0,
    backgroundColor: '#fff',
    borderTopLeftRadius: 24, borderTopRightRadius: 24,
    paddingHorizontal: 16, paddingTop: 16,
    shadowColor: '#000', shadowOpacity: 0.15, shadowRadius: 20,
    shadowOffset: { width: 0, height: -4 }, elevation: 10,
  },
  bottomCardInner: {
    flexDirection: 'row', alignItems: 'center',
    gap: 14,
  },
  bottomCardImage: { width: 72, height: 72, borderRadius: 12 },
  bottomCardBody: { flex: 1, gap: 5 },
  bottomCardName: { fontSize: 17, fontWeight: '700' },
  bottomCardMeta: { fontSize: 13, opacity: 0.55 },
  bottomCardBadge: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8, paddingVertical: 3,
    borderRadius: 50, borderWidth: 1,
  },
  badgeOpen: {
    backgroundColor: 'rgba(18,183,106,0.08)',
    borderColor: 'rgba(18,183,106,0.2)',
  },
  badgeClosed: {
    backgroundColor: 'rgba(217,45,32,0.06)',
    borderColor: 'rgba(217,45,32,0.15)',
  },
  bottomCardBadgeText: { fontSize: 11, fontWeight: '700' },
  badgeTextOpen: { color: '#067647' },
  badgeTextClosed: { color: '#B42318' },
  bottomCardChev: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: NAVY,
    alignItems: 'center', justifyContent: 'center',
  },
  bottomCardChevText: { color: '#fff', fontSize: 20, fontWeight: '300' },
  dismissBtn: {
    position: 'absolute', top: 12, right: 16,
    width: 28, height: 28, borderRadius: 14,
    backgroundColor: 'rgba(0,0,0,0.08)',
    alignItems: 'center', justifyContent: 'center',
  },
  dismissBtnText: { fontSize: 18, color: '#666', lineHeight: 22 },

  // Route planning
  stopPin: {
    minWidth: 26, height: 26, borderRadius: 13, paddingHorizontal: 6,
    backgroundColor: GOLD,
    borderWidth: 2.5, borderColor: '#fff',
    alignItems: 'center', justifyContent: 'center',
    shadowColor: '#000', shadowOpacity: 0.3, shadowRadius: 4,
    shadowOffset: { width: 0, height: 2 }, elevation: 4,
  },
  stopPinText: { color: NAVY, fontWeight: '800', fontSize: 13 },
  routeToggleBtn: { right: 16 },
  routeToggleBtnActive: { backgroundColor: GOLD },
  routeToggleTextActive: { color: NAVY },
  routeHint: { fontSize: 14, opacity: 0.6, paddingVertical: 6 },
  stopsRow: { gap: 8, paddingVertical: 4 },
  stopChip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: 'rgba(212,168,67,0.12)',
    borderWidth: 1, borderColor: 'rgba(212,168,67,0.35)',
    borderRadius: 50,
    paddingHorizontal: 12, paddingVertical: 7,
    maxWidth: 160,
  },
  stopChipIndex: { fontSize: 12, fontWeight: '800', color: GOLD },
  stopChipText: { fontSize: 13, fontWeight: '600', flexShrink: 1 },
  stopChipRemove: { fontSize: 16, color: '#999', paddingHorizontal: 2 },
  routeErrorText: { color: '#B42318', fontSize: 13, paddingTop: 8 },
  routeActionBtn: {
    marginTop: 12,
    backgroundColor: NAVY,
    borderRadius: 14,
    paddingVertical: 14,
    alignItems: 'center', justifyContent: 'center',
  },
  routeActionBtnText: { color: '#fff', fontSize: 15, fontWeight: '700' },
});
