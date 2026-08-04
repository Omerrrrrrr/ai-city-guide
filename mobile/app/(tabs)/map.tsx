import React from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Linking,
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
import * as ImagePicker from 'expo-image-picker';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { PlaceImage } from '@/components/place-image';
import { ThemedText } from '@/components/themed-text';
import { CATEGORY_FILTERS } from '@/src/constants/category-filters';
import type { Place, PlaceCategory } from '@/src/data/places';
import { usePlaces } from '@/src/hooks/use-places';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';
import { getDirectionsUrl } from '@/src/utils/directions';
import { useCityStore } from '@/src/store/city';
import { CATEGORY_EMOJI, formatCategory } from '@/src/utils/categories';
import { fetchDirections } from '@/src/api/routes';
import { enrichLivePlace, fetchLiveNearbyPlaces, type LivePin } from '@/src/api/live-places';
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

// Only fetch live pins at city/district zoom or closer — matches Google
// Maps' own behavior of not flooding pins at country/world zoom, and keeps
// a single drag from fanning out into dozens of cold-cache Overture queries.
const LIVE_PINS_MAX_LATITUDE_DELTA = 0.3;
const LIVE_PINS_DEBOUNCE_MS = 400;

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

  // Live-explore: raw, un-enriched pins for anywhere the map is dragged to,
  // beyond the curated cities. See fetchLiveNearbyPlaces/enrichLivePlace.
  const [livePins, setLivePins] = React.useState<LivePin[]>([]);
  const [enrichingPinId, setEnrichingPinId] = React.useState<string | null>(null);
  const liveDebounceRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  // Route planning
  const { activeTripId, startTrip, endTrip, addBreadcrumb, addPhoto, updateTripStops, trips } = useTrips();
  const activeTrip = React.useMemo(() => trips.find((trip) => trip.id === activeTripId) ?? null, [trips, activeTripId]);
  const [routeMode, setRouteMode] = React.useState(false);
  const [plannedStops, setPlannedStops] = React.useState<Place[]>([]);
  const [routeGeometry, setRouteGeometry] = React.useState<[number, number][] | null>(null);
  const [isFetchingRoute, setIsFetchingRoute] = React.useState(false);
  const [routeError, setRouteError] = React.useState<string | null>(null);
  const hydratedTripIdRef = React.useRef<string | null>(null);

  // If this screen mounts (or remounts) while a trip is already active — e.g.
  // the user left the Map tab mid-trip and came back — rehydrate the local
  // editable stop list from the stored trip once, so editing continues from
  // where it left off instead of starting from an empty selection.
  React.useEffect(() => {
    if (!activeTrip || !places?.length) return;
    if (hydratedTripIdRef.current === activeTrip.id) return;
    hydratedTripIdRef.current = activeTrip.id;
    const resolved = activeTrip.placeIds
      .map((placeId) => places.find((p) => p.id === placeId))
      .filter((p): p is Place => Boolean(p));
    if (resolved.length) {
      setPlannedStops(resolved);
      setRouteGeometry(activeTrip.routeGeometry ?? null);
      setRouteMode(true);
    }
  }, [activeTrip, places]);

  const toggleRouteMode = () => {
    setSelectedPlace(null);
    // While a trip is live, the panel must stay reachable — it's the only
    // way to reach "Rotayı Bitir", and GPS recording keeps running
    // regardless of whether this panel is visible, so hiding it would leave
    // no way to stop tracking from the UI.
    if (activeTripId) { setRouteMode(true); return; }
    setRouteMode((prev) => !prev);
    setPlannedStops([]);
    setRouteGeometry(null);
    setRouteError(null);
  };

  const toggleStop = (place: Place) => {
    setPlannedStops((prev) =>
      prev.some((p) => p.id === place.id) ? prev.filter((p) => p.id !== place.id) : [...prev, place]
    );
  };

  const moveStop = (index: number, direction: -1 | 1) => {
    setPlannedStops((prev) => {
      const target = index + direction;
      if (target < 0 || target >= prev.length) return prev;
      const next = [...prev];
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  };

  const stopsChangedFromActiveTrip =
    !!activeTrip &&
    (plannedStops.length !== activeTrip.placeIds.length ||
      plannedStops.some((stop, index) => stop.id !== activeTrip.placeIds[index]));

  const handleStartRoute = async () => {
    if (plannedStops.length < 2) return;
    setIsFetchingRoute(true);
    setRouteError(null);
    try {
      const result = await fetchDirections(plannedStops.map((p) => ({ lat: p.location!.lat, lng: p.location!.lng })));
      setRouteGeometry(result.route);
      const id = startTrip(plannedStops.map((p) => p.id), {
        routeGeometry: result.route,
        distanceMeters: result.distanceMeters,
        durationSeconds: result.durationSeconds,
      });
      hydratedTripIdRef.current = id;
    } catch (err) {
      setRouteError(err instanceof Error ? err.message : t('map.route.failed'));
    } finally {
      setIsFetchingRoute(false);
    }
  };

  const handleUpdateRoute = async () => {
    if (!activeTripId || plannedStops.length < 2) return;
    setIsFetchingRoute(true);
    setRouteError(null);
    try {
      const result = await fetchDirections(plannedStops.map((p) => ({ lat: p.location!.lat, lng: p.location!.lng })));
      setRouteGeometry(result.route);
      updateTripStops(activeTripId, plannedStops.map((p) => p.id), {
        routeGeometry: result.route,
        distanceMeters: result.distanceMeters,
        durationSeconds: result.durationSeconds,
      });
    } catch (err) {
      setRouteError(err instanceof Error ? err.message : t('map.route.failed'));
    } finally {
      setIsFetchingRoute(false);
    }
  };

  const handleEndRoute = () => {
    if (activeTripId) endTrip(activeTripId);
    hydratedTripIdRef.current = null;
    setRouteMode(false);
    setPlannedStops([]);
    setRouteGeometry(null);
  };

  // Photos stay on-device only — no upload/storage backend exists (or is
  // planned) for this feature, expo already persists the picked/captured
  // file locally, so we just keep a reference to its uri.
  const attachTripPhoto = async (fromCamera: boolean) => {
    if (!activeTripId) return;
    const picker = fromCamera ? ImagePicker.launchCameraAsync : ImagePicker.launchImageLibraryAsync;
    const result = await picker({ mediaTypes: ['images'], quality: 0.7 });
    if (result.canceled || !result.assets[0]) return;

    let lat: number | undefined;
    let lng: number | undefined;
    try {
      const { status } = await Location.getForegroundPermissionsAsync();
      if (status === 'granted') {
        const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
        lat = loc.coords.latitude;
        lng = loc.coords.longitude;
      }
    } catch { /* photo is still saved without coordinates */ }

    addPhoto(activeTripId, { uri: result.assets[0].uri, timestamp: Date.now(), lat, lng });
  };

  const handleAddPhoto = () => {
    Alert.alert(t('map.route.addPhoto'), undefined, [
      { text: t('map.route.photoCamera'), onPress: () => void attachTripPhoto(true) },
      { text: t('map.route.photoGallery'), onPress: () => void attachTripPhoto(false) },
      { text: t('common.cancel'), style: 'cancel' },
    ]);
  };

  // Live GPS breadcrumb recording — foreground only (tied to this screen
  // being mounted), while a trip is active. Records a point roughly every
  // 20s or 25m of movement, whichever comes first, so a trip's breadcrumb
  // trail can be replayed later (see the trip history/playback screen).
  React.useEffect(() => {
    if (!activeTripId) return;
    let cancelled = false;
    let subscription: Location.LocationSubscription | null = null;

    void (async () => {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted' || cancelled) return;
      const sub = await Location.watchPositionAsync(
        { accuracy: Location.Accuracy.Balanced, timeInterval: 20000, distanceInterval: 25 },
        (loc) => {
          addBreadcrumb(activeTripId, {
            lat: loc.coords.latitude,
            lng: loc.coords.longitude,
            timestamp: loc.timestamp,
          });
        }
      );
      if (cancelled) { sub.remove(); return; }
      subscription = sub;
    })();

    return () => {
      cancelled = true;
      subscription?.remove();
    };
  }, [activeTripId, addBreadcrumb]);

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

  const fetchLivePinsForRegion = React.useCallback((r: Region) => {
    if (r.latitudeDelta > LIVE_PINS_MAX_LATITUDE_DELTA) {
      setLivePins([]);
      return;
    }
    fetchLiveNearbyPlaces({
      minLat: r.latitude - r.latitudeDelta / 2,
      maxLat: r.latitude + r.latitudeDelta / 2,
      minLng: r.longitude - r.longitudeDelta / 2,
      maxLng: r.longitude + r.longitudeDelta / 2,
    })
      .then(setLivePins)
      .catch(() => { /* live pins are a supplementary overlay — fail silently */ });
  }, []);

  const handleRegionChangeComplete = (r: Region) => {
    if (routeMode) return; // ambiguous to tap an un-enriched pin mid-route-building
    if (liveDebounceRef.current) clearTimeout(liveDebounceRef.current);
    liveDebounceRef.current = setTimeout(() => fetchLivePinsForRegion(r), LIVE_PINS_DEBOUNCE_MS);
  };

  // Fetch once for the initial resting region too — onRegionChangeComplete
  // only fires on user-driven drags, not on mount.
  React.useEffect(() => {
    if (!locationReady) return;
    fetchLivePinsForRegion(region);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [locationReady]);

  const handleLivePinPress = async (pin: LivePin) => {
    if (enrichingPinId) return;
    setEnrichingPinId(pin.id);
    try {
      const enriched = await enrichLivePlace(pin.id);
      setLivePins((prev) => prev.filter((p) => p.id !== pin.id));
      setSelectedPlace(enriched);
      if (enriched.location) {
        mapRef.current?.animateToRegion({
          latitude: enriched.location.lat - 0.005,
          longitude: enriched.location.lng,
          latitudeDelta: 0.025,
          longitudeDelta: 0.025,
        }, 400);
      }
    } catch (err) {
      Alert.alert(t('map.live.error'), err instanceof Error ? err.message : undefined);
    } finally {
      setEnrichingPinId(null);
    }
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
  const selectedDirectionsUrl = selectedPlace ? getDirectionsUrl(selectedPlace) : null;

  return (
    <View style={styles.container}>
      <MapView
        ref={mapRef}
        style={styles.map}
        initialRegion={region}
        showsUserLocation
        showsMyLocationButton={false}
        showsCompass={false}
        onPress={() => setSelectedPlace(null)}
        onRegionChangeComplete={handleRegionChangeComplete}>
        {!routeMode && livePins.map((pin) =>
          // Custom-View marker children force react-native-maps into
          // snapshot-based rendering, which is a well-known iOS crash risk
          // (especially in Simulator) when many markers render/re-render
          // during a drag — live-confirmed here (SIGABRT on every pan).
          // Only the single pin actively being enriched gets a custom
          // loading view; every idle pin uses a plain system pin instead.
          enrichingPinId === pin.id ? (
            <Marker
              key={`live-${pin.id}`}
              coordinate={{ latitude: pin.lat, longitude: pin.lng }}
              onPress={(e) => e.stopPropagation()}>
              <View style={styles.livePin}>
                <ActivityIndicator size="small" color={NAVY} />
              </View>
            </Marker>
          ) : (
            <Marker
              key={`live-${pin.id}`}
              coordinate={{ latitude: pin.lat, longitude: pin.lng }}
              pinColor="#8A8FA3"
              opacity={0.85}
              onPress={(e) => {
                e.stopPropagation();
                void handleLivePinPress(pin);
              }}
            />
          )
        )}
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
                  toggleStop(place);
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
        {activeTrip && activeTrip.breadcrumb.length > 1 && (
          <Polyline
            coordinates={activeTrip.breadcrumb.map((point) => ({ latitude: point.lat, longitude: point.lng }))}
            strokeColor={NAVY}
            strokeWidth={5}
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

      {/* My trips */}
      <Pressable
        style={({ pressed }) => [styles.tripsBtn, { top: insets.top + 10 }, pressed && { opacity: 0.8 }]}
        onPress={() => router.push('/trips')}>
        <Text style={styles.tripsBtnText}>🗂</Text>
      </Pressable>

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
                  <View style={styles.stopChipReorder}>
                    <Pressable onPress={() => moveStop(index, -1)} disabled={index === 0} hitSlop={4}>
                      <Text style={[styles.stopChipArrow, index === 0 && styles.stopChipArrowDisabled]}>▲</Text>
                    </Pressable>
                    <Pressable onPress={() => moveStop(index, 1)} disabled={index === plannedStops.length - 1} hitSlop={4}>
                      <Text style={[styles.stopChipArrow, index === plannedStops.length - 1 && styles.stopChipArrowDisabled]}>▼</Text>
                    </Pressable>
                  </View>
                  <Text style={styles.stopChipIndex}>{index + 1}</Text>
                  <Text numberOfLines={1} style={styles.stopChipText}>{stop.name}</Text>
                  <Pressable onPress={() => toggleStop(stop)} hitSlop={8}>
                    <Text style={styles.stopChipRemove}>×</Text>
                  </Pressable>
                </View>
              ))}
            </ScrollView>
          )}

          {routeError && <ThemedText style={styles.routeErrorText}>{routeError}</ThemedText>}

          {activeTrip && (
            <>
              <View style={styles.trackingRow}>
                <View style={styles.trackingDot} />
                <ThemedText style={styles.trackingText}>
                  {t('map.route.tracking', { count: activeTrip.breadcrumb.length })}
                </ThemedText>
              </View>

              <View style={styles.photoRow}>
                <Pressable style={styles.addPhotoBtn} onPress={handleAddPhoto}>
                  <Text style={styles.addPhotoBtnText}>📷 {t('map.route.addPhoto')}</Text>
                </Pressable>
                {activeTrip.photos.length > 0 && (
                  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.photoThumbRow}>
                    {activeTrip.photos.map((photo) => (
                      <Image key={photo.uri + photo.timestamp} source={{ uri: photo.uri }} style={styles.photoThumb} />
                    ))}
                  </ScrollView>
                )}
              </View>
            </>
          )}

          {activeTripId ? (
            <>
              {stopsChangedFromActiveTrip && plannedStops.length >= 2 && (
                <Pressable
                  style={[styles.routeActionBtn, styles.routeUpdateBtn, isFetchingRoute && { opacity: 0.6 }]}
                  onPress={handleUpdateRoute}
                  disabled={isFetchingRoute}>
                  {isFetchingRoute ? (
                    <ActivityIndicator color={NAVY} size="small" />
                  ) : (
                    <Text style={[styles.routeActionBtnText, styles.routeUpdateBtnText]}>{t('map.route.update')}</Text>
                  )}
                </Pressable>
              )}
              <Pressable style={styles.routeActionBtn} onPress={handleEndRoute}>
                <Text style={styles.routeActionBtnText}>{t('map.route.end')}</Text>
              </Pressable>
            </>
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
          {selectedDirectionsUrl && (
            <Pressable
              style={({ pressed }) => [styles.directionsRow, pressed && { opacity: 0.85 }]}
              onPress={() => Linking.openURL(selectedDirectionsUrl).catch(() => {})}>
              <Text style={styles.directionsRowText}>🧭 {t('placeDetail.actionBar.directions')}</Text>
            </Pressable>
          )}
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

  // Loading state for the single live pin currently being enriched — the
  // only live-pin case that still uses a custom marker view.
  livePin: {
    width: 16, height: 16, borderRadius: 8,
    backgroundColor: 'rgba(255,255,255,0.85)',
    borderWidth: 1.5, borderColor: NAVY,
    alignItems: 'center', justifyContent: 'center',
  },

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
  directionsRow: {
    marginTop: 10,
    borderRadius: 12,
    paddingVertical: 11,
    alignItems: 'center', justifyContent: 'center',
    backgroundColor: 'rgba(15,28,63,0.06)',
    borderWidth: 1, borderColor: 'rgba(15,28,63,0.15)',
  },
  directionsRowText: { fontSize: 14, fontWeight: '700', color: NAVY },
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
  tripsBtn: {
    position: 'absolute', right: 16,
    width: 44, height: 44, borderRadius: 22,
    backgroundColor: '#fff',
    alignItems: 'center', justifyContent: 'center',
    shadowColor: '#000', shadowOpacity: 0.15, shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 }, elevation: 4,
  },
  tripsBtnText: { fontSize: 18 },
  routeToggleBtnActive: { backgroundColor: GOLD },
  routeToggleTextActive: { color: NAVY },
  routeHint: { fontSize: 14, opacity: 0.6, paddingVertical: 6 },
  stopsRow: { gap: 8, paddingVertical: 4 },
  stopChip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: 'rgba(212,168,67,0.12)',
    borderWidth: 1, borderColor: 'rgba(212,168,67,0.35)',
    borderRadius: 50,
    paddingHorizontal: 10, paddingVertical: 6,
    maxWidth: 190,
  },
  stopChipReorder: { gap: 1 },
  stopChipArrow: { fontSize: 9, color: GOLD, lineHeight: 11 },
  stopChipArrowDisabled: { opacity: 0.25 },
  stopChipIndex: { fontSize: 12, fontWeight: '800', color: GOLD },
  stopChipText: { fontSize: 13, fontWeight: '600', flexShrink: 1 },
  stopChipRemove: { fontSize: 16, color: '#999', paddingHorizontal: 2 },
  routeErrorText: { color: '#B42318', fontSize: 13, paddingTop: 8 },
  trackingRow: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingTop: 10 },
  trackingDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#D9342A' },
  trackingText: { fontSize: 12.5, opacity: 0.6 },
  photoRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingTop: 10, flexWrap: 'wrap' },
  addPhotoBtn: {
    paddingHorizontal: 12, paddingVertical: 7, borderRadius: 50,
    backgroundColor: 'rgba(15,28,63,0.06)',
    borderWidth: 1, borderColor: 'rgba(15,28,63,0.15)',
  },
  addPhotoBtnText: { fontSize: 13, fontWeight: '600' },
  photoThumbRow: { gap: 6 },
  photoThumb: { width: 44, height: 44, borderRadius: 8 },
  routeActionBtn: {
    marginTop: 12,
    backgroundColor: NAVY,
    borderRadius: 14,
    paddingVertical: 14,
    alignItems: 'center', justifyContent: 'center',
  },
  routeActionBtnText: { color: '#fff', fontSize: 15, fontWeight: '700' },
  routeUpdateBtn: { backgroundColor: 'rgba(212,168,67,0.15)', borderWidth: 1, borderColor: GOLD, marginBottom: 0 },
  routeUpdateBtnText: { color: NAVY },
});
