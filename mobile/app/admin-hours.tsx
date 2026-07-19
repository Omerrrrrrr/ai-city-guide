import { Stack } from 'expo-router';
import React from 'react';
import { Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import type { TFunction } from 'i18next';
import { useTranslation } from 'react-i18next';

import { AdminGate } from '@/components/admin-gate';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { fetchPlaces } from '@/src/api/places';
import {
  fetchGoogleHoursPreview,
  type GoogleHoursPreview,
  updatePlaceHours,
} from '@/src/api/place-hours';
import type {
  OpeningHoursData,
  OpeningHoursDayKey,
  OpeningHoursRange,
  Place,
} from '@/src/data/places';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';

const DAY_FIELDS: { key: OpeningHoursDayKey; labelKey: string }[] = [
  { key: '1', labelKey: 'placeHours.weekdayShort.mon' },
  { key: '2', labelKey: 'placeHours.weekdayShort.tue' },
  { key: '3', labelKey: 'placeHours.weekdayShort.wed' },
  { key: '4', labelKey: 'placeHours.weekdayShort.thu' },
  { key: '5', labelKey: 'placeHours.weekdayShort.fri' },
  { key: '6', labelKey: 'placeHours.weekdayShort.sat' },
  { key: '0', labelKey: 'placeHours.weekdayShort.sun' },
];

type HoursFormState = {
  hoursVerified: boolean;
  alwaysOpen: boolean;
  temporarilyClosed: boolean;
  hoursSourceUrl: string;
  hoursNote: string;
  dayInputs: Record<OpeningHoursDayKey, string>;
};

function getErrorMessage(t: TFunction, error: unknown) {
  if (error instanceof Error) return error.message;
  return t('adminHours.errorSavingFallback') as string;
}

function serializeRanges(ranges: OpeningHoursRange[] | undefined) {
  if (!ranges?.length) return '';
  return ranges.map((range) => `${range.start}-${range.end}`).join(', ');
}

function createEmptyDayInputs(): Record<OpeningHoursDayKey, string> {
  return {
    '0': '',
    '1': '',
    '2': '',
    '3': '',
    '4': '',
    '5': '',
    '6': '',
  };
}

function createEmptyDayRanges(): Record<OpeningHoursDayKey, OpeningHoursRange[]> {
  return {
    '0': [],
    '1': [],
    '2': [],
    '3': [],
    '4': [],
    '5': [],
    '6': [],
  };
}

function createDayInputsFromOpeningHours(openingHours?: OpeningHoursData) {
  const dayInputs = createEmptyDayInputs();

  if (openingHours?.mode === 'scheduled') {
    for (const field of DAY_FIELDS) {
      dayInputs[field.key] = serializeRanges(openingHours.days[field.key]);
    }
  }

  return dayInputs;
}

function createFormState(place: Place): HoursFormState {
  const openingHours = place.visitInfo?.openingHours;

  return {
    hoursVerified: place.visitInfo?.hoursVerified ?? false,
    alwaysOpen: openingHours?.mode === 'always-open',
    temporarilyClosed: place.visitInfo?.temporarilyClosed ?? false,
    hoursSourceUrl: place.visitInfo?.hoursSourceUrl ?? '',
    hoursNote: place.visitInfo?.hoursNote ?? '',
    dayInputs: createDayInputsFromOpeningHours(openingHours),
  };
}

function createFormStateWithPreview(
  previous: HoursFormState | undefined,
  preview: GoogleHoursPreview
): HoursFormState {
  const hasOpeningHours = Boolean(preview.openingHours);
  const nextAlwaysOpen =
    preview.openingHours?.mode === 'always-open'
      ? true
      : preview.openingHours?.mode === 'scheduled'
        ? false
        : previous?.alwaysOpen ?? false;

  return {
    hoursVerified: true,
    alwaysOpen: nextAlwaysOpen,
    temporarilyClosed: preview.temporarilyClosed,
    hoursSourceUrl: preview.googleMapsUri ?? preview.websiteUri ?? previous?.hoursSourceUrl ?? '',
    hoursNote: preview.hoursNote,
    dayInputs: hasOpeningHours
      ? createDayInputsFromOpeningHours(preview.openingHours)
      : previous?.dayInputs ?? createEmptyDayInputs(),
  };
}

function toMinutes(time: string) {
  const [hour, minute] = time.split(':').map(Number);
  return hour * 60 + minute;
}

function parseDayInput(t: TFunction, label: string, value: string): OpeningHoursRange[] {
  const trimmed = value.trim();
  if (!trimmed || trimmed.toLowerCase() === 'closed') return [];

  const ranges = trimmed
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const match = entry.match(/^([01]\d|2[0-3]):([0-5]\d)\s*-\s*([01]\d|2[0-3]):([0-5]\d)$/);
      if (!match) {
        throw new Error(t('adminHours.validation.formatError', { label }) as string);
      }

      const start = `${match[1]}:${match[2]}`;
      const end = `${match[3]}:${match[4]}`;

      if (toMinutes(end) <= toMinutes(start)) {
        throw new Error(t('adminHours.validation.endAfterStart', { label }) as string);
      }

      return { start, end };
    })
    .sort((left, right) => left.start.localeCompare(right.start));

  for (let index = 0; index < ranges.length - 1; index += 1) {
    if (toMinutes(ranges[index].end) > toMinutes(ranges[index + 1].start)) {
      throw new Error(t('adminHours.validation.noOverlap', { label }) as string);
    }
  }

  return ranges;
}

