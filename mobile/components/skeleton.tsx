import React from 'react';
import { Animated, StyleSheet, View, useColorScheme } from 'react-native';

function usePulse() {
  const anim = React.useRef(new Animated.Value(0)).current;
  React.useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(anim, { toValue: 1, duration: 900, useNativeDriver: true }),
        Animated.timing(anim, { toValue: 0, duration: 900, useNativeDriver: true }),
      ])
    );
    loop.start();
    return () => loop.stop();
  }, [anim]);
  return anim;
}

export function SkeletonBox({
  width,
  height,
  borderRadius = 8,
  style,
}: {
  width?: number | string;
  height: number;
  borderRadius?: number;
  style?: object;
}) {
  const dark = useColorScheme() === 'dark';
  const pulse = usePulse();
  const opacity = pulse.interpolate({ inputRange: [0, 1], outputRange: [0.35, 0.7] });

  return (
    <Animated.View
      style={[
        {
          width: width ?? '100%',
          height,
          borderRadius,
          backgroundColor: dark ? '#1E2A45' : '#E0E4EF',
          opacity,
        },
        style,
      ]}
    />
  );
}

export function FeaturedCardSkeleton() {
  return (
    <View style={styles.featCard}>
      <SkeletonBox height={130} borderRadius={0} />
      <View style={styles.featBody}>
        <SkeletonBox height={10} width={48} borderRadius={5} />
        <SkeletonBox height={14} width="80%" borderRadius={5} />
        <SkeletonBox height={12} width={60} borderRadius={5} />
      </View>
    </View>
  );
}

export function PlaceRowSkeleton() {
  return (
    <View style={styles.row}>
      <SkeletonBox width={60} height={60} borderRadius={10} />
      <View style={styles.rowBody}>
        <SkeletonBox height={14} width="60%" borderRadius={5} />
        <SkeletonBox height={12} width="40%" borderRadius={5} />
      </View>
      <SkeletonBox width={50} height={20} borderRadius={10} />
    </View>
  );
}

export function PlaceDetailSkeleton({ insetTop = 0 }: { insetTop?: number }) {
  const dark = useColorScheme() === 'dark';
  const cardBg = dark ? '#1A2744' : '#fff';
  const bg = dark ? '#0A0F1E' : '#F4F5F9';

  return (
    <View style={{ flex: 1, backgroundColor: bg }}>
      {/* Hero */}
      <SkeletonBox height={300 + insetTop} borderRadius={0} />

      {/* Action bar */}
      <View style={{ backgroundColor: cardBg, flexDirection: 'row', padding: 16, gap: 12 }}>
        {[1, 2, 3, 4].map((n) => (
          <View key={n} style={{ flex: 1, alignItems: 'center', gap: 6 }}>
            <SkeletonBox width={22} height={22} borderRadius={11} />
            <SkeletonBox width={40} height={10} borderRadius={5} />
          </View>
        ))}
      </View>

      <View style={{ padding: 16, gap: 14 }}>
        {/* Piri's Take card skeleton */}
        <View style={{ backgroundColor: '#0F1C3F', borderRadius: 18, padding: 20, gap: 10 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
            <SkeletonBox width={28} height={28} borderRadius={14} />
            <SkeletonBox width={90} height={14} borderRadius={5} />
          </View>
          <SkeletonBox height={14} width="70%" borderRadius={5} />
          <SkeletonBox height={12} borderRadius={5} />
          <SkeletonBox height={12} width="85%" borderRadius={5} />
        </View>

        {/* About card */}
        <View style={{ backgroundColor: cardBg, borderRadius: 18, padding: 18, gap: 10 }}>
          <SkeletonBox height={12} width={60} borderRadius={5} />
          <SkeletonBox height={13} borderRadius={5} />
          <SkeletonBox height={13} width="90%" borderRadius={5} />
          <SkeletonBox height={13} width="75%" borderRadius={5} />
        </View>

        {/* Hours card */}
        <View style={{ backgroundColor: cardBg, borderRadius: 18, padding: 18, gap: 10 }}>
          <SkeletonBox height={12} width={80} borderRadius={5} />
          <SkeletonBox height={13} width="50%" borderRadius={5} />
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  featCard: {
    width: 180,
    borderRadius: 16,
    overflow: 'hidden',
  },
  featBody: {
    padding: 12,
    gap: 8,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    borderRadius: 14,
    padding: 12,
  },
  rowBody: {
    flex: 1,
    gap: 8,
  },
});
