import { randomUUID } from 'node:crypto';

import { eq } from 'drizzle-orm';

import { db } from './db';
import { pushSubscriptions } from './schema';

const EXPO_PUSH_ENDPOINT = 'https://exp.host/--/api/v2/push/send';
const EXPO_PUSH_TOKEN_PATTERN = /^Expo(nent)?PushToken\[.+\]$/;
const MAX_MESSAGES_PER_REQUEST = 100;

type ExpoPushMessage = {
  to: string;
  sound: 'default';
  title: string;
  body: string;
  data: Record<string, unknown>;
};

function isExpoPushToken(token: string) {
  return EXPO_PUSH_TOKEN_PATTERN.test(token);
}

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

async function sendExpoPushMessages(messages: ExpoPushMessage[]) {
  for (const batch of chunk(messages, MAX_MESSAGES_PER_REQUEST)) {
    const response = await fetch(EXPO_PUSH_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'Accept-Encoding': 'gzip, deflate',
      },
      body: JSON.stringify(batch),
    });

    if (!response.ok) {
      const text = await response.text().catch(() => '');
      throw new Error(`Expo push API returned ${response.status}: ${text}`);
    }
  }
}

const COPY: Record<string, { ready: (city: string, count: number) => { title: string; body: string }; failed: (city: string) => { title: string; body: string } }> = {
  en: {
    ready: (city, count) => ({
      title: `${city} is ready! 🗺️`,
      body: count > 0 ? `Piri found ${count} places to explore.` : `Piri finished exploring ${city}.`,
    }),
    failed: (city) => ({
      title: `Couldn't finish exploring ${city}`,
      body: `Something went wrong. Try discovering ${city} again from the city picker.`,
    }),
  },
  tr: {
    ready: (city, count) => ({
      title: `${city} hazır! 🗺️`,
      body: count > 0 ? `Piri ${count} yer keşfetti.` : `Piri ${city} keşfini tamamladı.`,
    }),
    failed: (city) => ({
      title: `${city} keşfi tamamlanamadı`,
      body: `Bir sorun oluştu. Şehir seçiciden ${city}'yi tekrar keşfetmeyi dene.`,
    }),
  },
  nb: {
    ready: (city, count) => ({
      title: `${city} er klar! 🗺️`,
      body: count > 0 ? `Piri fant ${count} steder å utforske.` : `Piri er ferdig med å utforske ${city}.`,
    }),
    failed: (city) => ({
      title: `Kunne ikke fullføre utforskingen av ${city}`,
      body: `Noe gikk galt. Prøv å utforske ${city} på nytt fra bysøket.`,
    }),
  },
};

function copyFor(locale: string) {
  return COPY[locale] ?? COPY.en;
}

export async function subscribeToCityDiscovery(cityId: string, expoPushToken: string, locale?: string) {
  if (!isExpoPushToken(expoPushToken)) return;

  await db.insert(pushSubscriptions).values({
    id: randomUUID(),
    cityId,
    expoPushToken,
    locale: locale && locale in COPY ? locale : 'en',
    createdAt: new Date().toISOString(),
  });
}

async function sendAndClearSubscriptions(
  cityId: string,
  cityName: string,
  buildMessage: (locale: string) => { title: string; body: string }
) {
  const subs = await db.select().from(pushSubscriptions).where(eq(pushSubscriptions.cityId, cityId));
  if (subs.length === 0) return;

  const messages: ExpoPushMessage[] = subs
    .filter((sub) => isExpoPushToken(sub.expoPushToken))
    .map((sub) => {
      const { title, body } = buildMessage(sub.locale);
      return {
        to: sub.expoPushToken,
        sound: 'default' as const,
        title,
        body,
        data: { type: 'city-discovery', cityId, cityName },
      };
    });

  try {
    await sendExpoPushMessages(messages);
  } catch (error) {
    console.error(`Failed to send push notifications for city ${cityId}:`, error);
  }

  await db.delete(pushSubscriptions).where(eq(pushSubscriptions.cityId, cityId));
}

export async function notifyCityDiscoveryReady(cityId: string, cityName: string, placeCount: number) {
  await sendAndClearSubscriptions(cityId, cityName, (locale) => copyFor(locale).ready(cityName, placeCount));
}

export async function notifyCityDiscoveryFailed(cityId: string, cityName: string) {
  await sendAndClearSubscriptions(cityId, cityName, (locale) => copyFor(locale).failed(cityName));
}
