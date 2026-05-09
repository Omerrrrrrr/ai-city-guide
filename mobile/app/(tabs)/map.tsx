import React from 'react';
import { ActivityIndicator, StyleSheet, View, Text, TextInput, Pressable } from 'react-native';
import MapView, { Marker, Callout } from 'react-native-maps';
import { useRouter } from 'expo-router';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { usePlaces } from '@/src/hooks/use-places';
import { createPlace, lookupPlaceInfo, type PlaceLookupResult } from '@/src/api/places';

async function reverseGeocode(latitude: number, longitude: number) {
  try {
    const response = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${latitude}&lon=${longitude}&addressdetails=1`
    );

    if (!response.ok) {
      throw new Error('Reverse geocode failed');
    }

    const data = await response.json();
    const address = data.address ?? {};
    return {
      name: data.name ?? '',
      city:
        address.city || address.town || address.village || address.hamlet || address.county || '',
      country: address.country || '',
      displayName: data.display_name ?? '',
    };
  } catch {
    return {
      name: '',
      city: '',
      country: '',
      displayName: '',
    };
  }
}

export default function MapScreen() {
  const { data: places, error, isLoading, refresh } = usePlaces();
  const router = useRouter();
  const [draftCoordinate, setDraftCoordinate] = React.useState<{ latitude: number; longitude: number } | null>(null);
  const [draftName, setDraftName] = React.useState('');
  const [draftCategory, setDraftCategory] = React.useState('landmark');
  const [draftCity, setDraftCity] = React.useState('');
  const [draftCountry, setDraftCountry] = React.useState('');
  const [draftDescription, setDraftDescription] = React.useState('');
  const [draftError, setDraftError] = React.useState<string | null>(null);
  const [isSavingDraft, setIsSavingDraft] = React.useState(false);
  const [draftHidden, setDraftHidden] = React.useState(false);
  const [lookupInfo, setLookupInfo] = React.useState<PlaceLookupResult | null>(null);
  const [lookupError, setLookupError] = React.useState<string | null>(null);
  const [isLookingUp, setIsLookingUp] = React.useState(false);

  if (isLoading) {
    return (
      <ThemedView style={styles.centered}>
        <ThemedText>Loading map...</ThemedText>
      </ThemedView>
    );
  }

  const handleMapLongPress = async (event: any) => {
    const coordinate = event.nativeEvent.coordinate;
    setDraftCoordinate(coordinate);
    setDraftName('');
    setDraftCity('');
    setDraftCountry('');
    setDraftDescription('');
    setDraftCategory('landmark');
    setDraftError(null);
    setDraftHidden(false);

    const locationInfo = await reverseGeocode(coordinate.latitude, coordinate.longitude);
    setDraftCity((current) => current || locationInfo.city);
    setDraftCountry((current) => current || locationInfo.country);
    setDraftName((current) => current || locationInfo.name || `Place near ${locationInfo.city || 'selected location'}`);
    setDraftDescription((current) =>
      current || locationInfo.displayName || 'Describe this new location.'
    );
  };

  const handleMapPress = async (event: any) => {
    const coordinate = event.nativeEvent.coordinate;
    setLookupInfo(null);
    setLookupError(null);
    setIsLookingUp(true);
    setDraftCoordinate(null);

    try {
      const info = await lookupPlaceInfo(coordinate.latitude, coordinate.longitude);
      setLookupInfo(info);
    } catch (error: any) {
      setLookupError(error?.message ?? 'Lookup failed for this location.');
    } finally {
      setIsLookingUp(false);
    }
  };

  const handleSaveDraft = async () => {
    if (!draftCoordinate) return;

    setDraftError(null);
    setIsSavingDraft(true);

    try {
      await createPlace({
        name: draftName,
        category: draftCategory,
        city: draftCity,
        country: draftCountry || undefined,
        description: draftDescription,
        lat: draftCoordinate.latitude,
        lng: draftCoordinate.longitude,
        tags: [draftCategory, draftCity, draftCountry].filter(Boolean).join(','),
      });
      setDraftCoordinate(null);
      refresh();
    } catch (error: any) {
      setDraftError(error?.message ?? 'Failed to save place');
    } finally {
      setIsSavingDraft(false);
    }
  };

  if (error) {
    return (
      <ThemedView style={styles.centered}>
        <ThemedText style={styles.errorText}>{error}</ThemedText>
      </ThemedView>
    );
  }

  return (
    <View style={styles.container}>
      <MapView
        style={styles.map}
        initialRegion={{
          latitude: 58.146,
          longitude: 7.995,
          latitudeDelta: 0.05,
          longitudeDelta: 0.05,
        }}
        showsUserLocation
        onPress={handleMapPress}
        onLongPress={handleMapLongPress}
      >
        {places?.map((place) => {
          if (!place.location) return null;
          return (
            <Marker
              key={place.id}
              coordinate={{ latitude: place.location.lat, longitude: place.location.lng }}
              onPress={() => router.push(`/place/${place.id}`)}
              onCalloutPress={() => router.push(`/place/${place.id}`)}
            >
              <Callout tooltip={false}>
                <Pressable
                  onPress={() => router.push(`/place/${place.id}`)}
                  style={styles.callout}
                >
                  <Text style={styles.calloutTitle}>{place.name}</Text>
                  <Text style={styles.calloutDesc}>{place.tags.slice(0, 3).join(', ')}</Text>
                  <Text style={styles.calloutAction}>Tap for details ›</Text>
                </Pressable>
              </Callout>
            </Marker>
          );
        })}
        {draftCoordinate ? (
          <Marker
            coordinate={draftCoordinate}
            pinColor="#10B981"
            title="New place"
            onPress={() => setDraftHidden(false)}
          >
            <Callout tooltip={false}>
              <Pressable onPress={() => setDraftHidden(false)} style={styles.callout}>
                <Text style={styles.calloutTitle}>New place draft</Text>
                <Text style={styles.calloutDesc}>
                  {draftHidden ? 'Tap to continue editing.' : 'Fill the form below to save it.'}
                </Text>
              </Pressable>
            </Callout>
          </Marker>
        ) : null}
      </MapView>

      {lookupInfo || lookupError || isLookingUp ? (
        <ThemedView style={styles.lookupPanel}>
          <ThemedText type="subtitle">Location lookup</ThemedText>
          {isLookingUp ? (
            <View style={styles.lookupSpinner}>
              <ActivityIndicator size="small" />
              <ThemedText>Looking up location...</ThemedText>
            </View>
          ) : lookupError ? (
            <ThemedText style={styles.errorText}>{lookupError}</ThemedText>
          ) : lookupInfo ? (
            <>
              <Text style={styles.lookupTitle}>{lookupInfo.name || lookupInfo.displayName || 'Unknown location'}</Text>
              <Text style={styles.lookupMeta}>{[lookupInfo.city, lookupInfo.country].filter(Boolean).join(', ')}</Text>
              <Text style={styles.lookupSummary}>
                {lookupInfo.enrichment.summary ?? lookupInfo.displayName ?? 'No summary available.'}
              </Text>
              <Text style={styles.lookupHint}>
                This is exploration mode: tap anywhere for info. The AI and featured sections reserve only higher-quality recommendations.
              </Text>
            </>
          ) : null}
        </ThemedView>
      ) : null}

      {draftCoordinate && !draftHidden ? (
        <ThemedView style={styles.draftPanel}>
          <ThemedText type="subtitle">Save new place</ThemedText>
          <TextInput
            value={draftName}
            onChangeText={setDraftName}
            placeholder="Place name"
            style={styles.input}
          />
          <TextInput
            value={draftCity}
            onChangeText={setDraftCity}
            placeholder="City"
            style={styles.input}
          />
          <TextInput
            value={draftCountry}
            onChangeText={setDraftCountry}
            placeholder="Country"
            style={styles.input}
          />
          <TextInput
            value={draftCategory}
            onChangeText={setDraftCategory}
            placeholder="Category"
            style={styles.input}
          />
          <TextInput
            value={draftDescription}
            onChangeText={setDraftDescription}
            placeholder="Description"
            style={[styles.input, styles.multilineInput]}
            multiline
          />
          {draftError ? <ThemedText style={styles.errorText}>{draftError}</ThemedText> : null}
          <View style={styles.draftActions}>
            <Pressable
              accessibilityRole="button"
              onPress={() => setDraftCoordinate(null)}
              style={({ pressed }) => [styles.actionButton, pressed && styles.actionButtonPressed]}
            >
              <ThemedText style={styles.actionButtonText}>Cancel</ThemedText>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              onPress={() => setDraftHidden(true)}
              style={({ pressed }) => [styles.actionButton, pressed && styles.actionButtonPressed]}
            >
              <ThemedText style={styles.actionButtonText}>Ask later</ThemedText>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              disabled={!draftName.trim() || !draftCity.trim() || !draftDescription.trim() || isSavingDraft}
              onPress={handleSaveDraft}
              style={({ pressed }) => [
                styles.actionButton,
                styles.saveButton,
                (pressed || isSavingDraft) && styles.actionButtonPressed,
                (!draftName.trim() || !draftCity.trim() || !draftDescription.trim() || isSavingDraft) && styles.actionButtonDisabled,
              ]}
            >
              <ThemedText style={styles.actionButtonText}>
                {isSavingDraft ? 'Saving…' : 'Save place'}
              </ThemedText>
            </Pressable>
          </View>
        </ThemedView>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  map: {
    width: '100%',
    height: '100%',
  },
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  errorText: {
    color: '#B42318',
  },
  callout: {
    padding: 8,
    minWidth: 160,
    alignItems: 'center',
  },
  calloutTitle: {
    fontWeight: 'bold',
    marginBottom: 4,
    color: '#000',
    fontSize: 14,
    textAlign: 'center',
  },
  calloutDesc: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
    textAlign: 'center',
  },
  calloutAction: {
    fontSize: 12,
    color: '#007AFF',
    marginTop: 4,
  },
  draftPanel: {
    position: 'absolute',
    left: 12,
    right: 12,
    bottom: 24,
    padding: 14,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.95)',
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowRadius: 20,
    shadowOffset: { width: 0, height: 8 },
    elevation: 6,
    gap: 10,
  },
  input: {
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.24)',
    borderRadius: 12,
    padding: 10,
    fontSize: 14,
    backgroundColor: '#fff',
  },
  multilineInput: {
    minHeight: 80,
    textAlignVertical: 'top',
  },
  draftActions: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
  },
  actionButton: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#111827',
  },
  saveButton: {
    backgroundColor: '#0A84FF',
  },
  actionButtonPressed: {
    opacity: 0.75,
  },
  actionButtonDisabled: {
    opacity: 0.5,
  },
  actionButtonText: {
    color: '#fff',
    fontWeight: '700',
  },
  lookupPanel: {
    position: 'absolute',
    left: 12,
    right: 12,
    top: 24,
    padding: 14,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.95)',
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowRadius: 20,
    shadowOffset: { width: 0, height: 8 },
    elevation: 6,
    gap: 8,
  },
  lookupSpinner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  lookupTitle: {
    fontWeight: '700',
    fontSize: 16,
    marginTop: 8,
  },
  lookupMeta: {
    color: '#4B5563',
    marginTop: 4,
  },
  lookupSummary: {
    marginTop: 8,
    color: '#111827',
  },
  lookupHint: {
    marginTop: 10,
    color: '#6B7280',
    fontSize: 13,
  },
});
