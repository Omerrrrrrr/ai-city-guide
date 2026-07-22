import React from 'react';
import { Pressable, type PressableProps, type StyleProp, type ViewStyle } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withSpring } from 'react-native-reanimated';

const AnimatedPressableBase = Animated.createAnimatedComponent(Pressable);

type PressState = { pressed: boolean };
type StyleProp_ = StyleProp<ViewStyle> | ((state: PressState) => StyleProp<ViewStyle>);

type AnimatedPressableProps = Omit<PressableProps, 'style'> & {
  /** Scale factor while pressed. Defaults to a subtle 0.96. */
  scaleTo?: number;
  style?: StyleProp_;
};

/**
 * Drop-in replacement for Pressable that adds a spring-based scale-down on
 * press instead of a flat opacity dip — the standard "feels alive" tap
 * response in modern mobile UI. Compose with your own style/opacity changes
 * as usual; the scale transform is merged in automatically.
 *
 * Forwards its ref so it works as the direct child of expo-router's
 * `<Link asChild>`, same as a plain Pressable would.
 *
 * Resolves a function `style` (Pressable's `{ pressed }` callback pattern)
 * to a plain array before handing it to the Reanimated-wrapped component —
 * passing a function straight through to `Animated.createAnimatedComponent`
 * silently drops the resolved style (it expects an object/array, not a
 * callback), which made every pressed-dependent style vanish invisibly.
 */
export const AnimatedPressable = React.forwardRef<React.ComponentRef<typeof Pressable>, AnimatedPressableProps>(
  function AnimatedPressable({ scaleTo = 0.96, style, onPressIn, onPressOut, children, ...rest }, ref) {
    const scale = useSharedValue(1);
    const [pressed, setPressed] = React.useState(false);
    const animatedStyle = useAnimatedStyle(() => ({
      transform: [{ scale: scale.value }],
    }));

    const resolvedStyle = typeof style === 'function' ? style({ pressed }) : style;

    return (
      <AnimatedPressableBase
        ref={ref}
        onPressIn={(e) => {
          scale.value = withSpring(scaleTo, { damping: 16, stiffness: 280 });
          setPressed(true);
          onPressIn?.(e);
        }}
        onPressOut={(e) => {
          scale.value = withSpring(1, { damping: 14, stiffness: 220 });
          setPressed(false);
          onPressOut?.(e);
        }}
        style={[animatedStyle, resolvedStyle]}
        {...rest}>
        {children}
      </AnimatedPressableBase>
    );
  }
);
