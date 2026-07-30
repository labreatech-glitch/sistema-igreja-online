import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL?.trim();
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim();

const hasValidUrl = typeof url === 'string' && /^https:\/\/[^\s]+\.supabase\.co$/.test(url);
const hasValidAnonKey = typeof anonKey === 'string' && anonKey.length > 80 && !anonKey.includes('SEU-PROJETO');

export const isSupabaseConfigured = Boolean(hasValidUrl && hasValidAnonKey);

export const supabase = isSupabaseConfigured
  ? createClient(url, anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null;

export function getSupabaseDebugInfo() {
  return {
    configured: isSupabaseConfigured,
    url: url || 'não informada',
    keyType: anonKey ? 'anon/public' : 'ausente',
    keyPreview: anonKey ? `${anonKey.slice(0, 8)}...${anonKey.slice(-6)}` : 'não informada',
  };
}
