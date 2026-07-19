import React from 'react';
import { getCityStatus, type CityResult } from '@/src/api/cities';
import { useCityStore } from '@/src/store/city';

const POLL_INTERVAL = 5000;

export type CityDiscoveryState = 'idle' | 'discovering' | 'ready' | 'failed';

export function useCityStatus(onReady?: () => void): {
  status: CityDiscoveryState;
  cityInfo: CityResult | null;
} {
  const cityId = useCityStore((s) => s.cityId);
  const [cityInfo, setCityInfo] = React.useState<CityResult | null>(null);
  const [status, setStatus] = React.useState<CityDiscoveryState>('idle');
  const onReadyRef = React.useRef(onReady);
  onReadyRef.current = onReady;

  React.useEffect(() => {
    if (!cityId) {
      setStatus('idle');
      setCityInfo(null);
      return;
    }

    let cancelled = false;
    let timer: ReturnType<typeof setTimeout>;
    let wasDiscovering = false;

    const poll = async () => {
      try {
        const info = await getCityStatus(cityId);
        if (cancelled) return;

        setCityInfo(info);
        const s = info.status as string;

        if (s === 'ready') {
          setStatus('ready');
          if (wasDiscovering) onReadyRef.current?.();
        } else if (s === 'discovering' || s === 'pending') {
          setStatus('discovering');
          wasDiscovering = true;
          timer = setTimeout(poll, POLL_INTERVAL);
        } else if (s === 'failed') {
          setStatus('failed');
        } else {
          setStatus('idle');
        }
      } catch {
        if (!cancelled) {
          setStatus('idle');
        }
      }
    };

    void poll();
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [cityId]);

  return { status, cityInfo };
}
