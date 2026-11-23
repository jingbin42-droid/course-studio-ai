import "server-only";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";

import { getSupabaseSecretEnv } from "@/lib/env";

export function createAdminClient() {
  const env = getSupabaseSecretEnv();

  return createSupabaseClient(env.SUPABASE_URL, env.SUPABASE_SECRET_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