function formatCheckedAt(value?: string) {
  if (!value) return null;
  return new Date(value).toLocaleDateString('en-GB');
}

function formatBusinessStatus(t: TFunction, status?: string) {
  if (!status) return t('adminHours.noBusinessStatus') as string;

  return status
    .toLowerCase()
    .split('_')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

export default function AdminHoursScreen() {
  return (
    <AdminGate>
      <AdminHoursScreenContent />
    </AdminGate>
  );
}

function AdminHoursScreenContent() {
  const { t } = useTranslation();
  const [places, setPlaces] = React.useState<Place[]>([]);
  const [search, setSearch] = React.useState('');
  const [expandedPlaceId, setExpandedPlaceId] = React.useState<string | null>(null);
  const [forms, setForms] = React.useState<Record<string, HoursFormState>>({});
  const [googlePreviews, setGooglePreviews] = React.useState<Record<string, GoogleHoursPreview[]>>({});
  const [isLoading, setIsLoading] = React.useState(true);
  const [activePlaceId, setActivePlaceId] = React.useState<string | null>(null);
  const [previewLoadingPlaceId, setPreviewLoadingPlaceId] = React.useState<string | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [info, setInfo] = React.useState<string | null>(null);

  const loadPlaces = React.useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const next = await fetchPlaces();
      setPlaces(next);
    } catch (nextError) {
      setError(getErrorMessage(t, nextError));
    } finally {
      setIsLoading(false);
    }
  }, [t]);

  React.useEffect(() => {
    void loadPlaces();
  }, [loadPlaces]);

  const filteredPlaces = React.useMemo(() => {
    const query = search.trim().toLowerCase();
    const source = [...places].sort((left, right) => left.name.localeCompare(right.name));

    if (!query) return source;

    return source.filter(
      (place) => place.name.toLowerCase().includes(query) || place.id.toLowerCase().includes(query)
    );
  }, [places, search]);

  function ensureForm(place: Place) {
    setForms((state) => {
      if (state[place.id]) return state;
      return {
        ...state,
        [place.id]: createFormState(place),
      };
    });
  }

  function updateForm(placeId: string, updater: (state: HoursFormState) => HoursFormState) {
    setForms((state) => ({
      ...state,
      [placeId]: updater(state[placeId]),
    }));
  }

  async function handleFetchGooglePreview(place: Place) {
    ensureForm(place);
    setPreviewLoadingPlaceId(place.id);
    setError(null);
    setInfo(null);

    try {
      const response = await fetchGoogleHoursPreview(place.id);
      setGooglePreviews((state) => ({
        ...state,
        [place.id]: response.previews,
      }));

      if (response.previews.length > 0) {
        setInfo(t('adminHours.info.loadedPreviews', { count: response.previews.length, name: place.name }));
      } else {
        setInfo(t('adminHours.info.noPreviewsFound', { name: place.name }));
      }
    } catch (nextError) {
      setError(getErrorMessage(t, nextError));
    } finally {
      setPreviewLoadingPlaceId(null);
    }
  }

  function handleUseGooglePreview(place: Place, preview: GoogleHoursPreview) {
    setForms((state) => ({
      ...state,
      [place.id]: createFormStateWithPreview(state[place.id] ?? createFormState(place), preview),
    }));
    setError(null);
    setInfo(t('adminHours.info.filledFromPreview', { name: place.name }));
  }

  async function handleSave(place: Place) {
    const form = forms[place.id];
    if (!form) return;

    setActivePlaceId(place.id);
    setError(null);
    setInfo(null);

    try {
      const days = DAY_FIELDS.reduce<Record<OpeningHoursDayKey, OpeningHoursRange[]>>(
        (accumulator, field) => {
          accumulator[field.key] = form.alwaysOpen ? [] : parseDayInput(t, t(field.labelKey), form.dayInputs[field.key]);
          return accumulator;
        },
        createEmptyDayRanges()
      );

      const response = await updatePlaceHours(place.id, {
        hoursVerified: form.hoursVerified,
        hoursSourceUrl: form.hoursSourceUrl.trim() || undefined,
        hoursNote: form.hoursNote.trim() || undefined,
        temporarilyClosed: form.temporarilyClosed,
        openingHours: {
          timezone: 'Europe/Oslo',
          mode: form.alwaysOpen ? 'always-open' : 'scheduled',
          days,
        },
      });

      setPlaces((state) => state.map((entry) => (entry.id === place.id ? response.place : entry)));
      setForms((state) => ({
        ...state,
        [place.id]: createFormState(response.place),
      }));
      setInfo(t('adminHours.info.savedHours', { name: response.place.name }));
    } catch (nextError) {
      setError(getErrorMessage(t, nextError));
    } finally {
      setActivePlaceId(null);
    }
  }

  return (
    <>
      <Stack.Screen options={{ title: t('adminHours.hero.title') }} />
      <ScrollView contentContainerStyle={styles.container}>
        <ThemedView style={styles.hero}>
          <ThemedText type="title">{t('adminHours.hero.title')}</ThemedText>
          <ThemedText style={styles.body}>{t('adminHours.hero.body1')}</ThemedText>
          <ThemedText style={styles.body}>{t('adminHours.hero.body2')}</ThemedText>
        </ThemedView>

        <ThemedView style={styles.card}>
          <ThemedText type="subtitle">{t('adminHours.findPlace')}</ThemedText>
          <TextInput
            value={search}
            onChangeText={setSearch}
            placeholder={t('adminHours.searchPlaceholder')}
            placeholderTextColor="rgba(127,127,127,0.7)"
            autoCapitalize="none"
            autoCorrect={false}
            style={styles.input}
          />
          <Pressable
            onPress={() => void loadPlaces()}
            style={({ pressed }) => [styles.button, pressed && styles.buttonPressed]}>
            <ThemedText style={styles.buttonText}>{t('adminHours.refreshPlaces')}</ThemedText>
          </Pressable>
          {info ? <ThemedText style={styles.successText}>{info}</ThemedText> : null}
          {error ? <ThemedText style={styles.errorText}>{error}</ThemedText> : null}
        </ThemedView>

        {isLoading ? <ThemedText style={styles.body}>{t('adminHours.loadingPlaces')}</ThemedText> : null}

        {filteredPlaces.map((place) => {
          const status = getPlaceOpenStatus(place, t);
          const isExpanded = expandedPlaceId === place.id;
          const form = forms[place.id] ?? createFormState(place);
          const previews = googlePreviews[place.id];
          const hasLoadedGooglePreview = Object.prototype.hasOwnProperty.call(googlePreviews, place.id);

          return (
            <ThemedView key={place.id} style={styles.card}>
              <View style={styles.cardHeader}>
                <View style={styles.headerText}>
                  <ThemedText type="subtitle">{place.name}</ThemedText>
                  <ThemedText style={styles.meta}>{place.id}</ThemedText>
                  <ThemedText style={styles.meta}>
                    {status.shortLabel} · {status.verified ? t('adminHours.verifiedHoursLabel') : t('adminHours.estimatedHoursLabel')}
                  </ThemedText>
                  {place.visitInfo?.hoursLastCheckedAt ? (
                    <ThemedText style={styles.meta}>
                      {t('adminHours.lastChecked', { date: formatCheckedAt(place.visitInfo.hoursLastCheckedAt) })}
                    </ThemedText>
                  ) : null}
                </View>
                <Pressable
                  onPress={() => {
                    ensureForm(place);
                    setExpandedPlaceId(isExpanded ? null : place.id);
                  }}
                  style={({ pressed }) => [styles.buttonSmall, pressed && styles.buttonPressed]}>
                  <ThemedText style={styles.buttonText}>{isExpanded ? t('adminHours.close') : t('adminHours.editHours')}</ThemedText>
                </Pressable>
              </View>

              {isExpanded ? (
                <View style={styles.formBlock}>
                  <View style={styles.toggleRow}>
                    <Pressable
                      onPress={() =>
                        updateForm(place.id, (state) => ({ ...state, hoursVerified: !state.hoursVerified }))
                      }
                      style={({ pressed }) => [
                        styles.toggleChip,
                        form.hoursVerified && styles.toggleChipSelected,
                        pressed && styles.buttonPressed,
                      ]}>
                      <ThemedText style={styles.filterText}>{t('adminHours.toggles.verified')}</ThemedText>
                    </Pressable>
                    <Pressable
                      onPress={() =>
                        updateForm(place.id, (state) => ({ ...state, alwaysOpen: !state.alwaysOpen }))
                      }
                      style={({ pressed }) => [
                        styles.toggleChip,
                        form.alwaysOpen && styles.toggleChipSelected,
                        pressed && styles.buttonPressed,
                      ]}>
                      <ThemedText style={styles.filterText}>{t('adminHours.toggles.alwaysOpen')}</ThemedText>
                    </Pressable>
                    <Pressable
                      onPress={() =>
                        updateForm(place.id, (state) => ({
                          ...state,
                          temporarilyClosed: !state.temporarilyClosed,
                        }))
                      }
                      style={({ pressed }) => [
                        styles.toggleChip,
                        form.temporarilyClosed && styles.toggleChipDanger,
                        pressed && styles.buttonPressed,
                      ]}>
                      <ThemedText style={styles.filterText}>{t('adminHours.toggles.temporarilyClosed')}</ThemedText>
                    </Pressable>
                  </View>

                  <TextInput
                    value={form.hoursSourceUrl}
                    onChangeText={(value) =>
                      updateForm(place.id, (state) => ({ ...state, hoursSourceUrl: value }))
                    }
                    placeholder={t('adminHours.sourceUrlPlaceholder')}
                    placeholderTextColor="rgba(127,127,127,0.7)"
                    autoCapitalize="none"
                    autoCorrect={false}
                    style={styles.input}
                  />

                  <TextInput
                    value={form.hoursNote}
                    onChangeText={(value) =>
                      updateForm(place.id, (state) => ({ ...state, hoursNote: value }))
                    }
                    placeholder={t('adminHours.notePlaceholder')}
                    placeholderTextColor="rgba(127,127,127,0.7)"
                    multiline
                    style={[styles.input, styles.noteInput]}
                  />

                  {!form.alwaysOpen ? (
                    <View style={styles.dayList}>
                      {DAY_FIELDS.map((field) => (
                        <View key={field.key} style={styles.dayRow}>
                          <ThemedText style={styles.dayLabel}>{t(field.labelKey)}</ThemedText>
                          <TextInput
                            value={form.dayInputs[field.key]}
                            onChangeText={(value) =>
                              updateForm(place.id, (state) => ({
                                ...state,
                                dayInputs: { ...state.dayInputs, [field.key]: value },
                              }))
                            }
                            placeholder={t('adminHours.dayInputPlaceholder')}
                            placeholderTextColor="rgba(127,127,127,0.7)"
                            autoCapitalize="none"
                            autoCorrect={false}
                            style={styles.dayInput}
                          />
                        </View>
                      ))}
                    </View>
                  ) : null}

                  <ThemedText style={styles.meta}>{t('adminHours.formatHint')}</ThemedText>

                  <View style={styles.actionsRow}>
                    <Pressable
                      onPress={() => void handleFetchGooglePreview(place)}
                      disabled={previewLoadingPlaceId === place.id}
                      style={({ pressed }) => [
                        styles.buttonSecondary,
                        previewLoadingPlaceId === place.id && styles.buttonDisabled,
                        pressed && previewLoadingPlaceId !== place.id && styles.buttonPressed,
                      ]}>
                      <ThemedText style={styles.buttonText}>
                        {previewLoadingPlaceId === place.id ? t('adminHours.loadingGoogle') : t('adminHours.fetchGooglePreview')}
                      </ThemedText>
                    </Pressable>

                    <Pressable
                      onPress={() => void handleSave(place)}
                      disabled={activePlaceId === place.id}
                      style={({ pressed }) => [
                        styles.buttonPrimary,
                        activePlaceId === place.id && styles.buttonDisabled,
                        pressed && activePlaceId !== place.id && styles.buttonPressed,
                      ]}>
                      <ThemedText style={styles.buttonText}>
                        {activePlaceId === place.id ? t('common.saving') : t('adminHours.saveHours')}
                      </ThemedText>
                    </Pressable>
                  </View>

                  {hasLoadedGooglePreview ? (
                    <View style={styles.previewSection}>
                      <ThemedText type="subtitle">{t('adminHours.googlePreviewTitle')}</ThemedText>
                      <ThemedText style={styles.meta}>{t('adminHours.googlePreviewBody')}</ThemedText>

                      {previews?.length ? (
                        previews.map((preview) => (
                          <View key={preview.googlePlaceId} style={styles.previewCard}>
                            <View style={styles.previewHeader}>
                              <View style={styles.previewHeaderText}>
                                <ThemedText style={styles.previewTitle}>{preview.displayName}</ThemedText>
                                {preview.formattedAddress ? (
                                  <ThemedText style={styles.meta}>{preview.formattedAddress}</ThemedText>
                                ) : null}
                              </View>
                              <ThemedText style={styles.previewScore}>
                                {t('adminHours.ptsSuffix', { points: Math.round(preview.confidence) })}
                              </ThemedText>
                            </View>

                            <ThemedText style={styles.meta}>
                              {formatBusinessStatus(t, preview.businessStatus)} ·{' '}
                              {preview.temporarilyClosed ? t('adminHours.temporarilyClosedStatus') : t('adminHours.activeStatus')}
                            </ThemedText>
                            <ThemedText style={styles.meta}>{preview.matchReason}</ThemedText>

                            {preview.weekdayDescriptions.length ? (
                              <View style={styles.weekdayList}>
                                {preview.weekdayDescriptions.map((line) => (
                                  <ThemedText key={`${preview.googlePlaceId}:${line}`} style={styles.meta}>
                                    {line}
                                  </ThemedText>
                                ))}
                              </View>
                            ) : (
                              <ThemedText style={styles.meta}>{t('adminHours.noWeekdayDescriptions')}</ThemedText>
                            )}

                            <Pressable
                              onPress={() => handleUseGooglePreview(place, preview)}
                              style={({ pressed }) => [
                                styles.buttonSmall,
                                styles.previewUseButton,
                                pressed && styles.buttonPressed,
                              ]}>
                              <ThemedText style={styles.buttonText}>{t('adminHours.useThisPreview')}</ThemedText>
                            </Pressable>
                          </View>
                        ))
                      ) : (
                        <ThemedText style={styles.meta}>{t('adminHours.noGoogleCandidates')}</ThemedText>
                      )}
                    </View>
                  ) : null}
                </View>
              ) : null}
            </ThemedView>
          );
        })}
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 16,
    gap: 12,
  },
  hero: {
    gap: 8,
  },
  card: {
    gap: 10,
    padding: 16,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.18)',
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  headerText: {
    flex: 1,
    gap: 4,
  },
  body: {
    opacity: 0.8,
    lineHeight: 22,
  },
  meta: {
    fontSize: 13,
    lineHeight: 18,
    opacity: 0.72,
  },
  formBlock: {
    gap: 10,
  },
  toggleRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  toggleChip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
  },
  toggleChipSelected: {
    backgroundColor: 'rgba(18, 183, 106, 0.1)',
    borderColor: 'rgba(18, 183, 106, 0.24)',
  },
  toggleChipDanger: {
    backgroundColor: 'rgba(217, 45, 32, 0.08)',
    borderColor: 'rgba(217, 45, 32, 0.18)',
  },
  filterText: {
    fontSize: 14,
    lineHeight: 18,
  },
  input: {
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 15,
  },
  noteInput: {
    minHeight: 88,
    textAlignVertical: 'top',
  },
  dayList: {
    gap: 8,
  },
  dayRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  dayLabel: {
    width: 38,
    fontSize: 14,
    lineHeight: 18,
    opacity: 0.72,
  },
  dayInput: {
    flex: 1,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.25)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
  },
  button: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.24)',
  },
  actionsRow: {
    flexDirection: 'row',
    gap: 10,
  },
  buttonPrimary: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(24, 144, 255, 0.3)',
    backgroundColor: 'rgba(24, 144, 255, 0.08)',
  },
  buttonSecondary: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.24)',
  },
  buttonSmall: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
    paddingVertical: 9,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.24)',
  },
  buttonText: {
    fontSize: 14,
    lineHeight: 18,
  },
  buttonDisabled: {
    opacity: 0.45,
  },
  buttonPressed: {
    opacity: 0.72,
  },
  previewSection: {
    gap: 10,
    marginTop: 4,
    paddingTop: 4,
  },
  previewCard: {
    gap: 8,
    padding: 12,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.18)',
    backgroundColor: 'rgba(127,127,127,0.04)',
  },
  previewHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 10,
  },
  previewHeaderText: {
    flex: 1,
    gap: 4,
  },
  previewTitle: {
    fontSize: 15,
    lineHeight: 20,
  },
  previewScore: {
    fontSize: 12,
    lineHeight: 16,
    opacity: 0.72,
  },
  weekdayList: {
    gap: 4,
  },
  previewUseButton: {
    alignSelf: 'flex-start',
    paddingHorizontal: 12,
  },
  successText: {
    color: '#067647',
    lineHeight: 20,
  },
  errorText: {
    color: '#B42318',
    lineHeight: 20,
  },
});
