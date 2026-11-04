/**
 * Live project context: patch cleaning, the database rules ("user edits
 * win", append-only, no duplicates) and the updater in the pipeline.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { processCapture } from "@/server/pipeline/process-capture";
import { toContextPatch } from "@/server/pipeline/context-patch";
import { updateProjectContext } from "@/server/pipeline/update-context";
import { createUser, deleteUsers, type Client } from "./support/local-supabase";
import { mockAi } from "./support/mock-ai";

describe("toContextPatch", () => {
  const refs = new Map([
    ["e1", "id-1"],
    ["e2", "id-2"],
  ]);

  it("drops items the context already has and repeats, ignoring case", () => {
    const patch = toContextPatch(
      {
        summary: null,
        status: null,
        add: [
          { section: "stack", text: "supabase", from: ["e1"] },
          { section: "stack", text: "pgvector", from: ["e1"] },
          { section: "stack", text: " PGVECTOR ", from: ["e2"] },
          { section: "idea", text: "Supabase", from: ["e2"] },
        ],
      },
      refs,
      [{ section: "stack", text: "Supabase" }],
    );
    expect(patch.items.map((i) => `${i.section}:${i.text}`)).toEqual([
      "stack:pgvector",
      "idea:Supabase",
    ]);
  });

  it("maps refs to entry ids and credits unknown refs to the whole batch", () => {
    const patch = toContextPatch(
      {
        summary: null,
        status: null,
        add: [
          { section: "decision", text: "Use Haiku", from: ["e2", "e2"] },
          { section: "idea", text: "Diary mode", from: ["e9"] },
        ],
      },
      refs,
      [],
    );
    expect(patch.items[0].entry_ids).toEqual(["id-2"]);
    expect(patch.items[1].entry_ids).toEqual(["id-1", "id-2"]);
  });

  it("treats blank summary and status as no change and caps items", () => {
    const patch = toContextPatch(
      {
        summary: "  ",
        status: "",
        add: Array.from({ length: 12 }, (_, i) => ({
          section: "idea" as const,
          text: `idea ${i}`,
          from: [],
        })),
      },
      refs,
      [],
    );
    expect(patch.summary).toBeNull();
    expect(patch.status).toBeNull();
    expect(patch.items).toHaveLength(8);
  });
});

let user: { id: string; client: Client };
let other: { id: string; client: Client };
let projectId = "";

async function project() {
  const { data } = await user.client
    .from("projects")
    .select(
      "summary, summary_source, status, status_source, context_updated_at",
    )
    .eq("id", projectId)
    .single();
  return data;
}

async function items() {
  const { data } = await user.client
    .from("project_context_items")
    .select("section, text, source, entry_ids")
    .eq("project_id", projectId)
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
      summary: "A second brain.",
      status: "building",
    })
    .select("id")
    .single();
  if (error) throw error;
  projectId = data.id;
});
afterAll(() => deleteUsers([user?.id, other?.id]));

describe("apply_context_patch", () => {
  it("updates an AI summary and status and appends items without duplicates", async () => {
    const { error } = await user.client.rpc("apply_context_patch", {
      project_id: projectId,
      new_summary: "A self-hosted second brain.",
      new_status: "pilot",
      items: [
        { section: "stack", text: "Supabase", entry_ids: [] },
        { section: "stack", text: "supabase ", entry_ids: [] },
      ],
    });
    expect(error).toBeNull();
    expect(await project()).toMatchObject({
      summary: "A self-hosted second brain.",
      status: "pilot",
    });
    expect(await items()).toMatchObject([
      { section: "stack", text: "Supabase", source: "ai" },
    ]);
  });

  it("never replaces a summary or status written by hand", async () => {
    await user.client
      .from("projects")
      .update({
        summary: "Mine.",
        summary_source: "user",
        status: "paused",
        status_source: "user",
      })
      .eq("id", projectId);
    await user.client.rpc("apply_context_patch", {
      project_id: projectId,
      new_summary: "AI rewrite",
      new_status: "done",
    });
    expect(await project()).toMatchObject({
      summary: "Mine.",
      status: "paused",
    });
  });

  it("cannot touch another user's project", async () => {
    const { error } = await other.client.rpc("apply_context_patch", {
      project_id: projectId,
      new_summary: "hijack",
    });
    expect(error?.code).toBe("P0002");
    const { data } = await other.client
      .from("project_context_items")
      .select("id");
    expect(data).toEqual([]);
  });
});

describe("updateProjectContext in the pipeline", () => {
  it("adds what a confident entry says, credited to that entry", async () => {
    const { data: capture } = await user.client.rpc("create_text_capture", {
      content: "Решил: для сортировки берём Haiku, он дешевле",
    });
    const ai = mockAi({
      sort: {
        entries: [
          {
            kind: "note",
            content: "Для сортировки берём Haiku",
            projectSlug: "engram",
            newProjectName: null,
            dueAt: null,
            url: null,
            confidence: 0.9,
          },
        ],
      },
      context: {
        summary: null,
        status: null,
        add: [
          { section: "decision", text: "Сортировка на Haiku", from: ["e1"] },
        ],
      },
    });

    expect(await processCapture(user.client, capture!.id, ai)).toBe(
      "processed",
    );
    const { data: entry } = await user.client
      .from("entries")
      .select("id")
      .eq("capture_id", capture!.id)
      .single();
    expect((await items()).at(-1)).toEqual({
      section: "decision",
      text: "Сортировка на Haiku",
      source: "ai",
      entry_ids: [entry!.id],
    });

    const { data: calls } = await user.client
      .from("ai_calls")
      .select("step, ok")
      .eq("capture_id", capture!.id)
      .order("created_at");
    expect(calls).toEqual([
      { step: "sort", ok: true },
      { step: "context", ok: true },
    ]);
  });

  it("leaves entries waiting for review out", async () => {
    const before = (await items()).length;
    const { data: capture } = await user.client.rpc("create_text_capture", {
      content: "maybe something for engram",
    });
    const ai = mockAi({
      sort: {
        entries: [
          {
            kind: "idea",
            content: "maybe",
            projectSlug: "engram",
            newProjectName: null,
            dueAt: null,
            url: null,
            confidence: 0.4,
          },
        ],
      },
      context: {
        summary: null,
        status: null,
        add: [{ section: "idea", text: "should not appear", from: ["e1"] }],
      },
    });
    await processCapture(user.client, capture!.id, ai);
    expect(await items()).toHaveLength(before);
  });

  it("reports a failed model call without throwing", async () => {
    const { data: entry } = await user.client
      .from("entries")
      .insert({
        user_id: user.id,
        project_id: projectId,
        kind: "note",
        content: "x",
      })
      .select("id")
      .single();
    const ai = mockAi({ context: new Error("overloaded") });
    expect(
      await updateProjectContext(user.client, projectId, [entry!.id], ai),
    ).toBe("failed");
  });

  it("skips an archived project", async () => {
    await user.client
      .from("projects")
      .update({ archived_at: new Date().toISOString() })
      .eq("id", projectId);
    const ai = mockAi({ context: { summary: "nope", status: null, add: [] } });
    expect(
      await updateProjectContext(
        user.client,
        projectId,
        ["00000000-0000-4000-8000-000000000000"],
        ai,
      ),
    ).toBe("skipped");
    await user.client
      .from("projects")
      .update({ archived_at: null })
      .eq("id", projectId);
  });
});
