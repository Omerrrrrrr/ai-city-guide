import React from 'react';
import { Pressable, StyleSheet } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';

type Props = {
  children: React.ReactNode;
};

type State = {
  error: Error | null;
};

export class ErrorBoundary extends React.Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('Unhandled error caught by ErrorBoundary:', error, info.componentStack);
  }

  reset = () => {
    this.setState({ error: null });
  };

  render() {
    if (this.state.error) {
      return <ErrorFallback onRetry={this.reset} />;
    }

    return this.props.children;
  }
}

function ErrorFallback({ onRetry }: { onRetry: () => void }) {
  return (
    <ThemedView style={styles.container}>
      <ThemedText type="subtitle">Something went wrong</ThemedText>
      <ThemedText style={styles.text}>
        The app hit an unexpected error. You can try again, or restart the app if it keeps
        happening.
      </ThemedText>
      <Pressable
        onPress={onRetry}
        style={({ pressed }) => [styles.button, pressed && styles.buttonPressed]}>
        <ThemedText style={styles.buttonText}>Try again</ThemedText>
      </Pressable>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    gap: 12,
    padding: 24,
    justifyContent: 'center',
  },
  text: {
    opacity: 0.75,
    lineHeight: 20,
  },
  button: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 14,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.24)',
  },
  buttonPressed: {
    opacity: 0.72,
  },
  buttonText: {
    fontSize: 15,
    fontWeight: '600',
  },
});
