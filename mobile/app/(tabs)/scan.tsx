import React from 'react';
import {
  ActivityIndicator,
  Image,
  Pressable,
  SafeAreaView,
  ScrollView,
  Share,
  StyleSheet,
  View,
  useColorScheme,
} from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Haptics from 'expo-haptics';
import * as ImagePicker from 'expo-image-picker';
import * as Location from 'expo-location';
import { useRouter } from 'expo-router';

import { PlaceImage } from '@/components/place-image';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { identifyPlace, fetchPlace, type IdentifyResult } from '@/src/api/places';
import { useUserProfile } from '@/src/store/user-profile';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';
import type { Place } from '@/src/data/places';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

type State =
  | { kind: 'camera' }
  | { kind: 'loading' }
  | { kind: 'result'; result: IdentifyResult; imageUri: string }
  | { kind: 'error'; message: string };

function MatchedPlaceCard({ place, onPress }: { place: Place; onPress: () => void }) {
  const status = getPlaceOpenStatus(place);
  const open = status.state === 'open' || status.state === 'all-day';
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.matchedCard, pressed && { opacity: 0.85 }]}>
      <View style={styles.matchedCardBadge}>
        <ThemedText style={styles.matchedCardBadgeText} lightColor={GOLD} darkColor={GOLD}>
          ◈ In Piri
        </ThemedText>
      </View>
      <PlaceImage place={place} style={styles.matchedCardImage} />
      <View style={styles.matchedCardBody}>
        <ThemedText style={styles.matchedCardName} lightColor="#fff" darkColor="#fff" numberOfLines={1}>
          {place.name}
        </ThemedText>
        <View style={[styles.matchedStatusPill, open ? styles.pillOpen : styles.pillClosed]}>
          <ThemedText style={[styles.matchedStatusText, open ? styles.pillTextOpen : styles.pillTextClosed]}>
            {status.shortLabel}
          </ThemedText>
        </View>
        <ThemedText style={styles.matchedCardCta} lightColor={GOLD} darkColor={GOLD}>
          View full details →
        </ThemedText>
      </View>
    </Pressable>
  );
}

