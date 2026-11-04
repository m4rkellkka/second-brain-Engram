/**
 * Auth settings of the local stack: one-person instance, no public sign-up.
 * Runs against the local Supabase stack with the seed applied (`pnpm db:reset`).
 */
import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { publicClient } from "./support/local-supabase";

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
