import { Link } from 'expo-router';
import Constants from 'expo-constants';
import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import ParallaxScrollView from '@/components/parallax-scroll-view';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { fetchAppStatus, type AppStatusResponse } from '@/src/api/app-status';
import { API_BASE_URL } from '@/src/config/api';
import { useSavedPlaces } from '@/src/store/saved-places';

type StatusTone = 'neutral' | 'positive' | 'warning';

function StatusChip({ label, tone = 'neutral' }: { label: string; tone?: StatusTone }) {
  return (
    <View
      style={[
        styles.statusChip,
        tone === 'positive' && styles.statusChipPositive,
        tone === 'warning' && styles.statusChipWarning,
      ]}>
      <ThemedText style={styles.statusChipText}>{label}</ThemedText>
    </View>
  );
}

export default function SettingsScreen() {
  const { favoritePlaceIds, planPlaceIds, clearFavorites, clearPlan } = useSavedPlaces();
  const favoriteCount = Object.keys(favoritePlaceIds).length;
  const planCount = planPlaceIds.length;
  const version = Constants.expoConfig?.version ?? '1.0.0';

  const [appStatus, setAppStatus] = React.useState<AppStatusResponse | null>(null);
  const [statusError, setStatusError] = React.useState<string | null>(null);

  React.useEffect(() => {
    let active = true;

    void (async () => {
      try {
        const nextStatus = await fetchAppStatus();
        if (!active) return;
        setAppStatus(nextStatus);
        setStatusError(null);
      } catch {
        if (!active) return;
        setStatusError('Backend status could not be loaded right now.');
      }
    })();

    return () => {
      active = false;
    };
  }, []);

  const isBackendConnected = Boolean(appStatus) && !statusError;
  const aiEnabled = appStatus?.features.aiRecommendationsEnabled ?? false;
  const aiProviderLabel =
    appStatus?.features.aiProvider === 'openai'
      ? 'OpenAI'
      : appStatus?.features.aiProvider === 'openrouter'
        ? 'OpenRouter'
        : null;
  const googleHoursEnabled = appStatus?.features.googleHoursPreviewEnabled ?? false;

  return (
    <ParallaxScrollView
      headerBackgroundColor={{ light: '#E6F2FF', dark: '#0E2438' }}
      headerImage={<View style={styles.header} />}>
      <ThemedView style={styles.container}>
        <ThemedText type="title">Settings</ThemedText>

        <ThemedView style={styles.card}>
          <ThemedText type="subtitle">App</ThemedText>
          <ThemedText style={styles.text}>Version {version}</ThemedText>
          <ThemedText style={styles.text}>
            Browse places, save favorites, and manage your plan from one app.
          </ThemedText>
        </ThemedView>

        <ThemedView style={styles.card}>
          <View style={styles.cardTopRow}>
            <ThemedText type="subtitle">Backend</ThemedText>
            <StatusChip
              label={
                statusError
                  ? 'Status unavailable'
                  : isBackendConnected
                    ? 'Connected'
                    : 'Checking'
              }
              tone={statusError ? 'warning' : isBackendConnected ? 'positive' : 'neutral'}
            />
          </View>
          <ThemedText style={styles.label}>API base URL</ThemedText>
          <ThemedText style={styles.code}>{API_BASE_URL}</ThemedText>
          <ThemedText style={styles.text}>
            Override it with `EXPO_PUBLIC_API_URL` in `mobile/.env` when you need a fixed address.
          </ThemedText>
          {statusError ? <ThemedText style={styles.warningText}>{statusError}</ThemedText> : null}
          {appStatus ? (
            <ThemedText style={styles.text}>
              AI recommendations: {aiEnabled ? `enabled via ${aiProviderLabel}` : 'disabled'} ·
              Google hours preview: {googleHoursEnabled ? 'enabled' : 'manual only'}
            </ThemedText>
          ) : null}
        </ThemedView>

        <ThemedView style={styles.card}>
          <ThemedText type="subtitle">Saved Data</ThemedText>
          <ThemedText style={styles.text}>Favorites: {favoriteCount}</ThemedText>
          <ThemedText style={styles.text}>Plan items: {planCount}</ThemedText>

          <View style={styles.actions}>
            <Pressable
              onPress={clearFavorites}
              disabled={favoriteCount === 0}
              style={({ pressed }) => [
                styles.button,
                favoriteCount === 0 && styles.buttonDisabled,
                pressed && favoriteCount > 0 && styles.buttonPressed,
              ]}>
              <ThemedText style={styles.buttonText}>Clear Favorites</ThemedText>
            </Pressable>
            <Pressable
              onPress={clearPlan}
              disabled={planCount === 0}
              style={({ pressed }) => [
                styles.button,
                planCount === 0 && styles.buttonDisabled,
                pressed && planCount > 0 && styles.buttonPressed,
              ]}>
              <ThemedText style={styles.buttonText}>Clear Plan</ThemedText>
            </Pressable>
          </View>
        </ThemedView>

        <ThemedView style={styles.card}>
          <View style={styles.cardTopRow}>
            <ThemedText type="subtitle">AI</ThemedText>
            <StatusChip
              label={aiEnabled ? `${aiProviderLabel} ready` : 'Needs backend key'}
              tone={aiEnabled ? 'positive' : 'warning'}
            />
          </View>
          <ThemedText style={styles.text}>
            {aiEnabled
              ? `Ask AI is active and the backend is returning recommendations through ${aiProviderLabel}.`
              : 'Ask AI screen is wired, but recommendations stay disabled until the backend key is configured.'}
          </ThemedText>
          <ThemedText style={styles.text}>
            {aiEnabled
              ? 'You can use the Ask AI tab directly.'
              : 'Set `OPENAI_API_KEY` or `OPENROUTER_API_KEY` in `apps/api/.env`, then restart the API.'}
          </ThemedText>
        </ThemedView>

        <ThemedView style={styles.card}>
          <View style={styles.cardTopRow}>
            <ThemedText type="subtitle">Admin</ThemedText>
            <StatusChip
              label={googleHoursEnabled ? 'Google hours ready' : 'Hours review manual'}
              tone={googleHoursEnabled ? 'positive' : 'neutral'}
            />
          </View>
          <ThemedText style={styles.text}>
            Review pending image candidates and manage verified place photos without using the
            terminal.
          </ThemedText>
          <ThemedText style={styles.text}>
            Hours Review {googleHoursEnabled ? 'can prefill from Google Places.' : 'currently works in manual mode.'}
          </ThemedText>

          <View style={styles.adminActions}>
            <Link href={'/admin-hours' as any} asChild>
              <Pressable
                style={({ pressed }) => [styles.panelButton, pressed && styles.buttonPressed]}>
                <ThemedText style={styles.panelButtonText}>Open Hours Review</ThemedText>
              </Pressable>
            </Link>
            <Link href="/admin-images" asChild>
              <Pressable
                style={({ pressed }) => [styles.panelButton, pressed && styles.buttonPressed]}>
                <ThemedText style={styles.panelButtonText}>Open Image Review</ThemedText>
              </Pressable>
            </Link>
          </View>
        </ThemedView>
      </ThemedView>
    </ParallaxScrollView>
  );
}

