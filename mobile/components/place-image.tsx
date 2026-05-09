import { Image, type ImageContentFit } from 'expo-image';
import { StyleSheet, type ImageStyle, type StyleProp, type ViewStyle } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import type { Place } from '@/src/data/places';

type PlaceImageProps = {
  place: Pick<Place, 'name' | 'imageUrl' | 'image'>;
  style?: StyleProp<ImageStyle | ViewStyle>;
  contentFit?: ImageContentFit;
  compact?: boolean;
};

export function PlaceImage({
  place,
  style,
  contentFit = 'cover',
  compact = false,
}: PlaceImageProps) {
  const canDisplayImage = place.image.verified && Boolean(place.imageUrl);

  if (canDisplayImage) {
    return <Image source={{ uri: place.imageUrl }} style={style as StyleProp<ImageStyle>} contentFit={contentFit} />;
  }

  return (
    <ThemedView
      lightColor="#F3EFE6"
      darkColor="#1E1E1E"
      style={[styles.placeholder, compact && styles.compactPlaceholder, style as StyleProp<ViewStyle>]}>
      <ThemedText style={[styles.label, compact && styles.labelCompact]}>Photo unavailable</ThemedText>
      {!compact ? (
        <ThemedText style={styles.meta}>
          We only show real place photos after the source is verified.
        </ThemedText>
      ) : null}
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  placeholder: {
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.18)',
    paddingHorizontal: 12,
    gap: 4,
  },
  compactPlaceholder: {
    paddingHorizontal: 6,
    gap: 2,
  },
  label: {
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '700',
    textAlign: 'center',
  },
  labelCompact: {
    fontSize: 11,
    lineHeight: 14,
  },
  meta: {
    fontSize: 12,
    lineHeight: 16,
    opacity: 0.72,
    textAlign: 'center',
  },
});
