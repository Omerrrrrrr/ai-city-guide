import React from 'react';
import { Pressable, StyleSheet, TextInput } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useThemeColor } from '@/hooks/use-theme-color';
import { useAdminAuth } from '@/src/store/admin-auth';

export function AdminGate({ children }: { children: React.ReactNode }) {
  const adminToken = useAdminAuth((state) => state.adminToken);
  const setAdminToken = useAdminAuth((state) => state.setAdminToken);
  const [draftToken, setDraftToken] = React.useState('');
  const textColor = useThemeColor({}, 'text');
  const tintColor = useThemeColor({}, 'tint');
  const buttonTextColor = useThemeColor({}, 'background');

  if (adminToken) {
    return <>{children}</>;
  }

  return (
    <ThemedView style={styles.container}>
      <ThemedText type="subtitle">Admin access required</ThemedText>
      <ThemedText style={styles.text}>
        Enter the ADMIN_API_TOKEN configured on the backend to use this screen.
      </ThemedText>
      <TextInput
        value={draftToken}
        onChangeText={setDraftToken}
        placeholder="Admin token"
        placeholderTextColor="rgba(127,127,127,0.7)"
        secureTextEntry
        autoCapitalize="none"
        autoCorrect={false}
        style={[styles.input, { color: textColor, borderColor: tintColor }]}
      />
      <Pressable
        onPress={() => setAdminToken(draftToken)}
        disabled={!draftToken.trim()}
        style={({ pressed }) => [
          styles.button,
          { backgroundColor: tintColor },
          !draftToken.trim() && styles.buttonDisabled,
          pressed && styles.buttonPressed,
        ]}>
        <ThemedText style={[styles.buttonText, { color: buttonTextColor }]}>Unlock</ThemedText>
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
  input: {
    borderWidth: 1,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 15,
  },
  button: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 14,
    borderRadius: 12,
  },
  buttonDisabled: {
    opacity: 0.45,
  },
  buttonPressed: {
    opacity: 0.85,
  },
  buttonText: {
    fontWeight: '600',
    fontSize: 15,
  },
});
