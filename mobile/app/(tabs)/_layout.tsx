import { Tabs } from 'expo-router';
import React from 'react';
import { useTranslation } from 'react-i18next';
import { View, StyleSheet } from 'react-native';

import { HapticTab } from '@/components/haptic-tab';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Colors } from '@/constants/theme';
import { useColorScheme } from '@/hooks/use-color-scheme';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

function ScanTabIcon({ color, focused }: { color: string; focused: boolean }) {
  return (
    <View style={[styles.scanIcon, focused && styles.scanIconActive]}>
      <IconSymbol size={22} name="camera.fill" color={focused ? NAVY : color} />
    </View>
  );
}

export default function TabLayout() {
  const colorScheme = useColorScheme();
  const { t } = useTranslation();

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: Colors[colorScheme ?? 'light'].tint,
        headerShown: false,
        tabBarButton: HapticTab,
        tabBarStyle: {
          backgroundColor: colorScheme === 'dark' ? '#0A0F1E' : '#fff',
          borderTopColor: 'rgba(127,127,127,0.12)',
        },
      }}>
      <Tabs.Screen
        name="index"
        options={{
          title: t('tabs.home'),
          tabBarIcon: ({ color }) => <IconSymbol size={26} name="house.fill" color={color} />,
        }}
      />
      <Tabs.Screen
        name="scan"
        options={{
          title: t('tabs.scan'),
          tabBarIcon: ({ color, focused }) => <ScanTabIcon color={color} focused={focused} />,
          tabBarLabel: t('tabs.scan'),
        }}
      />
      <Tabs.Screen
        name="map"
        options={{
          title: t('tabs.map'),
          tabBarIcon: ({ color }) => <IconSymbol size={26} name="map.fill" color={color} />,
        }}
      />
      <Tabs.Screen
        name="ai"
        options={{
          title: t('tabs.ai'),
          tabBarIcon: ({ color }) => <IconSymbol size={26} name="sparkles" color={color} />,
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: t('tabs.profile'),
          tabBarIcon: ({ color }) => <IconSymbol size={26} name="person.fill" color={color} />,
        }}
      />
      {/* Hidden from tab bar but accessible as routes */}
      <Tabs.Screen
        name="explore"
        options={{ href: null }}
      />
      <Tabs.Screen
        name="saved"
        options={{ href: null }}
      />
    </Tabs>
  );
}

const styles = StyleSheet.create({
  scanIcon: {
    width: 44,
    height: 30,
    borderRadius: 15,
    backgroundColor: 'rgba(15,28,63,0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  scanIconActive: {
    backgroundColor: GOLD,
  },
});
