import { randomUUID } from 'node:crypto';

import { eq } from 'drizzle-orm';

import { sendApnsMessages } from './apns';
import { db } from './db';
import { pushSubscriptions } from './schema';

// APNs device tokens are 64 hex chars in practice, but that's not a
// documented Apple guarantee -- validate loosely (hex, reasonable length)
// rather than pinning to an exact count.
const DEVICE_TOKEN_PATTERN = /^[0-9a-f]{32,}$/i;

function isDeviceToken(token: string) {
  return DEVICE_TOKEN_PATTERN.test(token);
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

export async function subscribeToCityDiscovery(cityId: string, deviceToken: string, locale?: string) {
  if (!isDeviceToken(deviceToken)) return;

  // A user re-tapping "discover" for a city already in progress (e.g. the
  // /cities/discover retry path) would otherwise insert a second row for the
  // same city+token pair and get the completion push twice. The unique index
  // on (cityId, deviceToken) makes this a safe no-op instead.
  await db
    .insert(pushSubscriptions)
    .values({
      id: randomUUID(),
      cityId,
      deviceToken,
      locale: locale && locale in COPY ? locale : 'en',
      createdAt: new Date().toISOString(),
    })
    .onConflictDoNothing({ target: [pushSubscriptions.cityId, pushSubscriptions.deviceToken] });
}

async function sendAndClearSubscriptions(
  cityId: string,
  cityName: string,
  buildMessage: (locale: string) => { title: string; body: string }
) {
  const subs = await db.select().from(pushSubscriptions).where(eq(pushSubscriptions.cityId, cityId));
  if (subs.length === 0) return;

  const messages = subs
    .filter((sub) => isDeviceToken(sub.deviceToken))
    .map((sub) => {
      const { title, body } = buildMessage(sub.locale);
      return {
        deviceToken: sub.deviceToken,
        title,
        body,
        data: { type: 'city-discovery', cityId, cityName },
      };
    });

  try {
    await sendApnsMessages(messages);
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
