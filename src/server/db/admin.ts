import { createClient } from "@supabase/supabase-js";
import { env } from "@/lib/env";
import { serverEnv } from "@/server/env";
import type { Database } from "./database.types";

/**
 * Supabase client with the secret key: bypasses RLS. Only for the cron
 * retry sweep, which runs without a user session. Never import it from
 * code that a browser can reach with its own input.
 */
export function createAdminClient() {
  if (!serverEnv.SUPABASE_SECRET_KEY) return null;
  return createClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    serverEnv.SUPABASE_SECRET_KEY,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
