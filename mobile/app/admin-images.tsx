import { Image } from 'expo-image';
import { Stack } from 'expo-router';
import React from 'react';
import { Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';

import { AdminGate } from '@/components/admin-gate';
import { ExternalLink } from '@/components/external-link';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import {
  applyImageCandidate,
  approveImageCandidate,
  discoverImageCandidates,
  fetchImageCandidates,
  rejectImageCandidate,
  reassignImageCandidate,
} from '@/src/api/image-candidates';
import { fetchPlaces } from '@/src/api/places';
import type { ImageCandidate, ImageCandidateStatus } from '@/src/data/image-candidates';
import type { Place } from '@/src/data/places';

const FILTERS: { label: string; value: ImageCandidateStatus | 'all' }[] = [
  { label: 'Pending', value: 'pending' },
  { label: 'Approved', value: 'approved' },
  { label: 'Applied', value: 'applied' },
  { label: 'Rejected', value: 'rejected' },
  { label: 'All', value: 'all' },
];

function getErrorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  return 'Something went wrong while loading image candidates.';
}

export default function AdminImagesScreen() {
  return (
    <AdminGate>
      <AdminImagesScreenContent />
    </AdminGate>
  );
}

function AdminImagesScreenContent() {
  const [statusFilter, setStatusFilter] = React.useState<ImageCandidateStatus | 'all'>('pending');
  const [candidates, setCandidates] = React.useState<ImageCandidate[]>([]);
  const [error, setError] = React.useState<string | null>(null);
  const [info, setInfo] = React.useState<string | null>(null);
  const [isLoading, setIsLoading] = React.useState(true);
  const [isDiscovering, setIsDiscovering] = React.useState(false);
  const [activeCandidateId, setActiveCandidateId] = React.useState<string | null>(null);
  const [allPlaces, setAllPlaces] = React.useState<Place[]>([]);
  const [candidateQuery, setCandidateQuery] = React.useState('');
  const [discoverQuery, setDiscoverQuery] = React.useState('');
  const [selectedDiscoverPlace, setSelectedDiscoverPlace] = React.useState<Place | null>(null);
  const [reassignQueries, setReassignQueries] = React.useState<Record<string, string>>({});
  const [selectedPlacesByCandidate, setSelectedPlacesByCandidate] = React.useState<
    Record<string, Place | undefined>
  >({});

  const loadCandidates = React.useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const next = await fetchImageCandidates({
        status: statusFilter === 'all' ? undefined : statusFilter,
      });
      setCandidates(next);
    } catch (nextError) {
      setError(getErrorMessage(nextError));
    } finally {
      setIsLoading(false);
    }
  }, [statusFilter]);

  React.useEffect(() => {
    void loadCandidates();
  }, [loadCandidates]);

  React.useEffect(() => {
    let cancelled = false;

    async function loadPlaces() {
      try {
        const next = await fetchPlaces();
        if (!cancelled) {
          setAllPlaces(next);
        }
      } catch {}
    }

    void loadPlaces();

    return () => {
      cancelled = true;
    };
  }, []);

  const coverage = React.useMemo(() => {
    const totalPlaces = allPlaces.length;
    const verifiedPlaces = allPlaces.filter((place) => place.image.verified).length;
    const missingPlaces = Math.max(0, totalPlaces - verifiedPlaces);
    const pendingStrong = candidates.filter(
      (candidate) => candidate.status === 'pending' && candidate.confidence >= 70
    ).length;

    return {
      totalPlaces,
      verifiedPlaces,
      missingPlaces,
      pendingStrong,
    };
  }, [allPlaces, candidates]);

  const discoverSuggestions = React.useMemo(() => {
    const query = discoverQuery.trim().toLowerCase();
    if (query.length < 2) return [];

    return allPlaces
      .filter(
        (place) =>
          place.name.toLowerCase().includes(query) || place.id.toLowerCase().includes(query)
      )
      .slice(0, 5);
  }, [allPlaces, discoverQuery]);

  const visibleCandidates = React.useMemo(() => {
    const query = candidateQuery.trim().toLowerCase();
    if (!query) return candidates;

    return candidates.filter(
      (candidate) =>
        candidate.placeName.toLowerCase().includes(query) ||
        candidate.placeId.toLowerCase().includes(query) ||
        candidate.pageTitle.toLowerCase().includes(query)
    );
  }, [candidateQuery, candidates]);

  async function handleDiscoverMissing() {
    setIsDiscovering(true);
    setError(null);
    setInfo(null);

    try {
      const result = await discoverImageCandidates({ limit: 4 });
      setInfo(
        `Discovered ${result.discoveredCandidates} candidates across ${result.discoveredPlaces} places.`
      );
      await loadCandidates();
    } catch (nextError) {
      setError(getErrorMessage(nextError));
    } finally {
      setIsDiscovering(false);
    }
  }

  async function handleDiscoverSinglePlace() {
    if (!selectedDiscoverPlace) return;

    setIsDiscovering(true);
    setError(null);
    setInfo(null);

    try {
      const result = await discoverImageCandidates({
        placeId: selectedDiscoverPlace.id,
        limit: 6,
        includeVerified: true,
      });
      setInfo(`Discovered ${result.discoveredCandidates} candidates for ${selectedDiscoverPlace.name}.`);
      await loadCandidates();
    } catch (nextError) {
      setError(getErrorMessage(nextError));
    } finally {
      setIsDiscovering(false);
    }
  }

  async function handleApproveAndApply(candidateId: string) {
    setActiveCandidateId(candidateId);
    setError(null);
    setInfo(null);

    try {
      await approveImageCandidate(candidateId);
      await applyImageCandidate(candidateId);
      setInfo('Candidate approved and applied.');
      await loadCandidates();
    } catch (nextError) {
      setError(getErrorMessage(nextError));
    } finally {
      setActiveCandidateId(null);
    }
  }

  async function handleReject(candidateId: string) {
    setActiveCandidateId(candidateId);
    setError(null);
    setInfo(null);

    try {
      await rejectImageCandidate(candidateId);
      setInfo('Candidate rejected.');
      await loadCandidates();
    } catch (nextError) {
      setError(getErrorMessage(nextError));
    } finally {
      setActiveCandidateId(null);
    }
  }

  async function handleReassign(candidateId: string) {
    const selectedPlace = selectedPlacesByCandidate[candidateId];
    if (!selectedPlace) return;

    setActiveCandidateId(candidateId);
    setError(null);
    setInfo(null);

    try {
      await reassignImageCandidate(candidateId, selectedPlace.id);
      setInfo(`Candidate moved to ${selectedPlace.name}.`);
      setReassignQueries((state) => ({ ...state, [candidateId]: '' }));
      setSelectedPlacesByCandidate((state) => ({ ...state, [candidateId]: undefined }));
      await loadCandidates();
    } catch (nextError) {
      setError(getErrorMessage(nextError));
    } finally {
      setActiveCandidateId(null);
    }
  }

  return (
    <>
      <Stack.Screen options={{ title: 'Image Review' }} />
      <ScrollView contentContainerStyle={styles.container}>
        <ThemedView style={styles.hero}>
          <ThemedText type="title">Image Review</ThemedText>
          <ThemedText style={styles.body}>
            Review pending Wikimedia candidates, then approve and apply real photos to places.
          </ThemedText>
        </ThemedView>

        <ThemedView style={styles.card}>
          <ThemedText type="subtitle">Coverage</ThemedText>
          <View style={styles.metricsRow}>
            <View style={styles.metricCard}>
              <ThemedText style={styles.metricValue}>{coverage.totalPlaces}</ThemedText>
              <ThemedText style={styles.meta}>places</ThemedText>
            </View>
            <View style={styles.metricCard}>
              <ThemedText style={styles.metricValue}>{coverage.verifiedPlaces}</ThemedText>
              <ThemedText style={styles.meta}>verified main photos</ThemedText>
            </View>
            <View style={styles.metricCard}>
              <ThemedText style={styles.metricValue}>{coverage.missingPlaces}</ThemedText>
              <ThemedText style={styles.meta}>still missing</ThemedText>
            </View>
          </View>
          <ThemedText style={styles.meta}>
            Strong pending candidates in this filter: {coverage.pendingStrong}
          </ThemedText>
        </ThemedView>

        <ThemedView style={styles.card}>
          <ThemedText type="subtitle">Actions</ThemedText>
          <View style={styles.actionsRow}>
            <Pressable
              onPress={() => void loadCandidates()}
              style={({ pressed }) => [styles.button, pressed && styles.buttonPressed]}>
              <ThemedText style={styles.buttonText}>Refresh</ThemedText>
            </Pressable>
            <Pressable
              onPress={() => void handleDiscoverMissing()}
              disabled={isDiscovering}
              style={({ pressed }) => [
                styles.button,
                isDiscovering && styles.buttonDisabled,
                pressed && !isDiscovering && styles.buttonPressed,
              ]}>
              <ThemedText style={styles.buttonText}>
                {isDiscovering ? 'Discovering…' : 'Discover Missing'}
              </ThemedText>
            </Pressable>
          </View>

          <View style={styles.discoverBlock}>
            <ThemedText type="defaultSemiBold">Discover for One Place</ThemedText>
            <TextInput
              value={discoverQuery}
              onChangeText={(value) => {
                setDiscoverQuery(value);
                setSelectedDiscoverPlace(null);
              }}
              placeholder="Search place name or id…"
              placeholderTextColor="rgba(127,127,127,0.7)"
              autoCapitalize="none"
              autoCorrect={false}
              style={styles.input}
            />
            {selectedDiscoverPlace ? (
              <ThemedText style={styles.meta}>Selected: {selectedDiscoverPlace.name}</ThemedText>
            ) : null}
            {discoverSuggestions.length ? (
              <View style={styles.suggestions}>
                {discoverSuggestions.map((place) => (
                  <Pressable
                    key={place.id}
                    onPress={() => {
                      setSelectedDiscoverPlace(place);
                      setDiscoverQuery(place.name);
                    }}
                    style={({ pressed }) => [styles.suggestionChip, pressed && styles.buttonPressed]}>
                    <ThemedText style={styles.filterText}>{place.name}</ThemedText>
                  </Pressable>
                ))}
              </View>
            ) : null}
            <Pressable
              onPress={() => void handleDiscoverSinglePlace()}
              disabled={isDiscovering || !selectedDiscoverPlace}
              style={({ pressed }) => [
                styles.button,
                styles.secondaryButton,
                (isDiscovering || !selectedDiscoverPlace) && styles.buttonDisabled,
                pressed && !isDiscovering && selectedDiscoverPlace && styles.buttonPressed,
              ]}>
              <ThemedText style={styles.buttonText}>
                {isDiscovering ? 'Discovering…' : 'Discover This Place'}
              </ThemedText>
            </Pressable>
          </View>

          {info ? <ThemedText style={styles.successText}>{info}</ThemedText> : null}
          {error ? <ThemedText style={styles.errorText}>{error}</ThemedText> : null}
        </ThemedView>

        <ThemedView style={styles.filters}>
          {FILTERS.map((filter) => {
            const selected = filter.value === statusFilter;
            return (
              <Pressable
                key={filter.value}
                onPress={() => setStatusFilter(filter.value)}
                style={({ pressed }) => [
                  styles.filterChip,
                  selected && styles.filterChipSelected,
                  pressed && styles.buttonPressed,
                ]}>
                <ThemedText style={styles.filterText}>{filter.label}</ThemedText>
              </Pressable>
            );
          })}
        </ThemedView>

        <ThemedView style={styles.card}>
          <ThemedText type="subtitle">Search Candidates</ThemedText>
          <TextInput
            value={candidateQuery}
            onChangeText={setCandidateQuery}
            placeholder="Filter by place name, id, or photo title…"
            placeholderTextColor="rgba(127,127,127,0.7)"
            autoCapitalize="none"
            autoCorrect={false}
            style={styles.input}
          />
          <ThemedText style={styles.meta}>
            Showing {visibleCandidates.length} of {candidates.length} candidates in this filter.
          </ThemedText>
        </ThemedView>

        {isLoading ? <ThemedText style={styles.body}>Loading candidates…</ThemedText> : null}
        {!isLoading && visibleCandidates.length === 0 ? (
          <ThemedView style={styles.card}>
            <ThemedText style={styles.body}>No candidates in this filter yet.</ThemedText>
          </ThemedView>
        ) : null}

        {visibleCandidates.map((candidate) => {
          const isBusy = activeCandidateId === candidate.id;
          const query = reassignQueries[candidate.id] ?? '';
          const suggestions =
            query.trim().length >= 2
              ? allPlaces
                  .filter(
                    (place) =>
                      place.id !== candidate.placeId &&
                      (place.name.toLowerCase().includes(query.toLowerCase()) ||
                        place.id.toLowerCase().includes(query.toLowerCase()))
                  )
                  .slice(0, 4)
              : [];

          return (
            <ThemedView key={candidate.id} style={styles.card}>
              <View style={styles.cardHeader}>
                <View style={styles.headerText}>
                  <ThemedText type="subtitle">{candidate.placeName}</ThemedText>
                  <ThemedText style={styles.meta}>
                    {candidate.status} · confidence {candidate.confidence} · rank {candidate.rank}
                  </ThemedText>
                </View>
              </View>

              <Image source={{ uri: candidate.imageUrl }} style={styles.preview} contentFit="cover" />

              <ThemedText style={styles.body}>{candidate.pageTitle}</ThemedText>
              {candidate.notes ? <ThemedText style={styles.meta}>{candidate.notes}</ThemedText> : null}
              <ThemedText style={styles.meta}>
                Current image: {candidate.currentPlaceImage.verified ? 'verified' : 'placeholder'}
                {candidate.currentPlaceImage.sourceName
                  ? ` · ${candidate.currentPlaceImage.sourceName}`
                  : ''}
              </ThemedText>
              {candidate.imageLicense ? (
                <ThemedText style={styles.meta}>License: {candidate.imageLicense}</ThemedText>
              ) : null}
              {candidate.imageAttribution ? (
                <ThemedText style={styles.meta}>{candidate.imageAttribution}</ThemedText>
              ) : null}

              <ExternalLink href={candidate.sourceUrl}>
                <ThemedText type="link">Open source page</ThemedText>
              </ExternalLink>

              <View style={styles.reassignBlock}>
                <ThemedText type="defaultSemiBold">Match to Another Place</ThemedText>
                <TextInput
                  value={query}
                  onChangeText={(value) => {
                    setReassignQueries((state) => ({ ...state, [candidate.id]: value }));
                    setSelectedPlacesByCandidate((state) => ({ ...state, [candidate.id]: undefined }));
                  }}
                  placeholder="Search place name or id…"
                  placeholderTextColor="rgba(127,127,127,0.7)"
                  autoCapitalize="none"
                  autoCorrect={false}
                  style={styles.input}
                />
                {selectedPlacesByCandidate[candidate.id] ? (
                  <ThemedText style={styles.meta}>
                    Selected: {selectedPlacesByCandidate[candidate.id]?.name}
                  </ThemedText>
                ) : null}
                {suggestions.length ? (
                  <View style={styles.suggestions}>
                    {suggestions.map((place) => (
                      <Pressable
                        key={place.id}
                        onPress={() => {
                          setSelectedPlacesByCandidate((state) => ({ ...state, [candidate.id]: place }));
                          setReassignQueries((state) => ({ ...state, [candidate.id]: place.name }));
                        }}
                        style={({ pressed }) => [styles.suggestionChip, pressed && styles.buttonPressed]}>
                        <ThemedText style={styles.filterText}>{place.name}</ThemedText>
                      </Pressable>
                    ))}
                  </View>
                ) : null}
                <Pressable
                  onPress={() => void handleReassign(candidate.id)}
                  disabled={isBusy || !selectedPlacesByCandidate[candidate.id]}
                  style={({ pressed }) => [
                    styles.button,
                    isBusy && styles.buttonDisabled,
                    !selectedPlacesByCandidate[candidate.id] && styles.buttonDisabled,
                    pressed &&
                      !isBusy &&
                      Boolean(selectedPlacesByCandidate[candidate.id]) &&
                      styles.buttonPressed,
                  ]}>
                  <ThemedText style={styles.buttonText}>
                    {isBusy ? 'Saving…' : 'Match to Place'}
                  </ThemedText>
                </Pressable>
              </View>

              <View style={styles.actionsRow}>
                <Pressable
                  onPress={() => void handleApproveAndApply(candidate.id)}
                  disabled={isBusy}
                  style={({ pressed }) => [
                    styles.button,
                    styles.primaryButton,
                    isBusy && styles.buttonDisabled,
                    pressed && !isBusy && styles.buttonPressed,
                  ]}>
                  <ThemedText style={styles.primaryButtonText}>
                    {isBusy ? 'Saving…' : 'Approve + Apply'}
                  </ThemedText>
                </Pressable>
                <Pressable
                  onPress={() => void handleReject(candidate.id)}
                  disabled={isBusy}
                  style={({ pressed }) => [
                    styles.button,
                    isBusy && styles.buttonDisabled,
                    pressed && !isBusy && styles.buttonPressed,
                  ]}>
                  <ThemedText style={styles.buttonText}>Reject</ThemedText>
                </Pressable>
              </View>
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
    paddingBottom: 32,
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
    gap: 10,
  },
  headerText: {
    flex: 1,
    gap: 4,
  },
  metricsRow: {
    flexDirection: 'row',
    gap: 10,
  },
  metricCard: {
    flex: 1,
    gap: 4,
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.16)',
    backgroundColor: 'rgba(127,127,127,0.03)',
  },
  metricValue: {
    fontSize: 24,
    lineHeight: 28,
    fontWeight: '700',
  },
  discoverBlock: {
    gap: 8,
    marginTop: 4,
  },
  filters: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  filterChip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
  },
  filterChipSelected: {
    backgroundColor: '#E6F2FF',
    borderColor: '#8CB8E8',
  },
  filterText: {
    fontSize: 14,
    lineHeight: 18,
  },
  preview: {
    width: '100%',
    height: 180,
    borderRadius: 14,
    backgroundColor: 'rgba(127,127,127,0.08)',
  },
  reassignBlock: {
    gap: 8,
  },
  input: {
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.24)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 16,
  },
  suggestions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  suggestionChip: {
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
  },
  actionsRow: {
    flexDirection: 'row',
    gap: 10,
  },
  button: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    paddingHorizontal: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.24)',
  },
  primaryButton: {
    backgroundColor: '#0E2438',
    borderColor: '#0E2438',
  },
  secondaryButton: {
    backgroundColor: 'rgba(14,36,56,0.04)',
  },
  buttonText: {
    fontSize: 14,
    lineHeight: 18,
  },
  primaryButtonText: {
    fontSize: 14,
    lineHeight: 18,
    color: '#FFFFFF',
    fontWeight: '600',
  },
  buttonDisabled: {
    opacity: 0.45,
  },
  buttonPressed: {
    opacity: 0.72,
  },
  body: {
    lineHeight: 22,
    opacity: 0.84,
  },
  meta: {
    fontSize: 13,
    lineHeight: 18,
    opacity: 0.72,
  },
  errorText: {
    color: '#B42318',
    lineHeight: 20,
  },
  successText: {
    color: '#067647',
    lineHeight: 20,
  },
});
