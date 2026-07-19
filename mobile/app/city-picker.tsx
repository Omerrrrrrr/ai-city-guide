import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  TextInput,
  View,
  useColorScheme,
} from 'react-native';
import { useRouter } from 'expo-router';
import type { TFunction } from 'i18next';
import { useTranslation } from 'react-i18next';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { searchCities, discoverCity, type CityResult } from '@/src/api/cities';
import { useCityStore } from '@/src/store/city';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

function statusLabel(t: TFunction, status?: string): { text: string; color: string } {
  switch (status) {
    case 'ready': return { text: t('cityPicker.status.ready'), color: '#067647' };
    case 'discovering': return { text: t('cityPicker.status.discovering'), color: GOLD };
    case 'pending': return { text: t('cityPicker.status.queued'), color: '#6B7280' };
    case 'failed': return { text: t('cityPicker.status.failed'), color: '#B42318' };
    default: return { text: t('cityPicker.status.discover'), color: NAVY };
  }
}

export default function CityPickerScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const dark = useColorScheme() === 'dark';
  const { cityName: currentCity, setCity, clearCity } = useCityStore();

  const [query, setQuery] = React.useState('');
  const [results, setResults] = React.useState<CityResult[]>([]);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [discovering, setDiscovering] = React.useState<string | null>(null);
  const debounceRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  const handleSearch = (text: string) => {
    setQuery(text);
    setError(null);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    if (!text.trim()) { setResults([]); return; }
    debounceRef.current = setTimeout(async () => {
      setLoading(true);
      try {
        const cities = await searchCities(text);
        setResults(cities);
      } catch {
        setError(t('cityPicker.searchFailed'));
      } finally {
        setLoading(false);
      }
    }, 400);
  };

  const handleSelect = (city: CityResult) => {
    if (!city.isKnown || city.status !== 'ready') {
      handleDiscover(city);
      return;
    }
    setCity(city.id, city.name);
    router.back();
  };

  const handleDiscover = async (city: CityResult) => {
    setDiscovering(city.name);
    setError(null);
    try {
      const result = await discoverCity({ name: city.name, lat: city.centerLat, lng: city.centerLng, country: city.country });
      setCity(result.id, city.name);
      router.back();
    } catch (e: any) {
      setError(e.message || t('cityPicker.discoveryFailed'));
    } finally {
      setDiscovering(null);
    }
  };

  const handleClearCity = () => {
    clearCity();
    router.back();
  };

  return (
    <View style={{ flex: 1, backgroundColor: dark ? '#0A0F1E' : '#F4F5F9' }}>
      <SafeAreaView style={{ backgroundColor: NAVY }}>
        <View style={styles.header}>
          <Pressable onPress={() => router.back()} style={({ pressed }) => pressed && { opacity: 0.7 }}>
            <ThemedText style={styles.cancelBtn} lightColor="rgba(255,255,255,0.7)" darkColor="rgba(255,255,255,0.7)">
              {t('common.cancel')}
            </ThemedText>
          </Pressable>
          <ThemedText style={styles.headerTitle} lightColor="#fff" darkColor="#fff">{t('cityPicker.title')}</ThemedText>
          <View style={{ width: 56 }} />
        </View>
        <View style={styles.searchRow}>
          <TextInput
            value={query}
            onChangeText={handleSearch}
            placeholder={t('cityPicker.searchPlaceholder')}
            placeholderTextColor="rgba(255,255,255,0.4)"
            autoFocus
            autoCapitalize="words"
            autoCorrect={false}
            style={styles.searchInput}
          />
        </View>
      </SafeAreaView>

      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.content}>

        {/* Current city row */}
        {currentCity && (
          <ThemedView style={styles.section}>
            <ThemedText style={styles.sectionLabel}>{t('cityPicker.currentlyExploring')}</ThemedText>
            <View style={styles.currentRow}>
              <View style={styles.currentDot} />
              <ThemedText style={styles.currentCity}>{currentCity}</ThemedText>
              <Pressable onPress={handleClearCity} style={({ pressed }) => [styles.clearBtn, pressed && { opacity: 0.7 }]}>
                <ThemedText style={styles.clearBtnText}>{t('common.showAll')}</ThemedText>
              </Pressable>
            </View>
          </ThemedView>
        )}

        {/* Search results */}
        {loading && (
          <View style={styles.centered}>
            <ActivityIndicator color={NAVY} />
          </View>
        )}

        {error ? (
          <View style={styles.errorBox}>
            <ThemedText style={styles.errorText}>{error}</ThemedText>
          </View>
        ) : null}

        {!loading && results.length > 0 && (
          <ThemedView style={styles.section}>
            <ThemedText style={styles.sectionLabel}>{t('cityPicker.results')}</ThemedText>
            {results.map((city, idx) => {
              const isDiscovering = discovering === city.name;
              const badge = statusLabel(t, city.status);
              const isReady = city.isKnown && city.status === 'ready';
              return (
                <Pressable
                  key={city.id ?? `geocoded-${idx}-${city.centerLat}`}
                  onPress={() => handleSelect(city)}
                  disabled={isDiscovering}
                  style={({ pressed }) => [styles.cityRow, pressed && { opacity: 0.75 }]}>
                  <View style={styles.cityInfo}>
                    <ThemedText style={styles.cityName}>{city.name}</ThemedText>
                    {city.country ? (
                      <ThemedText style={styles.countryName}>{city.country}</ThemedText>
                    ) : null}
                    {city.isKnown && city.placeCount ? (
                      <ThemedText style={styles.placeCount}>{t('cityPicker.placeCount', { count: city.placeCount })}</ThemedText>
                    ) : null}
                  </View>
                  {isDiscovering ? (
                    <ActivityIndicator size="small" color={GOLD} />
                  ) : (
                    <View style={[styles.badge, isReady ? styles.badgeReady : styles.badgeDiscover]}>
                      <ThemedText style={[styles.badgeText, { color: isReady ? badge.color : '#fff' }]}>
                        {isReady ? badge.text : t('cityPicker.status.discover')}
                      </ThemedText>
                    </View>
                  )}
                </Pressable>
              );
            })}
          </ThemedView>
        )}

        {!loading && !error && query.trim() && results.length === 0 && (
          <View style={styles.centered}>
            <ThemedText style={styles.noResults}>{t('cityPicker.noResults', { query })}</ThemedText>
            <ThemedText style={styles.noResultsSub}>{t('cityPicker.noResultsSub')}</ThemedText>
          </View>
        )}

        {!query.trim() && (
          <View style={styles.hint}>
            <ThemedText style={styles.hintTitle}>{t('cityPicker.hintTitle')}</ThemedText>
            <ThemedText style={styles.hintBody}>{t('cityPicker.hintBody')}</ThemedText>
          </View>
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
    paddingBottom: 12,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '700',
  },
  cancelBtn: {
    fontSize: 16,
    width: 56,
  },
  searchRow: {
    paddingHorizontal: 16,
    paddingBottom: 14,
  },
  searchInput: {
    backgroundColor: 'rgba(255,255,255,0.12)',
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
    color: '#fff',
  },
  content: {
    padding: 16,
    gap: 16,
    paddingBottom: 40,
  },
  section: {
    borderRadius: 18,
    padding: 16,
    gap: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.15)',
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: '600',
    opacity: 0.45,
    textTransform: 'uppercase',
    letterSpacing: 0.8,
  },
  currentRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  currentDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: GOLD,
  },
  currentCity: {
    flex: 1,
    fontSize: 17,
    fontWeight: '600',
  },
  clearBtn: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
  },
  clearBtnText: {
    fontSize: 13,
    fontWeight: '600',
    opacity: 0.7,
  },
  cityRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 4,
  },
  cityInfo: {
    flex: 1,
    gap: 2,
  },
  cityName: {
    fontSize: 16,
    fontWeight: '600',
  },
  countryName: {
    fontSize: 13,
    opacity: 0.5,
  },
  placeCount: {
    fontSize: 12,
    opacity: 0.4,
  },
  badge: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
    borderWidth: 1,
  },
  badgeReady: {
    backgroundColor: 'rgba(18,183,106,0.08)',
    borderColor: 'rgba(18,183,106,0.2)',
  },
  badgeDiscover: {
    backgroundColor: NAVY,
    borderColor: NAVY,
  },
  badgeText: {
    fontSize: 13,
    fontWeight: '700',
  },
  centered: {
    paddingVertical: 32,
    alignItems: 'center',
    gap: 8,
  },
  errorBox: {
    backgroundColor: 'rgba(180,35,24,0.08)',
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: 'rgba(180,35,24,0.2)',
  },
  errorText: {
    color: '#B42318',
    fontSize: 14,
    lineHeight: 20,
  },
  noResults: {
    fontSize: 16,
    fontWeight: '600',
    opacity: 0.6,
  },
  noResultsSub: {
    fontSize: 14,
    opacity: 0.4,
    textAlign: 'center',
  },
  hint: {
    paddingTop: 32,
    paddingHorizontal: 8,
    gap: 10,
    alignItems: 'center',
  },
  hintTitle: {
    fontSize: 17,
    fontWeight: '700',
    opacity: 0.6,
  },
  hintBody: {
    fontSize: 14,
    opacity: 0.4,
    textAlign: 'center',
    lineHeight: 22,
  },
});
