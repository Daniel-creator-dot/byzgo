import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://ypmiurbtmfiyzmrygonh.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

// Fallback to a dummy key to prevent client initialization crash if environment variables aren't loaded yet
const finalAnonKey = supabaseAnonKey || 'dummy-anon-key-please-set-vite-supabase-anon-key';

export const supabase = createClient(supabaseUrl, finalAnonKey);
