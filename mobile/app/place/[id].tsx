import React from 'react';
import { Link, Stack, useLocalSearchParams } from 'expo-router';
import { Linking, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Image } from 'expo-image';

import { ExternalLink } from '@/components/external-link';
import { PlaceImage } from '@/components/place-image';
import { PlaceMiniMap } from '@/components/place-mini-map';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { usePlace, useNearbyPlaces } from '@/src/hooks/use-places';
import { useSavedPlaces } from '@/src/store/saved-places';
import type { PlaceGalleryImage } from '@/src/data/places';
import { getPlaceOpenStatus, getWeeklyHoursSchedule } from '@/src/utils/place-hours';

function getDirectionsUrl(place: {
  location?: { lat: number; lng: number };
  verifiedFacts?: { address?: string };
}) {
  if (place.location) {
    return `https://www.google.com/maps/search/?api=1&query=${place.location.lat},${place.location.lng}`;
  }

  if (place.verifiedFacts?.address) {
    return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
      place.verifiedFacts.address
    )}`;
  }

  return null;
}

function getWalkMinutes(distanceKm: number) {
  return Math.max(1, Math.round((distanceKm / 4.8) * 60));
}

type DetailPhoto = {
  id: string;
  imageUrl: string;
  sourceUrl?: string;
  sourceName?: string;
  license?: string;
  attribution?: string;
  verified: boolean;
  type: string;
  status: 'primary' | PlaceGalleryImage['status'];
  confidence?: number;
  pageTitle?: string;
  notes?: string;
};

function canDisplayPhoto(photo: DetailPhoto) {
  return photo.status !== 'primary' || photo.verified;
}

function getPhotoStatusLabel(photo: DetailPhoto) {
  if (photo.status === 'primary') {
    return photo.verified ? 'Verified main photo' : 'Photo unavailable';
  }

  if (photo.verified || photo.status === 'applied') {
    return 'Verified gallery photo';
  }

  if (photo.status === 'approved') {
    return 'Approved candidate';
  }

  return 'Review candidate';
}

export default function PlaceDetailScreen() {
  const { id } = useLocalSearchParams<{ id?: string }>();

  const { data: place, error, isLoading, refresh } = usePlace(id);
  const { data: nearbyPlaces } = useNearbyPlaces(id);
  const { isFavorite, toggleFavorite, isInPlan, togglePlan } = useSavedPlaces();
  const [isMapInteracting, setIsMapInteracting] = React.useState(false);
  const [selectedPhotoId, setSelectedPhotoId] = React.useState<string | null>(null);

  const photoGallery = React.useMemo<DetailPhoto[]>(() => {
    if (!place) return [];

    const primaryPhoto: DetailPhoto = {
      id: `primary:${place.id}`,
      imageUrl: place.imageUrl,
      sourceUrl: place.image.sourceUrl,
      sourceName: place.image.sourceName,
      license: place.image.license,
      attribution: place.image.attribution,
      verified: place.image.verified,
      type: place.image.type,
      status: 'primary',
    };

    return [primaryPhoto, ...(place.gallery ?? [])];
  }, [place]);

  React.useEffect(() => {
    const defaultPhoto =
      photoGallery.find((photo) => photo.status === 'primary' && photo.verified) ??
      photoGallery.find((photo) => photo.status !== 'primary') ??
      photoGallery[0];

    setSelectedPhotoId(defaultPhoto?.id ?? null);
  }, [photoGallery]);

  if (isLoading) {
    return (
      <ThemedView style={styles.centered}>
        <Stack.Screen options={{ title: 'Place' }} />
        <ThemedText type="subtitle">Loading place…</ThemedText>
      </ThemedView>
    );
  }

  if (error) {
    return (
      <ThemedView style={styles.centered}>
        <Stack.Screen options={{ title: 'Place' }} />
        <ThemedText type="subtitle">Could not load place</ThemedText>
        <ThemedText style={styles.body}>{error}</ThemedText>
        <Pressable onPress={refresh} style={({ pressed }) => [styles.actionButton, pressed && styles.actionButtonPressed]}>
          <ThemedText style={styles.actionButtonText}>Retry</ThemedText>
        </Pressable>
      </ThemedView>
    );
  }

  if (!place) {
    return (
      <ThemedView style={styles.centered}>
        <Stack.Screen options={{ title: 'Place' }} />
        <ThemedText type="subtitle">Place not found</ThemedText>
      </ThemedView>
    );
  }

  const directionsUrl = getDirectionsUrl(place);
  const mapNearbyPlaces = nearbyPlaces?.filter((nearby) => nearby.location).slice(0, 3) ?? [];
  const openStatus = getPlaceOpenStatus(place);
  const weeklyHours = getWeeklyHoursSchedule(place);
  const selectedPhoto = photoGallery.find((photo) => photo.id === selectedPhotoId) ?? photoGallery[0];

  return (
    <>
      <Stack.Screen options={{ title: place.name }} />
      <ScrollView contentContainerStyle={styles.container} scrollEnabled={!isMapInteracting}>
        {selectedPhoto && canDisplayPhoto(selectedPhoto) ? (
          <Image source={{ uri: selectedPhoto.imageUrl }} style={styles.image} contentFit="cover" />
        ) : (
          <PlaceImage place={place} style={styles.image} />
        )}

        <ThemedView style={styles.content}>
          <View style={styles.headerRow}>
            <ThemedText type="title" style={styles.title}>
              {place.name}
            </ThemedText>
            <View style={styles.actions}>
              <Pressable
                accessibilityRole="button"
                onPress={() => toggleFavorite(place.id)}
                style={({ pressed }) => [styles.actionButton, pressed && styles.actionButtonPressed]}>
                <ThemedText style={styles.actionButtonText}>
                  {isFavorite(place.id) ? 'Saved' : 'Save'}
                </ThemedText>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                onPress={() => togglePlan(place.id)}
                style={({ pressed }) => [styles.actionButton, pressed && styles.actionButtonPressed]}>
                <ThemedText style={styles.actionButtonText}>
                  {isInPlan(place.id) ? 'In plan' : 'Add to plan'}
                </ThemedText>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                disabled={!directionsUrl}
                onPress={() => {
                  if (!directionsUrl) return;
                  void Linking.openURL(directionsUrl);
                }}
                style={({ pressed }) => [
                  styles.actionButton,
                  !directionsUrl && styles.actionButtonDisabled,
                  pressed && directionsUrl && styles.actionButtonPressed,
                ]}>
                <ThemedText style={styles.actionButtonText}>Directions</ThemedText>
              </Pressable>
            </View>
          </View>

          <View style={styles.section}>
            <ThemedText type="subtitle">Description</ThemedText>
            <ThemedText style={styles.body}>{place.description}</ThemedText>
          </View>

          {place.wiki?.summary ? (
            <View style={styles.section}>
              <ThemedText type="subtitle">Wikipedia</ThemedText>
              <ThemedText style={styles.body}>{place.wiki.summary}</ThemedText>
              {place.wiki.pageUrl ? (
                <ExternalLink href={place.wiki.pageUrl}>
                  <ThemedText type="link">View on Wikipedia</ThemedText>
                </ExternalLink>
              ) : null}
            </View>
          ) : place.wiki?.status === 'not-found' ? (
            <View style={styles.section}>
              <ThemedText type="subtitle">Wikipedia</ThemedText>
              <ThemedText style={styles.body}>No enriched info yet.</ThemedText>
            </View>
          ) : null}

          <View style={styles.section}>
            <ThemedText type="subtitle">Photo</ThemedText>
            {selectedPhoto?.status === 'primary' && place.image.verified ? (
              <>
                <ThemedText style={styles.body}>Verified {place.image.type} photo</ThemedText>
                {place.image.sourceName ? (
                  <ThemedText style={styles.body}>Source: {place.image.sourceName}</ThemedText>
                ) : null}
                {place.image.license ? (
                  <ThemedText style={styles.body}>License: {place.image.license}</ThemedText>
                ) : null}
                {place.image.attribution ? (
                  <ThemedText style={styles.body}>{place.image.attribution}</ThemedText>
                ) : null}
              </>
            ) : selectedPhoto ? (
              <>
                <ThemedText style={styles.body}>
                  {getPhotoStatusLabel(selectedPhoto)} · {selectedPhoto.type}
                  {selectedPhoto.confidence != null ? ` · confidence ${selectedPhoto.confidence}` : ''}
                </ThemedText>
                {selectedPhoto.sourceName ? (
                  <ThemedText style={styles.body}>Source: {selectedPhoto.sourceName}</ThemedText>
                ) : null}
                {selectedPhoto.license ? (
                  <ThemedText style={styles.body}>License: {selectedPhoto.license}</ThemedText>
                ) : null}
                {selectedPhoto.attribution ? (
                  <ThemedText style={styles.body}>{selectedPhoto.attribution}</ThemedText>
                ) : null}
                {selectedPhoto.notes ? (
                  <ThemedText style={styles.helperText}>{selectedPhoto.notes}</ThemedText>
                ) : null}
                {selectedPhoto.pageTitle ? (
                  <ThemedText style={styles.helperText}>{selectedPhoto.pageTitle}</ThemedText>
                ) : null}
              </>
            ) : (
              <ThemedText style={styles.body}>
                Photo unavailable while we verify a real image source for this place.
              </ThemedText>
            )}
            {selectedPhoto?.sourceUrl ? (
              <ExternalLink href={selectedPhoto.sourceUrl}>
                <ThemedText type="link">Photo source</ThemedText>
              </ExternalLink>
            ) : null}
            {photoGallery.length > 1 ? (
              <View style={styles.photoGalleryBlock}>
                <ThemedText style={styles.helperText}>
                  More photos from the same place. Tap a thumbnail to switch the main image.
                </ThemedText>
                <ScrollView
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  contentContainerStyle={styles.photoGalleryScroller}>
                  {photoGallery.map((photo) => (
                    <Pressable
                      key={photo.id}
                      onPress={() => setSelectedPhotoId(photo.id)}
                      style={({ pressed }) => [
                        styles.photoThumbCard,
                        selectedPhoto?.id === photo.id && styles.photoThumbCardSelected,
                        pressed && styles.pressed,
                      ]}>
                      {canDisplayPhoto(photo) ? (
                        <Image source={{ uri: photo.imageUrl }} style={styles.photoThumb} contentFit="cover" />
                      ) : (
                        <PlaceImage
                          place={{
                            name: place.name,
                            imageUrl: place.imageUrl,
                            image: place.image,
                          }}
                          style={styles.photoThumb}
                          compact
                        />
                      )}
                      <View style={styles.photoThumbFooter}>
                        <ThemedText
                          numberOfLines={1}
                          style={[
                            styles.photoThumbLabel,
                            selectedPhoto?.id === photo.id && styles.photoThumbLabelSelected,
                          ]}>
                          {photo.status === 'primary' ? 'Main' : photo.verified ? 'Verified' : 'Candidate'}
                        </ThemedText>
                      </View>
                    </Pressable>
                  ))}
                </ScrollView>
              </View>
            ) : null}
          </View>

          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.tagsRow}>
            {place.tags.map((t) => (
              <Link key={t} href={{ pathname: '/explore', params: { tag: t } }} asChild>
                <Pressable style={({ pressed }) => [styles.tagChip, pressed && styles.pressed]}>
                  <ThemedText style={styles.tagText}>{t}</ThemedText>
                </Pressable>
              </Link>
            ))}
          </ScrollView>

          <View style={styles.section}>
            <ThemedText type="subtitle">Verified Facts</ThemedText>
            <ThemedText style={styles.body}>
              {place.verifiedFacts?.type}
              {place.verifiedFacts?.address ? ` · ${place.verifiedFacts.address}` : ''}
            </ThemedText>
            {place.verifiedFacts?.priceLevel ? (
              <ThemedText style={styles.body}>Price level: {place.verifiedFacts.priceLevel}</ThemedText>
            ) : null}
            {place.verifiedFacts?.sourceUrl ? (
              <ExternalLink href={place.verifiedFacts.sourceUrl as unknown as string}>
                <ThemedText type="link">Source</ThemedText>
              </ExternalLink>
            ) : null}
          </View>

          <View style={styles.section}>
            <ThemedText type="subtitle">Visit Info</ThemedText>
            <View
              style={[
                styles.statusBadge,
                openStatus.state === 'open' || openStatus.state === 'all-day'
                  ? styles.statusBadgeOpen
                  : styles.statusBadgeClosed,
              ]}>
              <ThemedText
                style={[
                  styles.statusBadgeText,
                  openStatus.state === 'open' || openStatus.state === 'all-day'
                    ? styles.statusBadgeTextOpen
                    : styles.statusBadgeTextClosed,
                ]}>
                {openStatus.shortLabel}
              </ThemedText>
            </View>
            <ThemedText style={styles.body}>{openStatus.detail}</ThemedText>
            {openStatus.note ? <ThemedText style={styles.helperText}>{openStatus.note}</ThemedText> : null}
            {place.visitInfo?.temporarilyClosed ? (
              <ThemedText style={styles.warningText}>
                This place is marked as temporarily closed right now.
              </ThemedText>
            ) : null}
            {place.visitInfo?.durationMinutes ? (
              <ThemedText style={styles.body}>
                Typical visit: about {place.visitInfo.durationMinutes} minutes
              </ThemedText>
            ) : null}
            {place.visitInfo?.bestTime ? (
              <ThemedText style={styles.body}>Best time: {place.visitInfo.bestTime}</ThemedText>
            ) : null}
            {place.visitInfo?.seasonality ? (
              <ThemedText style={styles.body}>Seasonality: {place.visitInfo.seasonality}</ThemedText>
            ) : null}
            {place.visitInfo?.hoursNote ? (
              <ThemedText style={styles.body}>Hours note: {place.visitInfo.hoursNote}</ThemedText>
            ) : null}

            <View style={styles.weeklyHoursBlock}>
              <View style={styles.weeklyHoursHeader}>
                <ThemedText style={styles.weeklyHoursTitle}>Week at a glance</ThemedText>
                <View
                  style={[
                    styles.weeklyHoursBadge,
                    weeklyHours.verified ? styles.weeklyHoursBadgeVerified : styles.weeklyHoursBadgeEstimated,
                  ]}>
                  <ThemedText
                    style={[
                      styles.weeklyHoursBadgeText,
                      weeklyHours.verified
                        ? styles.weeklyHoursBadgeTextVerified
                        : styles.weeklyHoursBadgeTextEstimated,
                    ]}>
                    {weeklyHours.verified ? 'Verified' : 'Estimated'}
                  </ThemedText>
                </View>
              </View>
              <View style={styles.weeklyHoursList}>
                {weeklyHours.rows.map((row) => (
                  <View
                    key={row.label}
                    style={[styles.weeklyHoursRow, row.isToday && styles.weeklyHoursRowToday]}>
                    <ThemedText
                      style={[styles.weeklyHoursDay, row.isToday && styles.weeklyHoursDayToday]}>
                      {row.label}
                    </ThemedText>
                    <ThemedText
                      style={[styles.weeklyHoursValue, row.isToday && styles.weeklyHoursValueToday]}>
                      {row.hoursText}
                    </ThemedText>
                  </View>
                ))}
              </View>
              <ThemedText style={styles.helperText}>{weeklyHours.note}</ThemedText>
            </View>
          </View>

          <View style={styles.section}>
            <ThemedText type="subtitle">Local Vibe</ThemedText>
            {place.localVibe?.mood ? (
              <ThemedText style={styles.body}>{place.localVibe.mood}</ThemedText>
            ) : null}
            {place.localVibe?.bestFor ? (
              <ThemedText style={styles.body}>Best for: {place.localVibe.bestFor}</ThemedText>
            ) : null}
          </View>

          <View style={styles.section}>
            <ThemedText type="subtitle">Short story</ThemedText>
            <ThemedText style={styles.body}>{place.shortStory}</ThemedText>
          </View>

          <View style={styles.section}>
            <ThemedText type="subtitle">Map</ThemedText>
            {place.verifiedFacts?.address ? (
              <ThemedText style={styles.body}>{place.verifiedFacts.address}</ThemedText>
            ) : (
              <ThemedText style={styles.body}>See where this place sits in Kristiansand.</ThemedText>
            )}
            {mapNearbyPlaces.length > 0 ? (
              <ThemedText style={styles.mapHintText}>
                Blue pins show the closest nearby places. Pinch or use + / - to zoom.
              </ThemedText>
            ) : null}
            <PlaceMiniMap
              place={place}
              relatedPlaces={mapNearbyPlaces}
              badgeLabel={mapNearbyPlaces.length > 0 ? 'Nearby on map' : 'Map preview'}
              interactive
              onInteractionChange={setIsMapInteracting}
              style={styles.detailMap}
            />
            {nearbyPlaces && nearbyPlaces.length > 0 ? (
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                contentContainerStyle={styles.nearbyScroller}>
                {nearbyPlaces.map((nearby) => {
                  const routeUrl = getDirectionsUrl(nearby);
                  const nearbyStatus = getPlaceOpenStatus(nearby);
                  return (
                    <View key={nearby.id} style={styles.nearbyCard}>
                      <Link href={{ pathname: '/place/[id]', params: { id: nearby.id } }} asChild>
                        <Pressable style={({ pressed }) => [styles.nearbyCardTap, pressed && styles.pressed]}>
                          <PlaceImage place={nearby} style={styles.nearbyThumb} compact />
                          <View style={styles.nearbyText}>
                            <ThemedText numberOfLines={2} style={styles.nearbyTitle}>
                              {nearby.name}
                            </ThemedText>
                            <ThemedText numberOfLines={1} style={styles.nearbyMeta}>
                              {getWalkMinutes(nearby.distanceKm)} min walk · {nearby.distanceKm.toFixed(1)} km
                            </ThemedText>
                            <ThemedText numberOfLines={1} style={styles.nearbyTag}>
                              {nearby.tags[0]}
                            </ThemedText>
                            <ThemedText
                              numberOfLines={1}
                              style={[
                                styles.nearbyStatus,
                                nearbyStatus.state === 'open' || nearbyStatus.state === 'all-day'
                                  ? styles.nearbyStatusOpen
                                  : styles.nearbyStatusClosed,
                              ]}>
                              {nearbyStatus.shortLabel}
                            </ThemedText>
                          </View>
                        </Pressable>
                      </Link>
                      <View style={styles.nearbyActions}>
                        <Pressable
                          accessibilityRole="button"
                          disabled={!routeUrl}
                          onPress={() => {
                            if (!routeUrl) return;
                            void Linking.openURL(routeUrl);
                          }}
                          style={({ pressed }) => [
                            styles.nearbyRouteButton,
                            !routeUrl && styles.nearbyRouteButtonDisabled,
                            pressed && routeUrl && styles.pressed,
                          ]}>
                          <ThemedText style={styles.nearbyRouteButtonText}>Route</ThemedText>
                        </Pressable>
                      </View>
                    </View>
                  );
                })}
              </ScrollView>
            ) : null}
          </View>
        </ThemedView>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingBottom: 32,
  },
  image: {
    width: '100%',
    height: 260,
  },
  content: {
    paddingHorizontal: 16,
    paddingTop: 16,
    gap: 16,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  title: {
    flex: 1,
  },
  actions: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: 8,
  },
  actionButton: {
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.35)',
  },
  actionButtonPressed: {
    opacity: 0.7,
  },
  actionButtonText: {
    fontSize: 14,
    lineHeight: 18,
  },
  actionButtonDisabled: {
    opacity: 0.45,
  },
  section: {
    gap: 8,
  },
  tagsRow: {
    paddingVertical: 2,
    gap: 8,
    paddingRight: 16,
  },
  tagChip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
  },
  tagText: {
    fontSize: 14,
    lineHeight: 18,
  },
  body: {
    fontSize: 16,
    lineHeight: 22,
  },
  helperText: {
    fontSize: 14,
    lineHeight: 19,
    opacity: 0.72,
  },
  warningText: {
    color: '#B42318',
    fontSize: 15,
    lineHeight: 21,
  },
  photoGalleryBlock: {
    gap: 10,
    marginTop: 4,
  },
  photoGalleryScroller: {
    gap: 10,
    paddingRight: 16,
  },
  photoThumbCard: {
    width: 122,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.18)',
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.72)',
  },
  photoThumbCardSelected: {
    borderColor: 'rgba(14, 36, 56, 0.3)',
  },
  photoThumb: {
    width: '100%',
    height: 86,
    backgroundColor: 'rgba(127,127,127,0.15)',
  },
  photoThumbFooter: {
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  photoThumbLabel: {
    fontSize: 12,
    lineHeight: 16,
    opacity: 0.82,
  },
  photoThumbLabelSelected: {
    fontWeight: '700',
    opacity: 1,
  },
  weeklyHoursBlock: {
    gap: 10,
    marginTop: 4,
  },
  weeklyHoursHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  weeklyHoursTitle: {
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '700',
  },
  weeklyHoursBadge: {
    paddingHorizontal: 9,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: 1,
  },
  weeklyHoursBadgeVerified: {
    backgroundColor: 'rgba(18, 183, 106, 0.1)',
    borderColor: 'rgba(18, 183, 106, 0.2)',
  },
  weeklyHoursBadgeEstimated: {
    backgroundColor: 'rgba(14, 36, 56, 0.06)',
    borderColor: 'rgba(14, 36, 56, 0.14)',
  },
  weeklyHoursBadgeText: {
    fontSize: 11,
    lineHeight: 14,
    fontWeight: '700',
  },
  weeklyHoursBadgeTextVerified: {
    color: '#067647',
  },
  weeklyHoursBadgeTextEstimated: {
    color: '#1D2939',
  },
  weeklyHoursList: {
    gap: 8,
  },
  weeklyHoursRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.16)',
    backgroundColor: 'rgba(127,127,127,0.03)',
  },
  weeklyHoursRowToday: {
    borderColor: 'rgba(14, 36, 56, 0.18)',
    backgroundColor: 'rgba(14, 36, 56, 0.06)',
  },
  weeklyHoursDay: {
    fontSize: 14,
    lineHeight: 18,
    opacity: 0.78,
  },
  weeklyHoursDayToday: {
    fontWeight: '700',
    opacity: 1,
  },
  weeklyHoursValue: {
    flex: 1,
    textAlign: 'right',
    fontSize: 14,
    lineHeight: 18,
    opacity: 0.9,
  },
  weeklyHoursValueToday: {
    fontWeight: '700',
  },
  statusBadge: {
    alignSelf: 'flex-start',
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 999,
    borderWidth: 1,
  },
  statusBadgeOpen: {
    backgroundColor: 'rgba(18, 183, 106, 0.1)',
    borderColor: 'rgba(18, 183, 106, 0.2)',
  },
  statusBadgeClosed: {
    backgroundColor: 'rgba(217, 45, 32, 0.08)',
    borderColor: 'rgba(217, 45, 32, 0.18)',
  },
  statusBadgeText: {
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '700',
  },
  statusBadgeTextOpen: {
    color: '#067647',
  },
  statusBadgeTextClosed: {
    color: '#B42318',
  },
  detailMap: {
    marginTop: 4,
    height: 180,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
  },
  mapHintText: {
    fontSize: 14,
    lineHeight: 19,
    opacity: 0.72,
  },
  nearbyScroller: {
    gap: 10,
    paddingRight: 16,
  },
  nearbyCard: {
    width: 180,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.72)',
  },
  nearbyCardTap: {
    backgroundColor: 'transparent',
  },
  nearbyThumb: {
    width: '100%',
    height: 88,
    backgroundColor: 'rgba(127,127,127,0.15)',
  },
  nearbyText: {
    gap: 4,
    padding: 10,
  },
  nearbyTitle: {
    fontSize: 15,
    fontWeight: 'bold',
  },
  nearbyMeta: {
    fontSize: 13,
    opacity: 0.7,
  },
  nearbyTag: {
    fontSize: 12,
    lineHeight: 16,
    opacity: 0.62,
  },
  nearbyStatus: {
    fontSize: 12,
    lineHeight: 16,
    fontWeight: '700',
  },
  nearbyStatusOpen: {
    color: '#067647',
  },
  nearbyStatusClosed: {
    color: '#B42318',
  },
  nearbyActions: {
    paddingHorizontal: 10,
    paddingBottom: 10,
  },
  nearbyRouteButton: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
    backgroundColor: 'rgba(14,36,56,0.04)',
  },
  nearbyRouteButtonDisabled: {
    opacity: 0.45,
  },
  nearbyRouteButtonText: {
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '700',
  },
  pressed: {
    opacity: 0.7,
  },
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
  },
});
