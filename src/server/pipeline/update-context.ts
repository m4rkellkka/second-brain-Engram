import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, Json } from "@/server/db/database.types";
import { proposeContextPatch, type ContextSection } from "@/server/ai/context";
import type { SortModel } from "@/server/ai/provider";
import { isEmptyPatch, toContextPatch } from "./context-patch";
import { logAiCall } from "./log-call";

type Db = SupabaseClient<Database>;

export type ContextOutcome = "updated" | "unchanged" | "skipped" | "failed";

/**
 * Pipeline step 6: lets the model add what new entries say to a project's
 * live context. Hand-written summary and status are kept by the database
 * function. A failure is logged and never undoes the entries.
 */
export async function updateProjectContext(
  db: Db,
  projectId: string,
  entryIds: string[],
  ai: SortModel | null,
  captureId: string | null = null,
): Promise<ContextOutcome> {
  if (!ai || entryIds.length === 0) return "skipped";

  const [project, items, entries] = await Promise.all([
    db
      .from("projects")
      .select("id, user_id, name, summary, status, archived_at")
      .eq("id", projectId)
      .maybeSingle(),
    db
      .from("project_context_items")
      .select("section, text")
      .eq("project_id", projectId)
      .order("created_at"),
    db
      .from("entries")
      .select("id, kind, content")
      .eq("project_id", projectId)
      .in("id", entryIds)
      .order("created_at"),
  ]);
  if (
    !project.data ||
    project.data.archived_at ||
    items.error ||
    entries.error
  ) {
    return "skipped";
  }
  if (entries.data.length === 0) return "skipped";

  const refs = new Map(entries.data.map((e, i) => [`e${i + 1}`, e.id]));
  const log = {
    userId: project.data.user_id,
    captureId,
    step: "context" as const,
    modelId: ai.modelId,
  };

  let result;
  const started = Date.now();
  try {
    result = await proposeContextPatch({
      model: ai.model,
      project: {
        name: project.data.name,
        summary: project.data.summary,
        status: project.data.status,
        items: items.data.map((i) => ({
          section: i.section as ContextSection,
          text: i.text,
        })),
      },
      entries: entries.data.map((e, i) => ({
        ref: `e${i + 1}`,
        kind: e.kind,
        content: e.content,
      })),
    });
  } catch (error) {
    console.error(
      `[context] model call failed for project ${projectId}`,
      error,
    );
    await logAiCall(db, {
      ...log,
      durationMs: Date.now() - started,
      ok: false,
    });
    return "failed";
  }
  await logAiCall(db, {
    ...log,
    durationMs: result.durationMs,
    ok: true,
    usage: result.usage,
  });

  const patch = toContextPatch(result.output, refs, items.data);
  if (isEmptyPatch(patch)) return "unchanged";

  const { error } = await db.rpc("apply_context_patch", {
    project_id: projectId,
    new_summary: patch.summary ?? undefined,
    new_status: patch.status ?? undefined,
    items: patch.items as unknown as Json,
    entry_ids: patch.entryIds,
  });
  if (error) {
    console.error(
      `[context] couldn't apply patch to ${projectId}`,
      error.message,
    );
    return "failed";
  }
  return "updated";
}
