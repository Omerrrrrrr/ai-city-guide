import * as Localization from 'expo-localization';
import i18next from 'i18next';
import { initReactI18next } from 'react-i18next';

import en from './locales/en.json';
import nb from './locales/nb.json';
import tr from './locales/tr.json';

export const SUPPORTED_LANGUAGES = ['en', 'tr', 'nb'] as const;
export type SupportedLanguage = (typeof SUPPORTED_LANGUAGES)[number];

function detectDeviceLanguage(): SupportedLanguage {
  const deviceCode = Localization.getLocales()[0]?.languageCode;
  if (deviceCode === 'tr') return 'tr';
  if (deviceCode === 'nb' || deviceCode === 'no' || deviceCode === 'nn') return 'nb';
  return 'en';
}

i18next.use(initReactI18next).init({
  compatibilityJSON: 'v4',
  resources: {
    en: { translation: en },
    tr: { translation: tr },
    nb: { translation: nb },
  },
  lng: detectDeviceLanguage(),
  fallbackLng: 'en',
  interpolation: {
    escapeValue: false,
  },
});

export { detectDeviceLanguage };
export default i18next;
