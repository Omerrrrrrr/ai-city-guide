import { Redirect } from 'expo-router';
import { View } from 'react-native';

import { useUserProfile } from '@/src/store/user-profile';

export default function Index() {
  const { onboardingCompleted, _hasHydrated } = useUserProfile();

  if (!_hasHydrated) {
    return <View style={{ flex: 1, backgroundColor: '#0F1C3F' }} />;
  }

  if (!onboardingCompleted) {
    return <Redirect href="/onboarding" />;
  }

  return <Redirect href="/(tabs)" />;
}
