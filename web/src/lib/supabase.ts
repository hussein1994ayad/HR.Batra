import { createClient } from '@supabase/supabase-js';

// القيم الاحتياطية = المشروع الحي (نفسها في mobile/lib/core/constants/constants.dart). المفتاح publishable
// عام بطبيعته والحماية من RLS؛ يُستعمل إذا ما انضبط .env.local وقت البناء فلا يُحذف.
export const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://jgjlmddphhncatrhqrej.supabase.co';
export const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_EjrPBiypg0kR-HMDk0uitw_y1aHc7kP';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  }
});
