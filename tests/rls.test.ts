/**
 * Row Level Security: user B must not read or write user A's rows or files.
 * Runs against the local Supabase stack (`pnpm db:start`, then `pnpm db:reset`).
 */
import { execSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Database } from "@/server/db/database.types";

type Client = SupabaseClient<Database>;

const local = JSON.parse(
  execSync("pnpm --silent supabase status -o json", { encoding: "utf8" }),
) as { API_URL: string; PUBLISHABLE_KEY: string; SECRET_KEY: string };

const noSession = { auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient<Database>(
  local.API_URL,
  local.SECRET_KEY,
  noSession,
);
const anon: Client = createClient<Database>(
  local.API_URL,
  local.PUBLISHABLE_KEY,
  noSession,
);

async function createUser(): Promise<{ id: string; client: Client }> {
  const email = `rls-${randomUUID()}@engram.test`;
  const password = randomUUID();
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error) throw error;
  const client = createClient<Database>(
    local.API_URL,
    local.PUBLISHABLE_KEY,
    noSession,
  );
  const { error: signInError } = await client.auth.signInWithPassword({
    email,
    password,
  });
  if (signInError) throw signInError;
  return { id: data.user.id, client };
}

let a: { id: string; client: Client };
let b: { id: string; client: Client };
const rows = {
  projectId: "",
  captureId: "",
  entryId: "",
  otherEntryId: "",
  audioPath: "",
};

beforeAll(async () => {
  [a, b] = await Promise.all([createUser(), createUser()]);

  const project = await a.client
    .from("projects")
    .insert({
      user_id: a.id,
      name: "A's project",
      slug: "a-project",
      color: "#B79CFF",
    })
    .select("id")
    .single();
  if (project.error) throw project.error;
  rows.projectId = project.data.id;

  const capture = await a.client
    .from("captures")
    .insert({ user_id: a.id, source: "text", raw_text: "secret thought" })
    .select("id")
    .single();
  if (capture.error) throw capture.error;
  rows.captureId = capture.data.id;

  const entries = await a.client
    .from("entries")
    .insert([
      {
        user_id: a.id,
        capture_id: rows.captureId,
        project_id: rows.projectId,
        kind: "idea",
        content: "secret idea",
      },
      { user_id: a.id, kind: "note", content: "another secret" },
    ])
    .select("id");
  if (entries.error) throw entries.error;
  rows.entryId = entries.data[0]!.id;
  rows.otherEntryId = entries.data[1]!.id;

  const link = await a.client.from("entry_links").insert({
    user_id: a.id,
    source_id: rows.entryId,
    target_id: rows.otherEntryId,
    kind: "manual",
  });
  if (link.error) throw link.error;

  rows.audioPath = `${a.id}/${rows.captureId}.webm`;
  const upload = await a.client.storage
    .from("audio")
    .upload(rows.audioPath, new Blob(["fake audio"], { type: "audio/webm" }), {
      contentType: "audio/webm",
    });
  if (upload.error) throw upload.error;
});

afterAll(async () => {
  await admin.storage.from("audio").remove([rows.audioPath]);
  await Promise.all(
    [a?.id, b?.id]
      .filter((id): id is string => Boolean(id))
      .map((id) => admin.auth.admin.deleteUser(id)),
  );
});

describe("owner access", () => {
  it("A can read their own rows", async () => {
    const { data } = await a.client
      .from("entries")
      .select("id")
      .eq("user_id", a.id);
    expect(data).toHaveLength(2);
  });
});

describe("user B cannot read user A's data", () => {
  it.each(["projects", "captures", "entries", "entry_links"] as const)(
    "%s is invisible to B and to anonymous visitors",
    async (table) => {
      for (const client of [b.client, anon]) {
        const { data, error } = await client
          .from(table)
          .select("user_id")
          .eq("user_id", a.id);
        expect(error).toBeNull();
        expect(data).toEqual([]);
      }
    },
  );
});

describe("user B cannot change user A's data", () => {
  it("update affects no rows", async () => {
    const { data } = await b.client
      .from("projects")
      .update({ name: "hacked" })
      .eq("id", rows.projectId)
      .select("id");
    expect(data).toEqual([]);

    const { data: still } = await a.client
      .from("projects")
      .select("name")
      .eq("id", rows.projectId)
      .single();
    expect(still?.name).toBe("A's project");
  });

  it("delete affects no rows", async () => {
    const { data } = await b.client
      .from("entries")
      .delete()
      .eq("id", rows.entryId)
      .select("id");
    expect(data).toEqual([]);

    const { data: still } = await a.client
      .from("entries")
      .select("id")
      .eq("id", rows.entryId);
    expect(still).toHaveLength(1);
  });

  it("insert as A is rejected", async () => {
    const { error } = await b.client.from("projects").insert({
      user_id: a.id,
      name: "forged",
      slug: "forged",
      color: "#B79CFF",
    });
    expect(error?.code).toBe("42501"); // RLS violation
  });

  it("B's own entry cannot point at A's project or capture", async () => {
    const toProject = await b.client.from("entries").insert({
      user_id: b.id,
      project_id: rows.projectId,
      kind: "idea",
      content: "x",
    });
    expect(toProject.error?.code).toBe("23503"); // foreign key violation

    const toCapture = await b.client.from("entries").insert({
      user_id: b.id,
      capture_id: rows.captureId,
      kind: "idea",
      content: "x",
    });
    expect(toCapture.error?.code).toBe("23503");
  });

  it("B cannot link their entry to A's entry", async () => {
    const own = await b.client
      .from("entries")
      .insert({ user_id: b.id, kind: "note", content: "B's note" })
      .select("id")
      .single();
    expect(own.error).toBeNull();

    const { error } = await b.client.from("entry_links").insert({
      user_id: b.id,
      source_id: own.data!.id,
      target_id: rows.entryId,
      kind: "manual",
    });
    expect(error?.code).toBe("23503"); // foreign key violation
  });

  it("B cannot link two of A's entries", async () => {
    const { error } = await b.client.from("entry_links").insert({
      user_id: b.id,
      source_id: rows.otherEntryId, // reverse pair, not taken yet
      target_id: rows.entryId,
      kind: "manual",
    });
    expect(error?.code).toBe("23503");
  });
});

describe("audio storage", () => {
  it("B cannot download A's audio", async () => {
    const { data, error } = await b.client.storage
      .from("audio")
      .download(rows.audioPath);
    expect(data).toBeNull();
    expect(error).not.toBeNull();
  });

  it("B cannot list A's folder", async () => {
    const { data } = await b.client.storage.from("audio").list(a.id);
    expect(data ?? []).toEqual([]);
  });

  it("B cannot upload into A's folder", async () => {
    const { error } = await b.client.storage
      .from("audio")
      .upload(`${a.id}/forged.webm`, new Blob(["x"], { type: "audio/webm" }), {
        contentType: "audio/webm",
      });
    expect(error).not.toBeNull();
  });

  it("A can download their own audio", async () => {
    const { data, error } = await a.client.storage
      .from("audio")
      .download(rows.audioPath);
    expect(error).toBeNull();
    expect(await data?.text()).toBe("fake audio");
  });
});
