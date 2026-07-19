import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

import { secureStoreStorage } from '@/src/utils/secure-store-adapter';

type AdminAuthState = {
  adminToken: string | null;
  setAdminToken: (token: string) => void;
  clearAdminToken: () => void;
};

export const useAdminAuth = create<AdminAuthState>()(
  persist(
    (set) => ({
      adminToken: null,
      setAdminToken: (token) => set({ adminToken: token.trim() || null }),
      clearAdminToken: () => set({ adminToken: null }),
    }),
    {
      name: 'ai-city-guide.admin-auth',
      storage: createJSONStorage(() => secureStoreStorage),
    }
  )
);
