import React from 'react';
import { Stack, Link, useLocalSearchParams, useRouter } from 'expo-router';
import {
  Linking,
  ScrollView,
  Share,
  StyleSheet,
  View,
  useColorScheme,
  type ViewStyle,
} from 'react-native';
import { Image } from 'expo-image';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import * as Haptics from 'expo-haptics';

import { AnimatedPressable } from '@/components/animated-pressable';
import { PlaceImage } from '@/components/place-image';
import { PlaceMiniMap } from '@/components/place-mini-map';
import { PlaceDetailSkeleton, SkeletonBox } from '@/components/skeleton';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { usePlace, useNearbyPlaces } from '@/src/hooks/use-places';
import { useSavedPlaces } from '@/src/store/saved-places';
import { useRecentlyViewed } from '@/src/store/recently-viewed';
import { explainPlace, type ExplainResult } from '@/src/api/places';
import { useUserProfile } from '@/src/store/user-profile';
import { getPlaceOpenStatus, getWeeklyHoursSchedule } from '@/src/utils/place-hours';
import { CATEGORY_EMOJI, formatCategory } from '@/src/utils/categories';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

function getDirectionsUrl(place: {
  location?: { lat: number; lng: number };
  verifiedFacts?: { address?: string };
}) {
  if (place.location) {
    return `https://www.google.com/maps/search/?api=1&query=${place.location.lat},${place.location.lng}`;
  }
  if (place.verifiedFacts?.address) {
    return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(place.verifiedFacts.address)}`;
  }
  return null;
}

function getWalkMinutes(distanceKm: number) {
  return Math.max(1, Math.round((distanceKm / 4.8) * 60));
}

export default function PlaceDetailScreen() {
  const { id } = useLocalSearchParams<{ id?: string }>();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const colorScheme = useColorScheme();
  const dark = colorScheme === 'dark';
  const { t } = useTranslation();

  const { data: place, error, isLoading, refresh } = usePlace(id);
  const { data: nearbyPlaces } = useNearbyPlaces(id);
  const { isFavorite, toggleFavorite, isInPlan, togglePlan } = useSavedPlaces();
  const { markViewed } = useRecentlyViewed();
  const { name: userName, profession, interests, faith } = useUserProfile();
  const [isMapInteracting, setIsMapInteracting] = React.useState(false);
  const [piriseTake, setPirisTake] = React.useState<ExplainResult | null>(null);
  const [pirisLoading, setPirisLoading] = React.useState(false);

  React.useEffect(() => {
    if (id) markViewed(id);
  }, [id]);

  React.useEffect(() => {
    if (!id || !place) return;
    let cancelled = false;
    setPirisLoading(true);
    explainPlace(id, { name: userName, profession, interests, faith })
      .then((result) => { if (!cancelled) setPirisTake(result); })
      .catch(() => { /* silently fail — non-critical */ })
      .finally(() => { if (!cancelled) setPirisLoading(false); });
    return () => { cancelled = true; };
  }, [id, place?.id, profession, faith, interests?.join(',')]);


  const bg = dark ? '#0A0F1E' : '#F4F5F9';
  const cardBg = dark ? '#1A2744' : '#fff';

  // ── Loading ───────────────────────────────────────────────────────────────────
  if (isLoading) {
    return (
      <>
        <Stack.Screen options={{ headerShown: false }} />
        <PlaceDetailSkeleton insetTop={insets.top} />
      </>
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────────
  if (error || !place) {
    return (
      <View style={[styles.fullCenter, { backgroundColor: bg }]}>
        <Stack.Screen options={{ headerShown: false }} />
        <View style={[styles.floatingBack, { top: insets.top + 12 }]}>
          <AnimatedPressable onPress={() => router.back()} style={styles.backBtn}>
            <ThemedText style={styles.backBtnText}>←</ThemedText>
          </AnimatedPressable>
        </View>
        <ThemedText style={styles.errorTitle}>{t('placeDetail.errorTitle')}</ThemedText>
        {error ? <ThemedText style={styles.errorBody}>{error}</ThemedText> : null}
        <AnimatedPressable style={styles.retryBtn} onPress={refresh}>
          <ThemedText style={styles.retryBtnText} lightColor="#fff" darkColor="#fff">{t('common.tryAgain')}</ThemedText>
        </AnimatedPressable>
      </View>
    );
  }

  const directionsUrl = getDirectionsUrl(place);
  const openStatus = getPlaceOpenStatus(place, t);
  const weeklyHours = getWeeklyHoursSchedule(place, t);
  const isOpen = openStatus.state === 'open' || openStatus.state === 'all-day';
  const mapNearbyPlaces = nearbyPlaces?.filter((n) => n.location).slice(0, 5) ?? [];
  const saved = isFavorite(place.id);
  const inPlan = isInPlan(place.id);

  // Pick best photo
  const galleryPhotos = place.gallery ?? [];
  const verifiedGallery = galleryPhotos.filter((p) => p.verified || p.status === 'applied');
  const heroUrl = place.image.verified
    ? place.imageUrl
    : verifiedGallery[0]?.imageUrl ?? place.imageUrl;

  return (
    <>
      <Stack.Screen options={{ headerShown: false }} />
      <ScrollView
        style={{ flex: 1, backgroundColor: bg }}
        scrollEnabled={!isMapInteracting}
        showsVerticalScrollIndicator={false}>

        {/* ── Hero image ── */}
        <View style={styles.heroContainer}>
          <Image
            source={{ uri: heroUrl }}
            style={styles.heroImage}
            contentFit="cover"
            transition={300}
          />
          {/* Floating back + save buttons */}
          <View style={[styles.heroTopBar, { paddingTop: insets.top + 10 }]}>
            <AnimatedPressable
              onPress={() => router.back()}
              style={({ pressed }) => [styles.iconBtn, pressed && { opacity: 0.7 }]}>
              <ThemedText style={styles.iconBtnText} lightColor="#fff" darkColor="#fff">←</ThemedText>
            </AnimatedPressable>
            <View style={styles.heroTopRight}>
              <AnimatedPressable
                onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium); toggleFavorite(place.id); }}
                style={({ pressed }) => [styles.iconBtn, saved && styles.iconBtnActive, pressed && { opacity: 0.7 }]}>
                <ThemedText
                  style={styles.iconBtnText}
                  lightColor={saved ? NAVY : '#fff'}
                  darkColor={saved ? NAVY : '#fff'}>
                  {saved ? '♥' : '♡'}
                </ThemedText>
              </AnimatedPressable>
              <AnimatedPressable
                onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); togglePlan(place.id); }}
                style={({ pressed }) => [styles.iconBtn, inPlan && styles.iconBtnPlan, pressed && { opacity: 0.7 }]}>
                <ThemedText
                  style={styles.iconBtnText}
                  lightColor={inPlan ? NAVY : '#fff'}
                  darkColor={inPlan ? NAVY : '#fff'}>
                  {inPlan ? '✓' : '+'}
                </ThemedText>
              </AnimatedPressable>
            </View>
          </View>

          {/* Name overlay at bottom of image */}
          <View style={styles.heroBottom}>
            <View style={[styles.statusPill, isOpen ? styles.statusPillOpen : styles.statusPillClosed]}>
              <ThemedText
                style={[styles.statusPillText, isOpen ? styles.statusPillTextOpen : styles.statusPillTextClosed]}>
                {openStatus.shortLabel}
              </ThemedText>
            </View>
            <ThemedText style={styles.heroName} lightColor="#fff" darkColor="#fff">
              {place.name}
            </ThemedText>
            <ThemedText style={styles.heroCategory} lightColor="rgba(255,255,255,0.75)" darkColor="rgba(255,255,255,0.75)">
              {CATEGORY_EMOJI[place.category] ?? '📍'} {formatCategory(place.category, t)}
              {place.verifiedFacts?.address ? ` · ${place.verifiedFacts.address}` : ''}
            </ThemedText>
          </View>
        </View>

        {/* ── Action bar ── */}
        <ThemedView style={[styles.actionBar, { backgroundColor: cardBg }]}>
          <AnimatedPressable
            style={({ pressed }) => [styles.actionBarBtn, pressed && { opacity: 0.7 }]}
            onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium); toggleFavorite(place.id); }}>
            <ThemedText style={styles.actionBarIcon}>{saved ? '♥' : '♡'}</ThemedText>
            <ThemedText style={styles.actionBarLabel}>{saved ? t('placeDetail.actionBar.saved') : t('placeDetail.actionBar.save')}</ThemedText>
          </AnimatedPressable>
          <View style={styles.actionBarDivider} />
          <AnimatedPressable
            style={({ pressed }) => [styles.actionBarBtn, pressed && { opacity: 0.7 }]}
            onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); togglePlan(place.id); }}>
            <ThemedText style={styles.actionBarIcon}>{inPlan ? '✓' : '📋'}</ThemedText>
            <ThemedText style={styles.actionBarLabel}>{inPlan ? t('placeDetail.actionBar.inPlan') : t('placeDetail.actionBar.addToPlan')}</ThemedText>
          </AnimatedPressable>
          <View style={styles.actionBarDivider} />
          <AnimatedPressable
            style={({ pressed }) => [styles.actionBarBtn, !directionsUrl && { opacity: 0.4 }, pressed && { opacity: 0.7 }]}
            disabled={!directionsUrl}
            onPress={() => directionsUrl && Linking.openURL(directionsUrl).catch(() => {})}>
            <ThemedText style={styles.actionBarIcon}>↗</ThemedText>
            <ThemedText style={styles.actionBarLabel}>{t('placeDetail.actionBar.directions')}</ThemedText>
          </AnimatedPressable>
          <View style={styles.actionBarDivider} />
          <AnimatedPressable
            style={({ pressed }) => [styles.actionBarBtn, pressed && { opacity: 0.7 }]}
            onPress={() => {
              const wikiNote = place.wiki?.pageUrl ? t('placeDetail.shareLearnMore', { url: place.wiki.pageUrl }) : '';
              Share.share({
                title: place.name,
                message: t('placeDetail.shareMessage', {
                  name: place.name,
                  category: formatCategory(place.category, t),
                  city: place.city,
                  story: place.shortStory || place.description,
                  wikiNote,
                }),
              });
            }}>
            <ThemedText style={styles.actionBarIcon}>⬆</ThemedText>
            <ThemedText style={styles.actionBarLabel}>{t('common.share')}</ThemedText>
          </AnimatedPressable>
        </ThemedView>

        {/* ── Content ── */}
        <View style={styles.content}>

          {/* Piri's Take */}
          {(pirisLoading || piriseTake) && (
            <View style={styles.pirisCard}>
              <View style={styles.pirisHeader}>
                <View style={styles.pirisLogo}>
                  <ThemedText style={styles.pirisLogoText} lightColor={GOLD} darkColor={GOLD}>◈</ThemedText>
                </View>
                <ThemedText style={styles.pirisTitle} lightColor="#fff" darkColor="#fff">
                  {t('placeDetail.pirisTake')}
                </ThemedText>
              </View>

              {pirisLoading && (
                <View style={{ gap: 10, marginTop: 4 }}>
                  <SkeletonBox height={16} width="65%" borderRadius={6} />
                  <SkeletonBox height={13} width="100%" borderRadius={5} />
                  <SkeletonBox height={13} width="85%" borderRadius={5} />
                  <SkeletonBox height={13} width="90%" borderRadius={5} />
                  <View style={{ flexDirection: 'row', gap: 8, marginTop: 4 }}>
                    <SkeletonBox width={7} height={7} borderRadius={4} />
                    <SkeletonBox height={12} width="75%" borderRadius={5} />
                  </View>
                  <View style={{ flexDirection: 'row', gap: 8 }}>
                    <SkeletonBox width={7} height={7} borderRadius={4} />
                    <SkeletonBox height={12} width="60%" borderRadius={5} />
                  </View>
                </View>
              )}
              {piriseTake && !pirisLoading && (
                <>
                  <ThemedText style={styles.pirisHeadline} lightColor={GOLD} darkColor={GOLD}>
                    {piriseTake.headline}
                  </ThemedText>
                  <ThemedText style={styles.pirisBody} lightColor="rgba(255,255,255,0.85)" darkColor="rgba(255,255,255,0.85)">
                    {piriseTake.body}
                  </ThemedText>
                  {piriseTake.highlights.length > 0 && (
                    <View style={styles.pirisHighlights}>
                      {piriseTake.highlights.map((h, i) => (
                        <View key={i} style={styles.pirisHighlightRow}>
                          <View style={styles.pirisHighlightDot} />
                          <ThemedText style={styles.pirisHighlightText} lightColor="rgba(255,255,255,0.8)" darkColor="rgba(255,255,255,0.8)">
                            {h}
                          </ThemedText>
                        </View>
                      ))}
                    </View>
                  )}
                </>
              )}

            </View>
          )}

          {/* About */}
          <ThemedView style={[styles.card, { backgroundColor: cardBg }]}>
            <ThemedText style={styles.sectionLabel}>{t('placeDetail.about')}</ThemedText>
            <ThemedText style={styles.bodyText}>{place.description}</ThemedText>
            {place.shortStory && place.shortStory !== place.description && (
              <View style={styles.storyBlock}>
                <View style={styles.storyLine} />
                <ThemedText style={styles.storyText}>{place.shortStory}</ThemedText>
              </View>
            )}
            {place.wiki?.summary ? (
              <ThemedText style={[styles.bodyText, { marginTop: 10, opacity: 0.75, fontSize: 14 }]}>
                {place.wiki.summary}
              </ThemedText>
            ) : null}
          </ThemedView>

          {/* Tags */}
          {place.tags.length > 0 && (
            <View style={styles.tagsRow}>
              {place.tags.map((tag) => (
                <Link key={tag} href={{ pathname: '/explore', params: { tag } }} asChild>
                  <AnimatedPressable style={({ pressed }) => [styles.tagChip, pressed && { opacity: 0.7 }]}>
                    <ThemedText style={styles.tagText}>{tag}</ThemedText>
                  </AnimatedPressable>
                </Link>
              ))}
            </View>
          )}

          {/* Hours */}
          <ThemedView style={[styles.card, { backgroundColor: cardBg }]}>
            <View style={styles.cardHeaderRow}>
              <ThemedText style={styles.sectionLabel}>{t('placeDetail.hours')}</ThemedText>
              <View style={[styles.hoursBadge, weeklyHours.verified ? styles.hoursBadgeVerified : styles.hoursBadgeEst]}>
                <ThemedText style={[styles.hoursBadgeText, weeklyHours.verified ? styles.hoursBadgeTextVerified : styles.hoursBadgeTextEst]}>
                  {weeklyHours.verified ? t('placeDetail.verified') : t('placeDetail.estimated')}
                </ThemedText>
              </View>
            </View>

            <ThemedText style={styles.openDetail}>{openStatus.detail}</ThemedText>
            {openStatus.note ? <ThemedText style={styles.openNote}>{openStatus.note}</ThemedText> : null}

            {place.visitInfo?.temporarilyClosed && (
              <View style={styles.warningBlock}>
                <ThemedText style={styles.warningText}>{t('placeDetail.temporarilyClosed')}</ThemedText>
              </View>
            )}

            <View style={styles.hoursGrid}>
              {weeklyHours.rows.map((row) => (
                <View key={row.label} style={[styles.hoursRow, row.isToday && styles.hoursRowToday]}>
                  <ThemedText style={[styles.hoursDay, row.isToday && styles.hoursDayToday]}>
                    {row.label}
                  </ThemedText>
                  <ThemedText style={[styles.hoursValue, row.isToday && styles.hoursValueToday]}>
                    {row.hoursText}
                  </ThemedText>
                </View>
              ))}
            </View>

            {place.visitInfo?.durationMinutes ? (
              <ThemedText style={styles.visitHint}>
                {t('placeDetail.typicalVisit', { minutes: place.visitInfo.durationMinutes })}
              </ThemedText>
            ) : null}
            {place.visitInfo?.bestTime ? (
              <ThemedText style={styles.visitHint}>{t('placeDetail.bestTime', { time: place.visitInfo.bestTime })}</ThemedText>
            ) : null}
          </ThemedView>

          {/* Local vibe */}
          {(place.localVibe?.mood || place.localVibe?.bestFor) ? (
            <ThemedView style={[styles.card, { backgroundColor: cardBg }]}>
              <ThemedText style={styles.sectionLabel}>{t('placeDetail.vibe')}</ThemedText>
              {place.localVibe.mood ? (
                <ThemedText style={styles.bodyText}>{place.localVibe.mood}</ThemedText>
              ) : null}
              {place.localVibe.bestFor ? (
                <View style={styles.bestForRow}>
                  <ThemedText style={styles.bestForLabel}>{t('placeDetail.bestFor')}</ThemedText>
                  <ThemedText style={styles.bestForValue}>{place.localVibe.bestFor}</ThemedText>
                </View>
              ) : null}
            </ThemedView>
          ) : null}

          {/* Photo gallery (if multiple verified photos) */}
          {verifiedGallery.length > 1 && (
            <View>
              <ThemedText style={styles.sectionLabel}>{t('placeDetail.photos')}</ThemedText>
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                contentContainerStyle={styles.galleryRow}>
                {verifiedGallery.map((photo, i) => (
                  <Image
                    key={photo.id ?? i}
                    source={{ uri: photo.imageUrl }}
                    style={styles.galleryThumb}
                    contentFit="cover"
                  />
                ))}
              </ScrollView>
            </View>
          )}

          {/* Map + Nearby */}
          <ThemedView style={[styles.card, { backgroundColor: cardBg }]}>
            <ThemedText style={styles.sectionLabel}>{t('placeDetail.location')}</ThemedText>
            {place.verifiedFacts?.address ? (
              <ThemedText style={styles.addressText}>{place.verifiedFacts.address}</ThemedText>
            ) : null}
            <PlaceMiniMap
              place={place}
              relatedPlaces={mapNearbyPlaces}
              badgeLabel=""
              interactive
              onInteractionChange={setIsMapInteracting}
              style={styles.miniMap}
            />
            {directionsUrl ? (
              <AnimatedPressable
                style={({ pressed }) => [styles.directionsBtn, pressed && { opacity: 0.85 }]}
                onPress={() => Linking.openURL(directionsUrl!).catch(() => {})}>
                <ThemedText style={styles.directionsBtnText} lightColor="#fff" darkColor="#fff">
                  {t('common.openInMaps')}
                </ThemedText>
              </AnimatedPressable>
            ) : null}
          </ThemedView>

          {/* Nearby places */}
          {nearbyPlaces && nearbyPlaces.length > 0 && (
            <View>
              <ThemedText style={styles.sectionLabel}>{t('placeDetail.nearby')}</ThemedText>
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                contentContainerStyle={styles.nearbyRow}>
                {nearbyPlaces.map((nearby) => {
                  const ns = getPlaceOpenStatus(nearby, t);
                  const nOpen = ns.state === 'open' || ns.state === 'all-day';
                  return (
                    <Link key={nearby.id} href={{ pathname: '/place/[id]', params: { id: nearby.id } }} asChild>
                      <AnimatedPressable style={({ pressed }) => [styles.nearbyCard, { backgroundColor: cardBg }, pressed && { opacity: 0.75 }]}>
                        <PlaceImage place={nearby} style={styles.nearbyImage} compact />
                        <View style={styles.nearbyBody}>
                          <ThemedText numberOfLines={2} style={styles.nearbyName}>{nearby.name}</ThemedText>
                          <ThemedText style={styles.nearbyCategory}>
                            {CATEGORY_EMOJI[nearby.category] ?? '📍'} {formatCategory(nearby.category, t)}
                          </ThemedText>
                          <ThemedText style={[styles.nearbyStatus, nOpen ? styles.nearbyStatusOpen : styles.nearbyStatusClosed]}>
                            {ns.shortLabel}
                          </ThemedText>
                          <ThemedText style={styles.nearbyDist}>
                            {t('placeDetail.walkMin', { minutes: getWalkMinutes(nearby.distanceKm) })}
                          </ThemedText>
                        </View>
                      </AnimatedPressable>
                    </Link>
                  );
                })}
              </ScrollView>
            </View>
          )}

        </View>

        {/* Bottom safe area */}
        <View style={{ height: Math.max(insets.bottom, 24) }} />
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  fullCenter: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
    padding: 32,
  },
  errorTitle: { fontSize: 20, fontWeight: '700' },
  errorBody: { fontSize: 15, opacity: 0.6, textAlign: 'center', lineHeight: 22 },
  retryBtn: {
    backgroundColor: NAVY,
    paddingHorizontal: 28,
    paddingVertical: 14,
    borderRadius: 14,
  },
  retryBtnText: { fontSize: 16, fontWeight: '700' },
  floatingBack: { position: 'absolute', left: 20 },
  backBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.45)',
    alignItems: 'center', justifyContent: 'center',
  },
  backBtnText: { fontSize: 20, color: '#fff' },

  // Hero
  heroContainer: { position: 'relative' },
  heroImage: { width: '100%', height: 340 },
  heroTopBar: {
    position: 'absolute',
    top: 0, left: 0, right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
  },
  heroTopRight: {
    flexDirection: 'row',
    gap: 10,
  },
  iconBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.4)',
    alignItems: 'center', justifyContent: 'center',
  },
  iconBtnActive: { backgroundColor: GOLD },
  iconBtnPlan: { backgroundColor: GOLD },
  iconBtnText: { fontSize: 18, fontWeight: '600' },
  heroBottom: {
    position: 'absolute',
    bottom: 0, left: 0, right: 0,
    padding: 20,
    paddingBottom: 24,
    backgroundColor: 'rgba(0,0,0,0.48)',
    gap: 4,
  },
  statusPill: {
    alignSelf: 'flex-start',
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: 50,
    marginBottom: 4,
  },
  statusPillOpen: { backgroundColor: 'rgba(18,183,106,0.25)', borderWidth: 1, borderColor: 'rgba(18,183,106,0.5)' },
  statusPillClosed: { backgroundColor: 'rgba(217,45,32,0.2)', borderWidth: 1, borderColor: 'rgba(217,45,32,0.4)' },
  statusPillText: { fontSize: 11, fontWeight: '700' },
  statusPillTextOpen: { color: '#6EFAB0' },
  statusPillTextClosed: { color: '#FFA5A0' },
  heroName: { fontSize: 28, fontWeight: '800', lineHeight: 34 },
  heroCategory: { fontSize: 14, marginTop: 2 },

  // Action bar
  actionBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    paddingHorizontal: 8,
    marginHorizontal: 16,
    marginTop: -1,
    borderRadius: 18,
    shadowColor: '#000',
    shadowOpacity: 0.08,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 4 },
    elevation: 4,
    marginBottom: 4,
    transform: [{ translateY: -20 }],
  },
  actionBarBtn: {
    flex: 1,
    alignItems: 'center',
    gap: 4,
    paddingVertical: 4,
  },
  actionBarIcon: { fontSize: 20 },
  actionBarLabel: { fontSize: 12, fontWeight: '600', opacity: 0.7 },
  actionBarDivider: { width: 1, height: 32, backgroundColor: 'rgba(127,127,127,0.15)' },

  // Content
  content: {
    paddingHorizontal: 16,
    gap: 16,
    marginTop: -12,
  },

  // Piri's Take
  pirisCard: {
    backgroundColor: NAVY,
    borderRadius: 20,
    padding: 20,
    gap: 12,
    shadowColor: NAVY,
    shadowOpacity: 0.3,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 6 },
    elevation: 6,
  },
  pirisHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  pirisLogo: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(212,168,67,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(212,168,67,0.3)',
  },
  pirisLogoText: { fontSize: 16 },
  pirisTitle: {
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  },
  pirisHeadline: {
    fontSize: 18,
    fontWeight: '700',
    lineHeight: 26,
  },
  pirisBody: {
    fontSize: 15,
    lineHeight: 24,
  },
  pirisHighlights: { gap: 8, marginTop: 4 },
  pirisHighlightRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 10,
  },
  pirisHighlightDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: GOLD,
    marginTop: 9,
  },
  pirisHighlightText: {
    flex: 1,
    fontSize: 14,
    lineHeight: 22,
  },
  card: {
    borderRadius: 20,
    padding: 20,
    gap: 12,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 3 },
    elevation: 2,
  },
  cardHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 1,
    opacity: 0.4,
  },
  bodyText: { fontSize: 16, lineHeight: 26 },
  storyBlock: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 4,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: 'rgba(127,127,127,0.12)',
  },
  storyLine: {
    width: 3,
    borderRadius: 2,
    backgroundColor: GOLD,
  },
  storyText: { flex: 1, fontSize: 15, lineHeight: 24, fontStyle: 'italic', opacity: 0.85 },

  // Tags
  tagsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    paddingHorizontal: 4,
  },
  tagChip: {
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 50,
    backgroundColor: 'rgba(15,28,63,0.07)',
    borderWidth: 1,
    borderColor: 'rgba(15,28,63,0.12)',
  },
  tagText: { fontSize: 13, fontWeight: '500' },

  // Hours
  hoursBadge: {
    paddingHorizontal: 9,
    paddingVertical: 4,
    borderRadius: 50,
    borderWidth: 1,
  },
  hoursBadgeVerified: {
    backgroundColor: 'rgba(18,183,106,0.08)',
    borderColor: 'rgba(18,183,106,0.2)',
  },
  hoursBadgeEst: {
    backgroundColor: 'rgba(127,127,127,0.08)',
    borderColor: 'rgba(127,127,127,0.2)',
  },
  hoursBadgeText: { fontSize: 11, fontWeight: '700' },
  hoursBadgeTextVerified: { color: '#067647' },
  hoursBadgeTextEst: { opacity: 0.6 },
  openDetail: { fontSize: 15, fontWeight: '600', lineHeight: 22 },
  openNote: { fontSize: 14, opacity: 0.6, lineHeight: 20 },
  warningBlock: {
    backgroundColor: 'rgba(217,45,32,0.08)',
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  warningText: { color: '#B42318', fontWeight: '600', fontSize: 14 },
  hoursGrid: { gap: 4 },
  hoursRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingVertical: 9,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.1)',
  },
  hoursRowToday: {
    backgroundColor: 'rgba(15,28,63,0.06)',
    borderColor: 'rgba(15,28,63,0.15)',
  },
  hoursDay: { fontSize: 14, opacity: 0.7 },
  hoursDayToday: { fontWeight: '700', opacity: 1 },
  hoursValue: { fontSize: 14, opacity: 0.85 },
  hoursValueToday: { fontWeight: '700' },
  visitHint: { fontSize: 13, opacity: 0.55 },

  // Vibe
  bestForRow: {
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
    marginTop: 4,
  },
  bestForLabel: { fontSize: 13, opacity: 0.5, fontWeight: '500' },
  bestForValue: { fontSize: 14, fontWeight: '600' },

  // Gallery
  galleryRow: { gap: 10, paddingTop: 8, paddingBottom: 4 },
  galleryThumb: {
    width: 140, height: 100,
    borderRadius: 12,
  },

  // Location
  addressText: { fontSize: 14, opacity: 0.65, lineHeight: 20 },
  miniMap: { height: 180, borderRadius: 16, marginTop: 4 },
  directionsBtn: {
    backgroundColor: NAVY,
    borderRadius: 14,
    paddingVertical: 14,
    alignItems: 'center',
    marginTop: 4,
  },
  directionsBtnText: { fontSize: 15, fontWeight: '700' },

  // Nearby
  nearbyRow: { gap: 12, paddingTop: 8, paddingBottom: 4 },
  nearbyCard: {
    width: 140,
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOpacity: 0.06,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 3 },
    elevation: 2,
  },
  nearbyImage: { width: '100%', height: 90 },
  nearbyBody: { padding: 10, gap: 4 },
  nearbyName: { fontSize: 13, fontWeight: '700', lineHeight: 18 },
  nearbyCategory: { fontSize: 11, opacity: 0.5 },
  nearbyStatus: { fontSize: 11, fontWeight: '700' },
  nearbyStatusOpen: { color: '#067647' },
  nearbyStatusClosed: { color: '#B42318' },
  nearbyDist: { fontSize: 11, opacity: 0.5 },
});
