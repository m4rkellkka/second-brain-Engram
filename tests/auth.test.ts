/**
 * Auth settings of the local stack: one-person instance, no public sign-up.
 * Runs against the local Supabase stack with the seed applied (`pnpm db:reset`).
 */
import { execSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

const local = JSON.parse(
  execSync("pnpm --silent supabase status -o json", { encoding: "utf8" }),
) as { API_URL: string; PUBLISHABLE_KEY: string };

function publicClient() {
  return createClient(local.API_URL, local.PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

describe("auth", () => {
  it("rejects sign-up through the public API", async () => {
    const { data, error } = await publicClient().auth.signUp({
      email: `intruder-${randomUUID()}@engram.test`,
      password: randomUUID(),
    });
    expect(error?.code).toBe("signup_disabled");
    expect(data.user).toBeNull();
  });

  it("signs in the seeded user with their password", async () => {
    const { data, error } = await publicClient().auth.signInWithPassword({
      email: "dev@engram.local",
      password: "engram-dev",
    });
    expect(error).toBeNull();
    expect(data.session).not.toBeNull();
  });

  it("rejects a wrong password", async () => {
    const { data, error } = await publicClient().auth.signInWithPassword({
      email: "dev@engram.local",
      password: "not-the-password",
    });
    expect(error?.code).toBe("invalid_credentials");
    expect(data.session).toBeNull();
  });
});
