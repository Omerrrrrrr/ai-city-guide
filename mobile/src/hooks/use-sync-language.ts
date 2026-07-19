import { useEffect } from 'react';

import i18n, { detectDeviceLanguage } from '@/src/i18n';
import { useLanguageStore } from '@/src/store/language';

export function useSyncLanguage() {
  const language = useLanguageStore((state) => state.language);

  useEffect(() => {
    const target = language ?? detectDeviceLanguage();
    if (i18n.language !== target) {
      i18n.changeLanguage(target);
    }
  }, [language]);
}
