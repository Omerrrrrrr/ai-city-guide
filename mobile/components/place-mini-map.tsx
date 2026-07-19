import React from 'react';
import MapView, { Marker, type Region } from 'react-native-maps';
import { Platform, Pressable, StyleSheet, View, type ViewStyle, type StyleProp } from 'react-native';
import { useTranslation } from 'react-i18next';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import type { Place } from '@/src/data/places';

type PlaceMiniMapProps = {
  place: Pick<Place, 'name' | 'location'>;
  relatedPlaces?: Pick<Place, 'name' | 'location'>[];
  badgeLabel?: string;
  interactive?: boolean;
  onInteractionChange?: (isInteracting: boolean) => void;
  style?: StyleProp<ViewStyle>;
};

const DEFAULT_LATITUDE_DELTA = 0.012;
const DEFAULT_LONGITUDE_DELTA = 0.012;
const MIN_LATITUDE_DELTA = 0.002;
const MIN_LONGITUDE_DELTA = 0.002;
const MAX_LATITUDE_DELTA = 0.08;
const MAX_LONGITUDE_DELTA = 0.08;
const ZOOM_IN_FACTOR = 0.6;
const ZOOM_OUT_FACTOR = 1.6;

function getRegion(
  place: Pick<Place, 'name' | 'location'>,
  relatedPlaces: Pick<Place, 'name' | 'location'>[]
): Region | null {
  if (!place.location) {
    return null;
  }

  const coordinates = [place, ...relatedPlaces]
    .map((entry) => entry.location)
    .filter((location): location is NonNullable<Place['location']> => Boolean(location));

  const latitudes = coordinates.map((location) => location.lat);
  const longitudes = coordinates.map((location) => location.lng);
  const minLat = Math.min(...latitudes);
  const maxLat = Math.max(...latitudes);
  const minLng = Math.min(...longitudes);
  const maxLng = Math.max(...longitudes);

  return {
    latitude: (minLat + maxLat) / 2,
    longitude: (minLng + maxLng) / 2,
    latitudeDelta: Math.max((maxLat - minLat) * 1.8, DEFAULT_LATITUDE_DELTA),
    longitudeDelta: Math.max((maxLng - minLng) * 1.8, DEFAULT_LONGITUDE_DELTA),
  };
}

function clampRegion(region: Region): Region {
  return {
    ...region,
    latitudeDelta: Math.min(Math.max(region.latitudeDelta, MIN_LATITUDE_DELTA), MAX_LATITUDE_DELTA),
    longitudeDelta: Math.min(
      Math.max(region.longitudeDelta, MIN_LONGITUDE_DELTA),
      MAX_LONGITUDE_DELTA
    ),
  };
}

