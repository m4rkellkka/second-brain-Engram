"use server";

import { revalidatePath } from "next/cache";
import {
  pickColor,
  slugify,
  uniqueSlug,
} from "@/features/projects/new-project";
import { after } from "next/server";
import { sortModel } from "@/server/ai/provider";
import { createClient } from "@/server/db/server";
import { sweepCaptures } from "@/server/pipeline/process-capture";
import { updateProjectContext } from "@/server/pipeline/update-context";
import {
  assignNewProjectSchema,
  assignProjectSchema,
  changeKindSchema,
  entryIdSchema,
} from "./schema";

export type InboxActionResult = { ok: true } | { ok: false; message: string };

const MOVE_FAILED = "Couldn't move it. Try again.";

type Supabase = Awaited<ReturnType<typeof createClient>>;

/** After the response: let the entry update its project's live context. */
function refreshContextLater(projectId: string, entryId: string): void {
  after(async () => {
    const db = await createClient();
    await updateProjectContext(db, projectId, [entryId], sortModel());
  });
}

/** Records a manual fix of the AI's sorting; never blocks the fix itself. */
async function recordCorrection(
  supabase: Supabase,
  correction: {
    userId: string;
    entryId: string;
    field: "project" | "kind" | "confirm";
    from: string | null;
    to: string | null;
  },
): Promise<void> {
  const { error } = await supabase.from("entry_corrections").insert({
    user_id: correction.userId,
    entry_id: correction.entryId,
    field: correction.field,
    from_value: correction.from,
    to_value: correction.to,
  });
  if (error) console.error("[inbox] couldn't record correction", error.message);
}

async function setEntryProject(
  supabase: Supabase,
  entryId: string,
  projectId: string | null,
): Promise<InboxActionResult> {
  const { data: before } = await supabase
    .from("entries")
    .select("user_id, project_id")
    .eq("id", entryId)
    .maybeSingle();
  if (!before) return { ok: false, message: MOVE_FAILED };

  // RLS hides other users' entries, so a foreign id updates zero rows,
  // and the composite foreign key rejects another user's project.
  // Picking a project by hand also resolves a "not sure" card.
  const { data, error } = await supabase
    .from("entries")
    .update({ project_id: projectId, needs_review: false })
    .eq("id", entryId)
    .select("id");
  if (error || data.length !== 1) return { ok: false, message: MOVE_FAILED };

  if (before.project_id !== projectId) {
    if (projectId) refreshContextLater(projectId, entryId);
    await recordCorrection(supabase, {
      userId: before.user_id,
      entryId,
      field: "project",
      from: before.project_id,
      to: projectId,
    });
  }
  revalidatePath("/inbox");
  return { ok: true };
}

/** Files an entry into one of the user's projects, or takes it out (`null`). */
export async function assignProject(input: {
  entryId: string;
  projectId: string | null;
}): Promise<InboxActionResult> {
  const parsed = assignProjectSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: MOVE_FAILED };

  const supabase = await createClient();
  return setEntryProject(supabase, parsed.data.entryId, parsed.data.projectId);
}

/**
 * Creates a project from the Inbox picker and files the entry into it.
 * Reuses an active project with the same name instead of making a twin.
 * Stopgap until project management lands in Phase 5.
 */
export async function assignNewProject(input: {
  entryId: string;
  name: string;
}): Promise<InboxActionResult> {
  const parsed = assignNewProjectSchema.safeParse(input);
  if (!parsed.success) {
    return {
      ok: false,
      message: parsed.error.issues[0]?.message ?? MOVE_FAILED,
    };
  }
  const { entryId, name } = parsed.data;

  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getClaims();
  const userId = auth?.claims.sub;
  if (!userId) return { ok: false, message: "Sign in again." };

  const { data: projects, error: listError } = await supabase
    .from("projects")
    .select("id, name, slug, color, archived_at");
  if (listError) return { ok: false, message: MOVE_FAILED };

  const active = projects.filter((project) => !project.archived_at);
  let projectId = active.find(
    (project) => project.name.toLowerCase() === name.toLowerCase(),
  )?.id;

  if (!projectId) {
    const { data: created, error } = await supabase
      .from("projects")
      .insert({
        user_id: userId,
        name,
        slug: uniqueSlug(
          slugify(name),
          projects.map((project) => project.slug),
        ),
        color: pickColor(active.map((project) => project.color)),
      })
      .select("id")
      .single();
    if (error) {
      return { ok: false, message: "Couldn't create the project. Try again." };
    }
    projectId = created.id;
  }

  return setEntryProject(supabase, entryId, projectId);
}

/** "Looks right" on a "not sure" card: keeps the AI's choice. */
export async function confirmEntry(
  entryId: string,
): Promise<InboxActionResult> {
  const parsed = entryIdSchema.safeParse(entryId);
  if (!parsed.success)
    return { ok: false, message: "Couldn't save. Try again." };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("entries")
    .update({ needs_review: false })
    .eq("id", parsed.data)
    .select("user_id, project_id");
  if (error || data.length !== 1) {
    return { ok: false, message: "Couldn't save. Try again." };
  }
  if (data[0].project_id) refreshContextLater(data[0].project_id, parsed.data);
  await recordCorrection(supabase, {
    userId: data[0].user_id,
    entryId: parsed.data,
    field: "confirm",
    from: data[0].project_id,
    to: data[0].project_id,
  });
  revalidatePath("/inbox");
  return { ok: true };
}

/** Fixes the type the AI picked (idea, task, note, link). */
export async function changeKind(input: {
  entryId: string;
  kind: string;
}): Promise<InboxActionResult> {
  const parsed = changeKindSchema.safeParse(input);
  if (!parsed.success)
    return { ok: false, message: "Couldn't change it. Try again." };
  const { entryId, kind } = parsed.data;

  const supabase = await createClient();
  const { data: before } = await supabase
    .from("entries")
    .select("user_id, kind")
    .eq("id", entryId)
    .maybeSingle();
  if (!before) return { ok: false, message: "Couldn't change it. Try again." };

  const { data, error } = await supabase
    .from("entries")
    .update({ kind })
    .eq("id", entryId)
    .select("id");
  if (error || data.length !== 1) {
    return { ok: false, message: "Couldn't change it. Try again." };
  }
  if (before.kind !== kind) {
    await recordCorrection(supabase, {
      userId: before.user_id,
      entryId,
      field: "kind",
      from: before.kind,
      to: kind,
    });
  }
  revalidatePath("/inbox");
  return { ok: true };
}

/** Called when the Inbox shows captures that have waited too long. */
export async function retryPendingCaptures(): Promise<void> {
  after(async () => {
    const db = await createClient();
    await sweepCaptures(db, sortModel(), 5);
  });
}
