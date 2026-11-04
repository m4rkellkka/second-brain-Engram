/**
 * Capture pipeline with a mock model, against the local Supabase stack:
 * claim, sort, write entries, retries, the no-AI fallback and the sweep.
 */
import { MockLanguageModelV4 } from "ai/test";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { SortedCapture } from "@/server/ai/sort";
import {
  processCapture,
  sweepCaptures,
} from "@/server/pipeline/process-capture";
import { createUser, deleteUsers, type Client } from "./support/local-supabase";

function mockAi(answer: SortedCapture | Error) {
  const model = new MockLanguageModelV4({
    doGenerate: async () => {
      if (answer instanceof Error) throw answer;
      return {
        content: [{ type: "text", text: JSON.stringify(answer) }],
        finishReason: { unified: "stop", raw: undefined },
        usage: {
          inputTokens: {
            total: 1000,
            noCache: 1000,
            cacheRead: undefined,
            cacheWrite: undefined,
          },
          outputTokens: { total: 200, text: 200, reasoning: undefined },
        },
        warnings: [],
      };
    },
  });
  return { model, modelId: "claude-haiku-5-5" };
}

let user: { id: string; client: Client };
let other: { id: string; client: Client };
let projectId = "";

async function capture(text: string): Promise<string> {
  const { data, error } = await user.client.rpc("create_text_capture", {
    content: text,
    timezone: "Europe/Istanbul",
  });
  if (error || !data) throw error ?? new Error("no capture");
  return data.id;
}

async function status(id: string) {
  const { data } = await user.client
    .from("captures")
    .select("status, attempts, error")
    .eq("id", id)
    .single();
  return data;
}

async function entries(captureId: string) {
  const { data } = await user.client
    .from("entries")
    .select(
      "kind, content, project_id, needs_review, suggested_project_name, due_at, confidence",
    )
    .eq("capture_id", captureId)
    .order("created_at");
  return data ?? [];
}

beforeAll(async () => {
  [user, other] = await Promise.all([createUser(), createUser()]);
  const { data, error } = await user.client
    .from("projects")
    .insert({
      user_id: user.id,
      name: "Engram",
      slug: "engram",
      color: "#B79CFF",
    })
    .select("id")
    .single();
  if (error) throw error;
  projectId = data.id;
});
afterAll(() => deleteUsers([user?.id, other?.id]));

describe("processCapture", () => {
  it("writes sorted entries, flags the unsure one and logs the call", async () => {
    const id = await capture(
      "Сделать фильтры в Inbox к пятнице. И может завести проект про скейт",
    );
    const ai = mockAi({
      entries: [
        {
          kind: "task",
          content: "Сделать фильтры в Inbox",
          projectSlug: "engram",
          newProjectName: null,
          dueAt: "2026-11-06T09:00:00+03:00",
          url: null,
          confidence: 0.92,
        },
        {
          kind: "idea",
          content: "Завести проект про скейт",
          projectSlug: null,
          newProjectName: "Скейт",
          dueAt: null,
          url: null,
          confidence: 0.6,
        },
      ],
    });

    expect(await processCapture(user.client, id, ai)).toBe("processed");
    expect(await status(id)).toMatchObject({
      status: "processed",
      attempts: 1,
      error: null,
    });

    const rows = await entries(id);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      kind: "task",
      project_id: projectId,
      needs_review: false,
      due_at: "2026-11-06T06:00:00+00:00",
    });
    expect(rows[1]).toMatchObject({
      kind: "idea",
      project_id: null,
      needs_review: true,
      suggested_project_name: "Скейт",
    });

    const { data: calls } = await user.client
      .from("ai_calls")
      .select("model, ok, input_tokens, output_tokens, cost_usd")
      .eq("capture_id", id);
    expect(calls).toEqual([
      // 1000 × $0.10/M + 200 × $0.50/M
      {
        model: "claude-haiku-5-5",
        ok: true,
        input_tokens: 1000,
        output_tokens: 200,
        cost_usd: 0.0002,
      },
    ]);
  });

  it("does not process the same capture twice", async () => {
    const id = await capture("once");
    const ai = mockAi({
      entries: [
        {
          kind: "note",
          content: "once",
          projectSlug: "engram",
          newProjectName: null,
          dueAt: null,
          url: null,
          confidence: 0.9,
        },
      ],
    });
    expect(await processCapture(user.client, id, ai)).toBe("processed");
    expect(await processCapture(user.client, id, ai)).toBe("skipped");
    expect(await entries(id)).toHaveLength(1);
  });

  it("retries a failing model and keeps the text as a note after the last attempt", async () => {
    const id = await capture("the model is down");
    const ai = mockAi(new Error("overloaded"));

    expect(await processCapture(user.client, id, ai)).toBe("failed");
    expect(await status(id)).toMatchObject({ status: "failed", attempts: 1 });
    expect(await entries(id)).toEqual([]);

    await processCapture(user.client, id, ai);
    await processCapture(user.client, id, ai);
    expect(await status(id)).toMatchObject({ status: "failed", attempts: 3 });
    expect(await entries(id)).toMatchObject([
      {
        kind: "note",
        content: "the model is down",
        needs_review: true,
        project_id: null,
      },
    ]);

    expect(await processCapture(user.client, id, ai)).toBe("skipped");
    const { data: calls } = await user.client
      .from("ai_calls")
      .select("ok")
      .eq("capture_id", id);
    expect(calls).toEqual([{ ok: false }, { ok: false }, { ok: false }]);
  });

  it("keeps a plain note when no model is configured", async () => {
    const id = await capture("no api key here");
    expect(await processCapture(user.client, id, null)).toBe("processed");
    expect(await entries(id)).toMatchObject([
      { kind: "note", content: "no api key here", needs_review: false },
    ]);
  });

  it("cannot claim another user's capture", async () => {
    const id = await capture("mine");
    expect(await processCapture(other.client, id, null)).toBe("skipped");
    expect(await status(id)).toMatchObject({ status: "pending", attempts: 0 });
  });
});

describe("sweepCaptures", () => {
  it("picks up a capture left pending and ignores fresh ones", async () => {
    const old = await capture("left behind");
    const fresh = await capture("just saved");
    await user.client
      .from("captures")
      .update({ created_at: new Date(Date.now() - 10 * 60_000).toISOString() })
      .eq("id", old);

    const counts = await sweepCaptures(user.client, null, 10);
    expect(counts.processed).toBeGreaterThanOrEqual(1);
    expect(await status(old)).toMatchObject({ status: "processed" });
    expect(await status(fresh)).toMatchObject({ status: "pending" });
  });
});

describe("AI call log and corrections", () => {
  it("are private to their owner", async () => {
    const { data: entry } = await user.client
      .from("entries")
      .select("id")
      .limit(1)
      .single();
    await user.client.from("entry_corrections").insert({
      user_id: user.id,
      entry_id: entry!.id,
      field: "confirm",
    });
    const [calls, corrections] = await Promise.all([
      other.client.from("ai_calls").select("id"),
      other.client.from("entry_corrections").select("id"),
    ]);
    expect(calls.data).toEqual([]);
    expect(corrections.data).toEqual([]);
  });
});
