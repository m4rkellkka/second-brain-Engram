/**
 * Text capture: input validation and the `create_text_capture` function.
 * Sorting into entries is covered in pipeline.test.ts.
 * The database part runs against the local Supabase stack.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { captureTextSchema } from "@/features/capture/schema";
import {
  createUser,
  deleteUsers,
  publicClient,
  type Client,
} from "./support/local-supabase";

describe("captureTextSchema", () => {
  it("trims the text", () => {
    expect(captureTextSchema.parse("  idea  ")).toBe("idea");
  });

  it.each(["", "   ", "\n\t"])("rejects empty input %j", (value) => {
    expect(captureTextSchema.safeParse(value).success).toBe(false);
  });

  it("rejects text over 10,000 characters", () => {
    expect(captureTextSchema.safeParse("a".repeat(10_001)).success).toBe(false);
    expect(captureTextSchema.safeParse("a".repeat(10_000)).success).toBe(true);
  });
});

describe("create_text_capture", () => {
  let user: { id: string; client: Client };
  let other: { id: string; client: Client };

  beforeAll(async () => {
    [user, other] = await Promise.all([createUser(), createUser()]);
  });
  afterAll(() => deleteUsers([user?.id, other?.id]));

  it("saves a pending text capture for the caller, without entries yet", async () => {
    const { data: capture, error } = await user.client.rpc(
      "create_text_capture",
      { content: "  remember the milk  ", timezone: "Europe/Istanbul" },
    );
    expect(error).toBeNull();
    expect(capture).toMatchObject({
      user_id: user.id,
      source: "text",
      raw_text: "remember the milk",
      status: "pending",
      attempts: 0,
      timezone: "Europe/Istanbul",
    });

    const { data: entries } = await user.client
      .from("entries")
      .select("id")
      .eq("capture_id", capture!.id);
    expect(entries).toEqual([]);
  });

  it("is invisible to another user", async () => {
    const { data: capture } = await user.client.rpc("create_text_capture", {
      content: "private",
    });
    const { data } = await other.client
      .from("captures")
      .select("id")
      .eq("id", capture!.id);
    expect(data).toEqual([]);
  });

  it("rejects empty content", async () => {
    const { error } = await user.client.rpc("create_text_capture", {
      content: "   ",
    });
    expect(error?.code).toBe("22023");
  });

  it("cannot be called without signing in", async () => {
    const { error } = await publicClient().rpc("create_text_capture", {
      content: "anonymous",
    });
    expect(error).not.toBeNull();
  });
});

describe("timeZoneSchema", () => {
  it("accepts IANA zones and rejects junk", async () => {
    const { timeZoneSchema } = await import("@/features/capture/schema");
    expect(timeZoneSchema.safeParse("Europe/Istanbul").success).toBe(true);
    expect(timeZoneSchema.safeParse("Mars/Olympus").success).toBe(false);
    expect(timeZoneSchema.safeParse("").success).toBe(false);
  });
});
