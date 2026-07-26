import i18next from 'i18next';

import en from '../locales/en.json';
import nb from '../locales/nb.json';
import tr from '../locales/tr.json';

// Regression test for a real bug found in production: Turkish CLDR
// pluralization rules distinguish "one" vs "other" (unlike what Turkish
// grammar might suggest, since Turkish nouns don't inflect for plural).
// Locale files that only defined `_other` for a pluralized key silently
// fell back to the *English* string when count was 1, even with the app
// language set to Turkish — see feedback_i18next_turkish_plurals memory.
// This uses its own isolated i18next instance (not the app's `@/src/i18n`
// singleton) so it doesn't depend on expo-localization / device state.

const PLURALIZED_KEYS = ['explore.placesFound', 'map.placesCount', 'cityPicker.placeCount'];

async function createInstance(language: string) {
  const instance = i18next.createInstance();
  await instance.init({
    compatibilityJSON: 'v4',
    resources: {
      en: { translation: en },
      tr: { translation: tr },
      nb: { translation: nb },
    },
    lng: language,
    fallbackLng: 'en',
    interpolation: { escapeValue: false },
  });
  return instance;
}

describe('pluralized keys resolve in the active language, not just in English', () => {
  it.each(PLURALIZED_KEYS)('Turkish "%s" stays Turkish for count=1 (singular)', async (key) => {
    const trInstance = await createInstance('tr');
    const enInstance = await createInstance('en');

    const trResult = trInstance.t(key, { count: 1 });
    const enResult = enInstance.t(key, { count: 1 });

    // The real bug: without a `_one` key, i18next falls back through the
    // chain to the English string even though the active language is 'tr'.
    expect(trResult).not.toBe(enResult);
  });

  it.each(PLURALIZED_KEYS)('Turkish "%s" resolves for count=5 (plural) too', async (key) => {
    const trInstance = await createInstance('tr');
    const result = trInstance.t(key, { count: 5 });

    expect(typeof result).toBe('string');
    expect(result.length).toBeGreaterThan(0);
  });

  it.each(PLURALIZED_KEYS)('every pluralized key defines both _one and _other in tr.json', (key) => {
    const [namespace, leaf] = key.split('.');
    const bucket = (tr as any)[namespace];

    expect(bucket).toBeDefined();
    expect(bucket[`${leaf}_one`]).toBeDefined();
    expect(bucket[`${leaf}_other`]).toBeDefined();
  });
});
