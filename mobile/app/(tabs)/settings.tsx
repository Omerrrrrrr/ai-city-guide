import { Link, useRouter } from 'expo-router';
import Constants from 'expo-constants';
import * as Haptics from 'expo-haptics';
import React from 'react';
import { useTranslation } from 'react-i18next';
import { Pressable, ScrollView, StyleSheet, TextInput, View, useColorScheme } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { FAITHS, INTERESTS, PROFESSIONS } from '@/src/constants/profile-options';
import { useSavedPlaces } from '@/src/store/saved-places';
import { useRecentlyViewed } from '@/src/store/recently-viewed';
import { useCityStore } from '@/src/store/city';
import { useLanguageStore, type LanguageCode } from '@/src/store/language';
import { useUserProfile as useProfile, type Interest } from '@/src/store/user-profile';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

const LANGUAGE_OPTIONS: { code: LanguageCode | null; emoji: string; labelKey: string }[] = [
  { code: null, emoji: '🌐', labelKey: 'settings.language.system' },
  { code: 'en', emoji: '🇬🇧', labelKey: 'settings.language.en' },
  { code: 'tr', emoji: '🇹🇷', labelKey: 'settings.language.tr' },
  { code: 'nb', emoji: '🇳🇴', labelKey: 'settings.language.nb' },
];