export default function ScanScreen() {
  const colorScheme = useColorScheme();
  const dark = colorScheme === 'dark';
  const router = useRouter();
  const [permission, requestPermission] = useCameraPermissions();
  const [facing, setFacing] = React.useState<'back' | 'front'>('back');
  const [flash, setFlash] = React.useState<'off' | 'on'>('off');
  const [state, setState] = React.useState<State>({ kind: 'camera' });
  const [pendingImageUri, setPendingImageUri] = React.useState<string | null>(null);
  const cameraRef = React.useRef<CameraView>(null);
  const [matchedPlace, setMatchedPlace] = React.useState<Place | null>(null);
  const { name, profession, interests, faith } = useUserProfile();

  const userProfile = { name, profession, interests, faith };

  const handleShare = async (result: IdentifyResult) => {
    try {
      await Share.share({
        title: result.title,
        message: `${result.title}\n${result.subtitle}\n\n${result.explanation}\n\n— Discovered with Piri`,
      });
    } catch { /* ignore */ }
  };

  const getLocation = async () => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') return undefined;
      const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
      return { lat: loc.coords.latitude, lng: loc.coords.longitude };
    } catch {
      return undefined;
    }
  };

  const processImage = async (base64: string, imageUri: string) => {
    setPendingImageUri(imageUri);
    setState({ kind: 'loading' });
    const coords = await getLocation();
    try {
      const result = await identifyPlace({
        imageBase64: base64,
        mimeType: 'image/jpeg',
        lat: coords?.lat,
        lng: coords?.lng,
        userProfile,
      });
      setState({ kind: 'result', result, imageUri });
      if (result.matchedPlaceId) {
        fetchPlace(result.matchedPlaceId).then(setMatchedPlace).catch(() => {});
      }
    } catch (e: any) {
      setState({ kind: 'error', message: e.message || 'Could not identify this place.' });
    }
  };

  const handleCapture = async () => {
    if (!cameraRef.current) return;
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    try {
      const photo = await cameraRef.current.takePictureAsync({
        base64: true,
        quality: 0.6,
        exif: false,
      });
      if (photo?.base64) await processImage(photo.base64, photo.uri);
    } catch {
      setState({ kind: 'error', message: 'Failed to take photo.' });
    }
  };

  const handleGallery = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      base64: true,
      quality: 0.6,
    });
    if (!result.canceled && result.assets[0]?.base64) {
      await processImage(result.assets[0].base64, result.assets[0].uri);
    }
  };

  const reset = () => { setState({ kind: 'camera' }); setMatchedPlace(null); setPendingImageUri(null); };

  // ── Permission gate ──────────────────────────────────────────────────────────
  if (!permission) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color={NAVY} />
      </View>
    );
  }

  if (!permission.granted) {
    return (
      <View style={[styles.center, { backgroundColor: NAVY }]}>
        <SafeAreaView style={styles.permissionBox}>
          <ThemedText style={styles.permissionTitle} lightColor="#fff" darkColor="#fff">
            Camera access needed
          </ThemedText>
          <ThemedText style={styles.permissionBody} lightColor="rgba(255,255,255,0.7)" darkColor="rgba(255,255,255,0.7)">
            Point your camera at any place in the world and Piri will explain it — tailored to who you are.
          </ThemedText>
          <Pressable style={styles.goldButton} onPress={requestPermission}>
            <ThemedText style={styles.goldButtonText} lightColor={NAVY} darkColor={NAVY}>
              Allow Camera
            </ThemedText>
          </Pressable>
        </SafeAreaView>
      </View>
    );
  }

  // ── Loading ──────────────────────────────────────────────────────────────────
  if (state.kind === 'loading') {
    return (
      <View style={{ flex: 1, backgroundColor: NAVY }}>
        {pendingImageUri && (
          <Image source={{ uri: pendingImageUri }} style={styles.loadingBg} blurRadius={6} />
        )}
        <View style={[styles.loadingOverlay, pendingImageUri ? { backgroundColor: 'rgba(15,28,63,0.7)' } : { backgroundColor: NAVY }]}>
          <ActivityIndicator size="large" color={GOLD} />
          <ThemedText style={styles.loadingText} lightColor="rgba(255,255,255,0.9)" darkColor="rgba(255,255,255,0.9)">
            Piri is looking...
          </ThemedText>
        </View>
      </View>
    );
  }

  // ── Result ───────────────────────────────────────────────────────────────────
  if (state.kind === 'result') {
    const { result } = state;
    return (
      <View style={{ flex: 1, backgroundColor: dark ? '#0A0F1E' : '#F4F5F9' }}>
        <SafeAreaView style={{ backgroundColor: NAVY }}>
          <View style={styles.resultHeader}>
            <Pressable onPress={reset} style={({ pressed }) => pressed && { opacity: 0.7 }}>
              <ThemedText style={styles.backBtn} lightColor="rgba(255,255,255,0.7)" darkColor="rgba(255,255,255,0.7)">
                ← Scan again
              </ThemedText>
            </Pressable>
          </View>
        </SafeAreaView>

        <ScrollView contentContainerStyle={styles.resultContent} showsVerticalScrollIndicator={false}>
          {/* Captured photo thumbnail */}
          <Image source={{ uri: state.imageUri }} style={styles.capturedPhoto} />

          <ThemedView style={styles.resultCard}>
            <ThemedText style={styles.resultTitle}>{result.title}</ThemedText>
            <ThemedText style={styles.resultSubtitle}>{result.subtitle}</ThemedText>

            <View style={styles.divider} />

            <ThemedText style={styles.resultExplanation}>{result.explanation}</ThemedText>

            {result.highlights.length > 0 && (
              <View style={styles.highlights}>
                {result.highlights.map((h, i) => (
                  <View key={i} style={styles.highlightRow}>
                    <View style={styles.highlightDot} />
                    <ThemedText style={styles.highlightText}>{h}</ThemedText>
                  </View>
                ))}
              </View>
            )}
          </ThemedView>

          {/* Actions */}
          <View style={styles.resultActions}>
            <Pressable
              style={({ pressed }) => [styles.actionBtn, styles.actionBtnSecondary, pressed && { opacity: 0.7 }]}
              onPress={() => handleShare(result)}>
              <ThemedText style={styles.actionBtnText}>Share</ThemedText>
            </Pressable>
            <Pressable
              style={({ pressed }) => [styles.actionBtn, styles.actionBtnPrimary, pressed && { opacity: 0.8 }]}
              onPress={() => {
                router.navigate({
                  pathname: '/(tabs)/ai',
                  params: { q: `Tell me more about ${result.title}` },
                });
              }}>
              <ThemedText style={styles.actionBtnTextPrimary} lightColor="#fff" darkColor="#fff">
                Ask Piri more →
              </ThemedText>
            </Pressable>
          </View>

          {result.matchedPlaceId && (
            matchedPlace ? (
              <MatchedPlaceCard
                place={matchedPlace}
                onPress={() => router.push({ pathname: '/place/[id]', params: { id: matchedPlace.id } })}
              />
            ) : (
              <Pressable
                style={({ pressed }) => [styles.matchedPlaceBtn, pressed && { opacity: 0.8 }]}
                onPress={() => router.push({ pathname: '/place/[id]', params: { id: result.matchedPlaceId! } })}>
                <ThemedText style={styles.matchedPlaceBtnText} lightColor={GOLD} darkColor={GOLD}>
                  ◈ View full details in Piri
                </ThemedText>
              </Pressable>
            )
          )}

          <Pressable style={({ pressed }) => [styles.scanAgainBtn, pressed && { opacity: 0.8 }]} onPress={reset}>
            <ThemedText style={styles.scanAgainText} lightColor="rgba(255,255,255,0.7)" darkColor="rgba(255,255,255,0.7)">
              Scan another place
            </ThemedText>
          </Pressable>
        </ScrollView>
      </View>
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────────
  if (state.kind === 'error') {
    return (
      <View style={{ flex: 1, backgroundColor: NAVY }}>
        {pendingImageUri && (
          <Image source={{ uri: pendingImageUri }} style={styles.loadingBg} blurRadius={8} />
        )}
        <View style={[styles.loadingOverlay, { backgroundColor: 'rgba(15,28,63,0.82)', gap: 20 }]}>
          <ThemedText style={[styles.loadingText, { fontSize: 40 }]}>⚠️</ThemedText>
          <ThemedText style={styles.errorText} lightColor="rgba(255,255,255,0.9)" darkColor="rgba(255,255,255,0.9)">
            {state.message}
          </ThemedText>
          <Pressable style={styles.goldButton} onPress={reset}>
            <ThemedText style={styles.goldButtonText} lightColor={NAVY} darkColor={NAVY}>
              Try again
            </ThemedText>
          </Pressable>
        </View>
      </View>
    );
  }

  // ── Camera ───────────────────────────────────────────────────────────────────
  return (
    <View style={{ flex: 1, backgroundColor: '#000' }}>
      <CameraView ref={cameraRef} style={StyleSheet.absoluteFill} facing={facing} flash={flash} />

      {/* Overlay — absolute positioned on top of camera */}
      <View style={StyleSheet.absoluteFill} pointerEvents="box-none">
        {/* Top overlay */}
        <SafeAreaView>
          <View style={styles.topBar}>
            <Pressable
              onPress={() => setFlash((f) => (f === 'off' ? 'on' : 'off'))}
              style={({ pressed }) => [styles.flashBtn, pressed && { opacity: 0.7 }]}>
              <ThemedText style={[styles.flashBtnText, flash === 'on' && styles.flashBtnTextOn]} lightColor="#fff" darkColor="#fff">
                ⚡
              </ThemedText>
            </Pressable>
            <ThemedText style={styles.topBarText} lightColor="#fff" darkColor="#fff">
              Point at any place
            </ThemedText>
            <View style={{ width: 36 }} />
          </View>
        </SafeAreaView>

        {/* Viewfinder corners */}
        <View style={styles.viewfinder} pointerEvents="none">
          <View style={[styles.corner, styles.cornerTL]} />
          <View style={[styles.corner, styles.cornerTR]} />
          <View style={[styles.corner, styles.cornerBL]} />
          <View style={[styles.corner, styles.cornerBR]} />
        </View>

        {/* Bottom controls */}
        <View style={styles.bottomBar}>
          <Pressable
            style={({ pressed }) => [styles.sideBtn, pressed && { opacity: 0.7 }]}
            onPress={handleGallery}>
            <ThemedText style={styles.sideBtnText} lightColor="#fff" darkColor="#fff">
              Gallery
            </ThemedText>
          </Pressable>

          <Pressable
            style={({ pressed }) => [styles.captureBtn, pressed && { transform: [{ scale: 0.95 }] }]}
            onPress={handleCapture}>
            <View style={styles.captureBtnInner} />
          </Pressable>

          <Pressable
            style={({ pressed }) => [styles.sideBtn, pressed && { opacity: 0.7 }]}
            onPress={() => setFacing((f) => (f === 'back' ? 'front' : 'back'))}>
            <ThemedText style={styles.sideBtnText} lightColor="#fff" darkColor="#fff">
              Flip
            </ThemedText>
          </Pressable>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
    padding: 32,
  },
  permissionBox: {
    alignItems: 'center',
    gap: 16,
    paddingHorizontal: 16,
  },
  permissionTitle: {
    fontSize: 24,
    fontWeight: '700',
    textAlign: 'center',
  },
  permissionBody: {
    fontSize: 16,
    lineHeight: 24,
    textAlign: 'center',
  },
  goldButton: {
    backgroundColor: GOLD,
    paddingHorizontal: 32,
    paddingVertical: 16,
    borderRadius: 14,
    marginTop: 8,
  },
  goldButtonText: {
    fontSize: 17,
    fontWeight: '700',
  },
  loadingBg: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
  },
  loadingOverlay: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
    padding: 32,
  },
  loadingText: {
    fontSize: 18,
    marginTop: 8,
  },
  capturedPhoto: {
    width: '100%',
    height: 220,
    borderRadius: 18,
    marginBottom: 4,
  },
  // Camera UI
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 8,
  },
  topBarText: {
    fontSize: 15,
    fontWeight: '500',
    opacity: 0.9,
    textAlign: 'center',
  },
  flashBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(0,0,0,0.35)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  flashBtnText: {
    fontSize: 18,
    opacity: 0.45,
  },
  flashBtnTextOn: {
    opacity: 1,
  },
  viewfinder: {
    flex: 1,
    margin: 48,
  },
  corner: {
    position: 'absolute',
    width: 28,
    height: 28,
    borderColor: GOLD,
  },
  cornerTL: { top: 0, left: 0, borderTopWidth: 3, borderLeftWidth: 3 },
  cornerTR: { top: 0, right: 0, borderTopWidth: 3, borderRightWidth: 3 },
  cornerBL: { bottom: 0, left: 0, borderBottomWidth: 3, borderLeftWidth: 3 },
  cornerBR: { bottom: 0, right: 0, borderBottomWidth: 3, borderRightWidth: 3 },
  bottomBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 40,
    paddingBottom: 48,
    paddingTop: 16,
  },
  sideBtn: {
    width: 70,
    alignItems: 'center',
  },
  sideBtnText: {
    fontSize: 14,
    fontWeight: '600',
  },
  captureBtn: {
    width: 76,
    height: 76,
    borderRadius: 38,
    borderWidth: 3,
    borderColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  captureBtnInner: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#fff',
  },
  // Result
  resultHeader: {
    paddingHorizontal: 20,
    paddingVertical: 14,
  },
  backBtn: {
    fontSize: 15,
    fontWeight: '500',
  },
  resultContent: {
    padding: 20,
    gap: 16,
    paddingBottom: 48,
  },
  resultCard: {
    borderRadius: 20,
    padding: 24,
    gap: 12,
    shadowColor: '#000',
    shadowOpacity: 0.07,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 4 },
    elevation: 4,
  },
  resultTitle: {
    fontSize: 26,
    fontWeight: '800',
    lineHeight: 32,
  },
  resultSubtitle: {
    fontSize: 15,
    opacity: 0.55,
    fontWeight: '500',
  },
  divider: {
    height: 1,
    backgroundColor: 'rgba(127,127,127,0.15)',
    marginVertical: 4,
  },
  resultExplanation: {
    fontSize: 16,
    lineHeight: 26,
  },
  highlights: {
    gap: 10,
    marginTop: 8,
  },
  highlightRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 10,
  },
  highlightDot: {
    width: 7,
    height: 7,
    borderRadius: 4,
    backgroundColor: GOLD,
    marginTop: 8,
  },
  highlightText: {
    flex: 1,
    fontSize: 15,
    lineHeight: 22,
  },
  resultActions: {
    flexDirection: 'row',
    gap: 12,
  },
  actionBtn: {
    flex: 1,
    borderRadius: 14,
    paddingVertical: 14,
    alignItems: 'center',
  },
  actionBtnSecondary: {
    borderWidth: 1.5,
    borderColor: 'rgba(15,28,63,0.2)',
    backgroundColor: 'transparent',
  },
  actionBtnPrimary: {
    backgroundColor: NAVY,
  },
  actionBtnText: {
    fontSize: 15,
    fontWeight: '600',
  },
  actionBtnTextPrimary: {
    fontSize: 15,
    fontWeight: '700',
  },
  matchedCard: {
    borderRadius: 18,
    overflow: 'hidden',
    borderWidth: 1.5,
    borderColor: GOLD,
  },
  matchedCardBadge: {
    position: 'absolute',
    top: 10,
    left: 12,
    zIndex: 10,
    backgroundColor: 'rgba(0,0,0,0.55)',
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  matchedCardBadgeText: {
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  matchedCardImage: {
    width: '100%',
    height: 150,
  },
  matchedCardBody: {
    backgroundColor: NAVY,
    padding: 14,
    gap: 6,
  },
  matchedCardName: {
    fontSize: 17,
    fontWeight: '700',
  },
  matchedStatusPill: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 50,
    borderWidth: 1,
  },
  pillOpen: { backgroundColor: 'rgba(18,183,106,0.2)', borderColor: 'rgba(18,183,106,0.4)' },
  pillClosed: { backgroundColor: 'rgba(217,45,32,0.15)', borderColor: 'rgba(217,45,32,0.3)' },
  matchedStatusText: { fontSize: 11, fontWeight: '700' },
  pillTextOpen: { color: '#6EFAB0' },
  pillTextClosed: { color: '#FFA5A0' },
  matchedCardCta: {
    fontSize: 14,
    fontWeight: '600',
  },
  matchedPlaceBtn: {
    alignItems: 'center',
    paddingVertical: 14,
    borderRadius: 14,
    borderWidth: 1.5,
    borderColor: GOLD,
    backgroundColor: 'rgba(212,168,67,0.08)',
  },
  matchedPlaceBtnText: {
    fontSize: 15,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  scanAgainBtn: {
    alignItems: 'center',
    paddingVertical: 12,
  },
  scanAgainText: {
    fontSize: 15,
    fontWeight: '500',
  },
  errorText: {
    fontSize: 16,
    textAlign: 'center',
    lineHeight: 24,
  },
});
