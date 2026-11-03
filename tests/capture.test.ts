/**
 * Text capture: input validation and the `create_text_capture` function.
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

  it("creates one processed text capture and one note entry for the caller", async () => {
    const { data: entry, error } = await user.client.rpc(
      "create_text_capture",
      {
        content: "  remember the milk  ",
      },
    );
    expect(error).toBeNull();
    expect(entry).toMatchObject({
      user_id: user.id,
      kind: "note",
      content: "remember the milk",
      project_id: null,
    });

    const { data: capture } = await user.client
      .from("captures")
      .select("user_id, source, raw_text, status")
      .eq("id", entry!.capture_id!)
      .single();
    expect(capture).toEqual({
      user_id: user.id,
      source: "text",
      raw_text: "remember the milk",
      status: "processed",
    });
  });

  it("is invisible to another user", async () => {
    const { data: entry } = await user.client.rpc("create_text_capture", {
      content: "private",
    });
    const { data } = await other.client
      .from("entries")
      .select("id")
      .eq("id", entry!.id);
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