export const PlaceMiniMap = React.memo(function PlaceMiniMap({
  place,
  relatedPlaces = [],
  badgeLabel,
  interactive = false,
  onInteractionChange,
  style,
}: PlaceMiniMapProps) {
  const { t } = useTranslation();
  const resolvedBadgeLabel = badgeLabel ?? t('components.placeMiniMap.badgeLabel');
  const regionKey = `${place.location?.lat ?? 'missing'}:${place.location?.lng ?? 'missing'}:${relatedPlaces
    .map((relatedPlace) =>
      relatedPlace.location
        ? `${relatedPlace.location.lat}:${relatedPlace.location.lng}`
        : relatedPlace.name
    )
    .join('|')}`;
  const mapRef = React.useRef<MapView | null>(null);
  const nextRegionRef = React.useRef<Region | null>(getRegion(place, relatedPlaces));
  nextRegionRef.current = getRegion(place, relatedPlaces);
  const [region, setRegion] = React.useState<Region | null>(nextRegionRef.current);

  React.useEffect(() => {
    setRegion(nextRegionRef.current);
    if (interactive && mapRef.current && nextRegionRef.current) {
      mapRef.current.animateToRegion(nextRegionRef.current, 0);
    }
  }, [interactive, regionKey]);

  if (!place.location) {
    return (
      <ThemedView
        lightColor="#EEF2F6"
        darkColor="#1E1E1E"
        style={[styles.fallback, style]}>
        <ThemedText style={styles.fallbackText}>{t('components.placeMiniMap.unavailable')}</ThemedText>
      </ThemedView>
    );
  }

  function handleZoom(factor: number) {
    if (!region) return;

    onInteractionChange?.(true);
    const nextRegion = clampRegion({
      ...region,
      latitudeDelta: region.latitudeDelta * factor,
      longitudeDelta: region.longitudeDelta * factor,
    });

    setRegion(nextRegion);
    mapRef.current?.animateToRegion(nextRegion, 180);
  }

  return (
    <View collapsable={false} style={[styles.container, style]}>
      <MapView
        ref={mapRef}
        style={styles.map}
        liteMode={Platform.OS === 'android' && !interactive}
        cacheEnabled={!interactive}
        loadingEnabled
        initialRegion={nextRegionRef.current ?? undefined}
        onTouchStart={interactive ? () => onInteractionChange?.(true) : undefined}
        onTouchEnd={interactive ? () => onInteractionChange?.(false) : undefined}
        onResponderRelease={interactive ? () => onInteractionChange?.(false) : undefined}
        onRegionChangeComplete={
          interactive
            ? (nextRegion) => {
                setRegion(nextRegion);
                onInteractionChange?.(false);
              }
            : undefined
        }
        scrollEnabled={interactive}
        zoomEnabled={interactive}
        zoomTapEnabled={interactive}
        rotateEnabled={false}
        pitchEnabled={false}
        showsCompass={interactive}
        toolbarEnabled={false}>
        <Marker
          coordinate={{
            latitude: place.location.lat,
            longitude: place.location.lng,
          }}
          title={place.name}
        />
        {relatedPlaces.map((relatedPlace) =>
          relatedPlace.location ? (
            <Marker
              key={`${relatedPlace.name}-${relatedPlace.location.lat}-${relatedPlace.location.lng}`}
              coordinate={{
                latitude: relatedPlace.location.lat,
                longitude: relatedPlace.location.lng,
              }}
              pinColor="#0A84FF"
              title={relatedPlace.name}
            />
          ) : null
        )}
      </MapView>

      <View style={styles.badge}>
        <ThemedText style={styles.badgeText}>{resolvedBadgeLabel}</ThemedText>
      </View>

      {interactive ? (
        <View style={styles.zoomControls}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={t('components.placeMiniMap.zoomIn')}
            onPress={() => {
              handleZoom(ZOOM_IN_FACTOR);
              onInteractionChange?.(false);
            }}
            style={({ pressed }) => [styles.zoomButton, pressed && styles.zoomButtonPressed]}>
            <ThemedText style={styles.zoomButtonText}>+</ThemedText>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={t('components.placeMiniMap.zoomOut')}
            onPress={() => {
              handleZoom(ZOOM_OUT_FACTOR);
              onInteractionChange?.(false);
            }}
            style={({ pressed }) => [styles.zoomButton, pressed && styles.zoomButtonPressed]}>
            <ThemedText style={styles.zoomButtonText}>-</ThemedText>
          </Pressable>
        </View>
      ) : null}
    </View>
  );
});

const styles = StyleSheet.create({
  container: {
    position: 'relative',
    minHeight: 104,
    overflow: 'hidden',
    borderTopWidth: 1,
    borderTopColor: 'rgba(127,127,127,0.16)',
    backgroundColor: 'rgba(127,127,127,0.08)',
  },
  map: {
    width: '100%',
    height: '100%',
  },
  fallback: {
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 104,
    borderTopWidth: 1,
    borderTopColor: 'rgba(127,127,127,0.16)',
  },
  fallbackText: {
    fontSize: 13,
    lineHeight: 18,
    opacity: 0.72,
  },
  badge: {
    position: 'absolute',
    left: 10,
    bottom: 10,
    paddingHorizontal: 8,
    paddingVertical: 5,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.9)',
  },
  badgeText: {
    fontSize: 11,
    lineHeight: 14,
    fontWeight: '700',
  },
  zoomControls: {
    position: 'absolute',
    top: 10,
    right: 10,
    gap: 8,
  },
  zoomButton: {
    width: 36,
    height: 36,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.94)',
    borderWidth: 1,
    borderColor: 'rgba(15,23,42,0.12)',
  },
  zoomButtonPressed: {
    opacity: 0.7,
  },
  zoomButtonText: {
    fontSize: 22,
    lineHeight: 24,
    fontWeight: '700',
  },
});