export default function ProfileScreen() {
  const dark = useColorScheme() === 'dark';
  const router = useRouter();
  const { t } = useTranslation();
  const { name, profession, interests, faith, setProfile } = useProfile();
  const { cityName } = useCityStore();
  const { language, setLanguage } = useLanguageStore();
  const [editingName, setEditingName] = React.useState(false);
  const [nameInput, setNameInput] = React.useState(name);
  const { favoritePlaceIds, planPlaceIds, clearFavorites, clearPlan } = useSavedPlaces();
  const { viewedIds, clearHistory } = useRecentlyViewed();
  const favoriteCount = Object.keys(favoritePlaceIds).length;
  const planCount = planPlaceIds.length;
  const recentCount = viewedIds.length;
  const version = Constants.expoConfig?.version ?? '1.0.0';

  const toggleInterest = (value: Interest) =>
    setProfile({
      interests: interests.includes(value)
        ? interests.filter((i) => i !== value)
        : [...interests, value],
    });

  const displayName = name.trim() || t('settings.travelerFallback');
  const professionLabel = profession
    ? t(PROFESSIONS.find((p) => p.value === profession)?.labelKey ?? '')
    : null;
  const faithLabel =
    faith && faith !== 'prefer_not_to_say'
      ? t(FAITHS.find((f) => f.value === faith)?.labelKey ?? '')
      : null;

  return (
    <View style={styles.screenRoot}>
      {/* Navy header */}
      <SafeAreaView style={{ backgroundColor: NAVY }}>
        <View style={styles.navHeader}>
          <View style={styles.avatar}>
            <ThemedText style={styles.avatarText}>{displayName[0].toUpperCase()}</ThemedText>
          </View>
          <View style={{ flex: 1 }}>
            {editingName ? (
              <TextInput
                value={nameInput}
                onChangeText={setNameInput}
                autoFocus
                style={styles.nameInput}
                placeholderTextColor="rgba(255,255,255,0.4)"
                placeholder={t('onboarding.name.placeholder')}
                returnKeyType="done"
                onSubmitEditing={() => {
                  setProfile({ name: nameInput.trim() });
                  setEditingName(false);
                }}
                onBlur={() => {
                  setProfile({ name: nameInput.trim() });
                  setEditingName(false);
                }}
              />
            ) : (
              <Pressable onPress={() => { setNameInput(name); setEditingName(true); }}>
                <ThemedText style={styles.displayName} lightColor="#fff" darkColor="#fff">
                  {displayName}
                  <ThemedText style={styles.editHint} lightColor="rgba(255,255,255,0.35)" darkColor="rgba(255,255,255,0.35)"> ✎</ThemedText>
                </ThemedText>
              </Pressable>
            )}
            {(professionLabel || faithLabel) ? (
              <ThemedText style={styles.subline} lightColor="rgba(255,255,255,0.6)" darkColor="rgba(255,255,255,0.6)">
                {[professionLabel, faithLabel].filter(Boolean).join(' · ')}
              </ThemedText>
            ) : null}
          </View>
        </View>
      </SafeAreaView>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}>

      {/* Language */}
      <ThemedView style={styles.card}>
        <ThemedText style={styles.cardLabel}>{t('settings.language.label')}</ThemedText>
        <View style={styles.chipGrid}>
          {LANGUAGE_OPTIONS.map(({ code, emoji, labelKey }) => {
            const active = language === code;
            return (
              <Pressable
                key={code ?? 'system'}
                style={[styles.chip, active && styles.chipActive]}
                onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); setLanguage(code); }}>
                <ThemedText style={styles.chipEmoji}>{emoji}</ThemedText>
                <ThemedText style={[styles.chipText, active && styles.chipTextActive]}>
                  {t(labelKey)}
                </ThemedText>
              </Pressable>
            );
          })}
        </View>
      </ThemedView>

      {/* Profession */}
      <ThemedView style={styles.card}>
        <ThemedText style={styles.cardLabel}>{t('onboarding.profession.title')}</ThemedText>
        <View style={styles.chipGrid}>
          {PROFESSIONS.map(({ value, labelKey }) => {
            const active = profession === value;
            return (
              <Pressable
                key={value}
                style={[styles.chip, active && styles.chipActive]}
                onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); setProfile({ profession: value }); }}>
                <ThemedText style={[styles.chipText, active && styles.chipTextActive]}>
                  {t(labelKey)}
                </ThemedText>
              </Pressable>
            );
          })}
        </View>
      </ThemedView>

      {/* Interests */}
      <ThemedView style={styles.card}>
        <ThemedText style={styles.cardLabel}>{t('onboarding.faithInterests.interestsLabel')}</ThemedText>
        <View style={styles.chipGrid}>
          {INTERESTS.map(({ value, labelKey }) => {
            const active = interests.includes(value);
            return (
              <Pressable
                key={value}
                style={[styles.chip, active && styles.chipActive]}
                onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); toggleInterest(value); }}>
                <ThemedText style={[styles.chipText, active && styles.chipTextActive]}>
                  {t(labelKey)}
                </ThemedText>
              </Pressable>
            );
          })}
        </View>
      </ThemedView>

      {/* Faith */}
      <ThemedView style={styles.card}>
        <ThemedText style={styles.cardLabel}>{t('onboarding.faithInterests.faithLabel')}</ThemedText>
        <ThemedText style={styles.cardNote}>{t('settings.faithNote')}</ThemedText>
        <View style={styles.chipGrid}>
          {FAITHS.map(({ value, labelKey }) => {
            const active = faith === value;
            return (
              <Pressable
                key={value}
                style={[styles.chip, active && styles.chipActive]}
                onPress={() => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); setProfile({ faith: value }); }}>
                <ThemedText style={[styles.chipText, active && styles.chipTextActive]}>
                  {t(labelKey)}
                </ThemedText>
              </Pressable>
            );
          })}
        </View>
      </ThemedView>

      {/* Current city */}
      <ThemedView style={styles.card}>
        <ThemedText style={styles.cardLabel}>{t('settings.currentCity')}</ThemedText>
        <Pressable
          onPress={() => router.push('/city-picker' as never)}
          style={({ pressed }) => [styles.cityRow, pressed && styles.buttonPressed]}>
          <ThemedText style={styles.cityName}>
            {cityName ? t('home.cityPill', { cityName }) : t('common.everywhere')}
          </ThemedText>
          <ThemedText style={styles.cityChevron} lightColor={NAVY} darkColor={GOLD}>{t('settings.changeCity')}</ThemedText>
        </Pressable>
      </ThemedView>

      {/* Saved data */}
      <ThemedView style={styles.card}>
        <View style={styles.cardHeaderRow}>
          <ThemedText style={styles.cardLabel}>{t('settings.savedPlaces')}</ThemedText>
          <Link href={'/saved' as never} asChild>
            <Pressable style={({ pressed }) => [styles.viewAllBtn, pressed && styles.buttonPressed]}>
              <ThemedText style={styles.viewAllText} lightColor={NAVY} darkColor={GOLD}>
                {t('settings.viewAll')}
              </ThemedText>
            </Pressable>
          </Link>
        </View>
        <View style={styles.row}>
          <Link href={{ pathname: '/saved', params: { tab: 'favorites' } } as never} asChild>
            <Pressable style={({ pressed }) => [styles.statBtn, pressed && styles.buttonPressed]}>
              <ThemedText style={styles.statNum}>{favoriteCount}</ThemedText>
              <ThemedText style={styles.statLabel}>{t('settings.stats.saved')}</ThemedText>
            </Pressable>
          </Link>
          <Link href={{ pathname: '/saved', params: { tab: 'plan' } } as never} asChild>
            <Pressable style={({ pressed }) => [styles.statBtn, pressed && styles.buttonPressed]}>
              <ThemedText style={styles.statNum}>{planCount}</ThemedText>
              <ThemedText style={styles.statLabel}>{t('settings.stats.inPlan')}</ThemedText>
            </Pressable>
          </Link>
          <Link href={{ pathname: '/saved', params: { tab: 'visited' } } as never} asChild>
            <Pressable style={({ pressed }) => [styles.statBtn, pressed && styles.buttonPressed]}>
              <ThemedText style={styles.statNum}>{recentCount}</ThemedText>
              <ThemedText style={styles.statLabel}>{t('settings.stats.visited')}</ThemedText>
            </Pressable>
          </Link>
        </View>
        <View style={styles.actions}>
          <Pressable
            onPress={clearFavorites}
            disabled={favoriteCount === 0}
            style={({ pressed }) => [
              styles.button,
              favoriteCount === 0 && styles.buttonDisabled,
              pressed && favoriteCount > 0 && styles.buttonPressed,
            ]}>
            <ThemedText style={styles.buttonText}>{t('settings.clearFavorites')}</ThemedText>
          </Pressable>
          <Pressable
            onPress={clearPlan}
            disabled={planCount === 0}
            style={({ pressed }) => [
              styles.button,
              planCount === 0 && styles.buttonDisabled,
              pressed && planCount > 0 && styles.buttonPressed,
            ]}>
            <ThemedText style={styles.buttonText}>{t('settings.clearPlan')}</ThemedText>
          </Pressable>
        </View>
        <Pressable
          onPress={clearHistory}
          disabled={recentCount === 0}
          style={({ pressed }) => [
            styles.button,
            recentCount === 0 && styles.buttonDisabled,
            pressed && recentCount > 0 && styles.buttonPressed,
          ]}>
          <ThemedText style={styles.buttonText}>{t('settings.clearHistory')}</ThemedText>
        </Pressable>
      </ThemedView>

      {/* App info */}
      <ThemedText style={styles.versionText}>{t('settings.version', { version })}</ThemedText>

      {/* Admin (dev only) */}
      {__DEV__ ? (
        <ThemedView style={styles.card}>
          <ThemedText style={styles.cardLabel}>{t('settings.adminDevOnly')}</ThemedText>
          <View style={styles.adminActions}>
            <Link href={'/admin-hours' as never} asChild>
              <Pressable style={({ pressed }) => [styles.panelButton, pressed && styles.buttonPressed]}>
                <ThemedText style={styles.panelButtonText}>{t('settings.hoursReview')}</ThemedText>
              </Pressable>
            </Link>
            <Link href="/admin-images" asChild>
              <Pressable style={({ pressed }) => [styles.panelButton, pressed && styles.buttonPressed]}>
                <ThemedText style={styles.panelButtonText}>{t('settings.imageReview')}</ThemedText>
              </Pressable>
            </Link>
          </View>
        </ThemedView>
      ) : null}
    </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  screenRoot: {
    flex: 1,
  },
  navHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 16,
  },
  scrollView: {
    flex: 1,
  },
  content: {
    paddingTop: 20,
    paddingHorizontal: 20,
    paddingBottom: 40,
    gap: 14,
  },
  avatar: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: {
    color: GOLD,
    fontSize: 24,
    fontWeight: '700',
  },
  displayName: {
    fontSize: 20,
    fontWeight: '700',
  },
  editHint: {
    fontSize: 16,
    fontWeight: '400',
  },
  nameInput: {
    fontSize: 20,
    fontWeight: '700',
    color: '#fff',
    borderBottomWidth: 1.5,
    borderBottomColor: GOLD,
    paddingVertical: 2,
    minWidth: 120,
  },
  subline: {
    fontSize: 14,
    marginTop: 2,
  },
  cityRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  cityName: {
    fontSize: 16,
    fontWeight: '600',
  },
  cityChevron: {
    fontSize: 14,
    fontWeight: '600',
  },
  cardHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  viewAllBtn: {
    paddingHorizontal: 4,
    paddingVertical: 2,
  },
  viewAllText: {
    fontSize: 14,
    fontWeight: '600',
  },
  card: {
    gap: 12,
    padding: 16,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.18)',
  },
  cardLabel: {
    fontSize: 13,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.8,
    opacity: 0.5,
  },
  cardNote: {
    fontSize: 14,
    opacity: 0.6,
    lineHeight: 20,
    marginTop: -4,
  },
  chipGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 50,
    borderWidth: 1.5,
    borderColor: 'rgba(127,127,127,0.24)',
  },
  chipActive: {
    backgroundColor: NAVY,
    borderColor: NAVY,
  },
  chipEmoji: {
    fontSize: 15,
  },
  chipText: {
    fontSize: 14,
    fontWeight: '500',
  },
  chipTextActive: {
    color: '#FFFFFF',
  },
  row: {
    flexDirection: 'row',
    gap: 12,
  },
  statBtn: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 10,
    borderRadius: 12,
    backgroundColor: 'rgba(15,28,63,0.05)',
    gap: 2,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.12)',
  },
  statNum: {
    fontSize: 22,
    fontWeight: '700',
    lineHeight: 26,
  },
  statLabel: {
    fontSize: 12,
    opacity: 0.5,
    fontWeight: '500',
  },
  actions: {
    flexDirection: 'row',
    gap: 10,
  },
  adminActions: {
    gap: 10,
  },
  button: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 11,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.24)',
  },
  panelButton: {
    alignItems: 'center',
    paddingVertical: 14,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(15,23,42,0.14)',
    backgroundColor: 'rgba(15,23,42,0.04)',
  },
  buttonText: {
    fontSize: 14,
  },
  panelButtonText: {
    fontSize: 15,
    fontWeight: '600',
  },
  buttonDisabled: {
    opacity: 0.35,
  },
  buttonPressed: {
    opacity: 0.7,
  },
  versionText: {
    textAlign: 'center',
    fontSize: 13,
    opacity: 0.35,
  },
});
