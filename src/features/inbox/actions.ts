"use server";

import { revalidatePath } from "next/cache";
import {
  pickColor,
  slugify,
  uniqueSlug,
} from "@/features/projects/new-project";
import { createClient } from "@/server/db/server";
import { assignNewProjectSchema, assignProjectSchema } from "./schema";

export type InboxActionResult = { ok: true } | { ok: false; message: string };

const MOVE_FAILED = "Couldn't move it. Try again.";

type Supabase = Awaited<ReturnType<typeof createClient>>;

async function setEntryProject(
  supabase: Supabase,
  entryId: string,
  projectId: string | null,
): Promise<InboxActionResult> {
  // RLS hides other users' entries, so a foreign id updates zero rows,
  // and the composite foreign key rejects another user's project.
  const { data, error } = await supabase
    .from("entries")
    .update({ project_id: projectId })
    .eq("id", entryId)
    .select("id");
  if (error || data.length !== 1) return { ok: false, message: MOVE_FAILED };

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
