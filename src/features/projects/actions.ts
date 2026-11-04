"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/server/db/server";
import { findOrCreateProject } from "./create";
import {
  addContextItemSchema,
  archiveProjectSchema,
  createProjectSchema,
  setStatusSchema,
  setSummarySchema,
  toggleTaskSchema,
  updateContextItemSchema,
  updateProjectSchema,
} from "./schema";

export type ProjectActionResult = { ok: true } | { ok: false; message: string };

const FAILED = "Couldn't save. Try again.";

function invalid(error: {
  issues: { message: string }[];
}): ProjectActionResult {
  return { ok: false, message: error.issues[0]?.message ?? FAILED };
}

/** List and project pages both show project data. */
function refresh(): void {
  revalidatePath("/projects", "layout");
  revalidatePath("/inbox");
}

/** One row changed, or the id was not the user's (RLS returns no rows). */
function oneRow(result: {
  data: unknown[] | null;
  error: unknown;
}): ProjectActionResult {
  if (result.error || result.data?.length !== 1)
    return { ok: false, message: FAILED };
  refresh();
  return { ok: true };
}

export async function createProject(input: {
  name: string;
}): Promise<{ ok: true; slug: string } | { ok: false; message: string }> {
  const parsed = createProjectSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, message: parsed.error.issues[0]?.message ?? FAILED };
  }
  const result = await findOrCreateProject(
    await createClient(),
    parsed.data.name,
  );
  if (!result.ok) return result;
  refresh();
  return { ok: true, slug: result.slug };
}

/** Rename or recolor. The slug stays, so links keep working. */
export async function updateProject(input: {
  projectId: string;
  name?: string;
  color?: string;
}): Promise<ProjectActionResult> {
  const parsed = updateProjectSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const { projectId, ...changes } = parsed.data;
  const supabase = await createClient();
  return oneRow(
    await supabase
      .from("projects")
      .update(changes)
      .eq("id", projectId)
      .select("id"),
  );
}

export async function setArchived(input: {
  projectId: string;
  archived: boolean;
}): Promise<ProjectActionResult> {
  const parsed = archiveProjectSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const supabase = await createClient();
  return oneRow(
    await supabase
      .from("projects")
      .update({
        archived_at: parsed.data.archived ? new Date().toISOString() : null,
      })
      .eq("id", parsed.data.projectId)
      .select("id"),
  );
}

/** A hand-written summary wins over the AI; `null` lets the AI update it again. */
export async function setSummary(input: {
  projectId: string;
  summary: string | null;
}): Promise<ProjectActionResult> {
  const parsed = setSummarySchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const { projectId, summary } = parsed.data;
  const supabase = await createClient();
  return oneRow(
    await supabase
      .from("projects")
      .update(
        summary === null
          ? { summary_source: "ai" }
          : {
              summary: summary || null,
              summary_source: "user",
              summary_entry_ids: [],
            },
      )
      .eq("id", projectId)
      .select("id"),
  );
}

export async function setStatus(input: {
  projectId: string;
  status: string | null;
}): Promise<ProjectActionResult> {
  const parsed = setStatusSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const { projectId, status } = parsed.data;
  const supabase = await createClient();
  return oneRow(
    await supabase
      .from("projects")
      .update(
        status === null
          ? { status_source: "ai" }
          : { status: status || null, status_source: "user" },
      )
      .eq("id", projectId)
      .select("id"),
  );
}

export async function addContextItem(input: {
  projectId: string;
  section: string;
  text: string;
}): Promise<ProjectActionResult> {
  const parsed = addContextItemSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getClaims();
  if (!auth?.claims.sub) return { ok: false, message: "Sign in again." };

  const { error } = await supabase.from("project_context_items").insert({
    user_id: auth.claims.sub,
    project_id: parsed.data.projectId,
    section: parsed.data.section,
    text: parsed.data.text,
    source: "user",
  });
  if (error?.code === "23505")
    return { ok: false, message: "It's already on the list." };
  if (error) return { ok: false, message: FAILED };
  refresh();
  return { ok: true };
}

/** Editing an AI item makes it yours. */
export async function updateContextItem(input: {
  itemId: string;
  text: string;
}): Promise<ProjectActionResult> {
  const parsed = updateContextItemSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const supabase = await createClient();
  const result = await supabase
    .from("project_context_items")
    .update({ text: parsed.data.text, source: "user" })
    .eq("id", parsed.data.itemId)
    .select("id");
  if (result.error?.code === "23505")
    return { ok: false, message: "It's already on the list." };
  return oneRow(result);
}

export async function deleteContextItem(
  itemId: string,
): Promise<ProjectActionResult> {
  const parsed = updateContextItemSchema.shape.itemId.safeParse(itemId);
  if (!parsed.success) return { ok: false, message: FAILED };
  const supabase = await createClient();
  return oneRow(
    await supabase
      .from("project_context_items")
      .delete()
      .eq("id", parsed.data)
      .select("id"),
  );
}

export async function toggleTask(input: {
  entryId: string;
  done: boolean;
}): Promise<ProjectActionResult> {
  const parsed = toggleTaskSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const supabase = await createClient();
  return oneRow(
    await supabase
      .from("entries")
      .update({ done_at: parsed.data.done ? new Date().toISOString() : null })
      .eq("id", parsed.data.entryId)
      .eq("kind", "task")
      .select("id"),
  );
}
