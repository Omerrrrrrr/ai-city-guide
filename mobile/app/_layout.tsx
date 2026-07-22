import { DarkTheme, DefaultTheme, ThemeProvider } from '@react-navigation/native';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useTranslation } from 'react-i18next';
import 'react-native-reanimated';

import { ErrorBoundary } from '@/components/error-boundary';
import { useColorScheme } from '@/hooks/use-color-scheme';
import '@/src/i18n';
import { useSyncLanguage } from '@/src/hooks/use-sync-language';
import { useNotificationTapHandler } from '@/src/hooks/use-push-notifications';

export const unstable_settings = {
  anchor: 'index',
};

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const { t } = useTranslation();
  useSyncLanguage();
  useNotificationTapHandler();

  return (
    <ErrorBoundary>
      <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
        <Stack>
          <Stack.Screen name="index" options={{ headerShown: false }} />
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="onboarding" options={{ headerShown: false, animation: 'fade' }} />
          <Stack.Screen name="place/[id]" options={{ headerShown: false }} />
          <Stack.Screen name="city-picker" options={{ headerShown: false, animation: 'slide_from_bottom', presentation: 'modal' }} />
          <Stack.Screen name="admin-hours" options={{ title: t('screenTitles.manageHours') }} />
          <Stack.Screen name="admin-images" options={{ title: t('screenTitles.manageImages') }} />
        </Stack>
        <StatusBar style="auto" />
      </ThemeProvider>
    </ErrorBoundary>
  );
}
