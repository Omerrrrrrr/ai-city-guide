import React from 'react';
import Constants from 'expo-constants';
import * as Notifications from 'expo-notifications';
import { useRouter } from 'expo-router';
import { Platform } from 'react-native';

import { useCityStore } from '@/src/store/city';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

const PROJECT_ID = Constants.expoConfig?.extra?.eas?.projectId as string | undefined;

/**
 * Best-effort push token fetch: requests permission if needed and returns
 * an Expo push token, or undefined if permission is denied, no physical
 * device is available, or anything else goes wrong. Never throws — a
 * missing push token should never block the flow that wants one.
 */
export async function getExpoPushToken(): Promise<string | undefined> {
  try {
    if (!PROJECT_ID) return undefined;

    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('default', {
        name: 'default',
        importance: Notifications.AndroidImportance.DEFAULT,
      });
    }

    const { status: existingStatus } = await Notifications.getPermissionsAsync();
    let status = existingStatus;
    if (status !== 'granted') {
      const requested = await Notifications.requestPermissionsAsync();
      status = requested.status;
    }
    if (status !== 'granted') return undefined;

    const { data } = await Notifications.getExpoPushTokenAsync({ projectId: PROJECT_ID });
    return data;
  } catch {
    return undefined;
  }
}

type CityDiscoveryNotificationData = {
  type?: string;
  cityId?: string;
  cityName?: string;
};

/**
 * Handles taps on push notifications app-wide: a city-discovery notification
 * switches the current city and opens Home, whether tapped from a killed
 * app (cold start) or while the app is already running.
 */
export function useNotificationTapHandler() {
  const router = useRouter();
  const setCity = useCityStore((state) => state.setCity);

  React.useEffect(() => {
    function handleData(data: CityDiscoveryNotificationData | undefined) {
      if (data?.type === 'city-discovery' && data.cityId && data.cityName) {
        setCity(data.cityId, data.cityName);
        router.push('/(tabs)');
      }
    }

    Notifications.getLastNotificationResponseAsync().then((response) => {
      handleData(response?.notification.request.content.data as CityDiscoveryNotificationData | undefined);
    });

    const subscription = Notifications.addNotificationResponseReceivedListener((response) => {
      handleData(response.notification.request.content.data as CityDiscoveryNotificationData | undefined);
    });

    return () => subscription.remove();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}