const styles = StyleSheet.create({
  header: {
    height: 178,
  },
  container: {
    gap: 12,
  },
  card: {
    gap: 10,
    padding: 16,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.18)',
  },
  cardTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  label: {
    fontSize: 13,
    lineHeight: 18,
    opacity: 0.72,
  },
  code: {
    fontSize: 14,
    lineHeight: 20,
    fontFamily: 'monospace',
  },
  text: {
    opacity: 0.8,
    lineHeight: 22,
  },
  warningText: {
    color: '#B54708',
    lineHeight: 20,
  },
  statusChip: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.18)',
    backgroundColor: 'rgba(127,127,127,0.06)',
  },
  statusChipPositive: {
    borderColor: 'rgba(18,183,106,0.24)',
    backgroundColor: 'rgba(18,183,106,0.1)',
  },
  statusChipWarning: {
    borderColor: 'rgba(245,158,11,0.24)',
    backgroundColor: 'rgba(245,158,11,0.12)',
  },
  statusChipText: {
    fontSize: 12,
    lineHeight: 16,
  },
  actions: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 4,
  },
  adminActions: {
    gap: 10,
    marginTop: 4,
  },
  button: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.24)',
  },
  panelButton: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 14,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(15,23,42,0.14)',
    backgroundColor: 'rgba(15,23,42,0.04)',
  },
  buttonText: {
    fontSize: 14,
    lineHeight: 18,
  },
  panelButtonText: {
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '600',
  },
  buttonDisabled: {
    opacity: 0.45,
  },
  buttonPressed: {
    opacity: 0.72,
  },
});
