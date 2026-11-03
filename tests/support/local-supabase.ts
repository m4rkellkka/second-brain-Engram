/** Shared helpers for tests that run against the local Supabase stack. */
import { execSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/server/db/database.types";

export type Client = SupabaseClient<Database>;

export const local = JSON.parse(
  execSync("pnpm --silent supabase status -o json", { encoding: "utf8" }),
) as { API_URL: string; PUBLISHABLE_KEY: string; SECRET_KEY: string };

const noSession = { auth: { persistSession: false, autoRefreshToken: false } };

export const admin: Client = createClient<Database>(
  local.API_URL,
  local.SECRET_KEY,
  noSession,
);

export function publicClient(): Client {
  return createClient<Database>(
    local.API_URL,
    local.PUBLISHABLE_KEY,
    noSession,
  );
}

/** Creates a confirmed throwaway user and returns a client signed in as them. */
export async function createUser(): Promise<{ id: string; client: Client }> {
  const email = `test-${randomUUID()}@engram.test`;
  const password = randomUUID();
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error) throw error;
  const client = publicClient();
  const { error: signInError } = await client.auth.signInWithPassword({
    email,
    password,
  });
  if (signInError) throw signInError;
  return { id: data.user.id, client };
}

export async function deleteUsers(ids: (string | undefined)[]): Promise<void> {
  await Promise.all(
    ids
      .filter((id): id is string => Boolean(id))
      .map((id) => admin.auth.admin.deleteUser(id)),
  );
}
