import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, Json } from "@/server/db/database.types";
import type { SortModel } from "@/server/ai/provider";
import { sortCapture, type SortProject } from "@/server/ai/sort";
import { toEntryRows, type EntryRow } from "./entry-rows";
import { logAiCall } from "./log-call";
import { updateProjectContext } from "./update-context";

type Db = SupabaseClient<Database>;

export const MAX_ATTEMPTS = 3;
/** Fresh captures are handled right after saving; the sweep waits this long. */
const SWEEP_AFTER_MS = 2 * 60_000;
/** A capture stuck in `processing` this long is taken again. */
const STALE_CLAIM_MS = 5 * 60_000;

export type ProcessOutcome = "processed" | "failed" | "skipped";

/**
 * Pipeline steps 1, 3, 4, 6 and 7 for one capture: claim it, sort it with
 * the model, write the entries, update the touched projects' context. Without a model (no API key)
 * the text is kept as a plain note, as before AI sorting.
 */
export async function processCapture(
  db: Db,
  captureId: string,
  ai: SortModel | null,
  now: Date = new Date(),
): Promise<ProcessOutcome> {
  const { data: capture } = await db.rpc("claim_capture", {
    capture_id: captureId,
    max_attempts: MAX_ATTEMPTS,
  });
  if (!capture?.id) return "skipped";
  const text = capture.raw_text ?? "";

  let modelCalled = false;
  try {
    let rows: EntryRow[];
    if (!ai) {
      rows = [
        {
          kind: "note",
          content: text,
          project_id: null,
          suggested_project_name: null,
          url: null,
          due_at: null,
          confidence: 0,
          needs_review: false,
        },
      ];
    } else {
      const { data: projects, error } = await db
        .from("projects")
        .select("id, slug, name, summary")
        .is("archived_at", null)
        .order("name");
      if (error) throw new Error(`Couldn't load projects: ${error.message}`);

      const forModel: SortProject[] = projects.map((p) => ({
        slug: p.slug,
        name: p.name,
        summary: p.summary,
      }));

      modelCalled = true;
      const log = {
        userId: capture.user_id,
        captureId: capture.id,
        step: "sort" as const,
        modelId: ai.modelId,
      };
      const started = Date.now();
      try {
        const result = await sortCapture({
          model: ai.model,
          text,
          projects: forModel,
          now,
          timeZone: capture.timezone,
        });
        await logAiCall(db, {
          ...log,
          durationMs: result.durationMs,
          ok: true,
          usage: result.usage,
        });
        rows = toEntryRows(result.output, projects, text);
      } catch (error) {
        await logAiCall(db, {
          ...log,
          durationMs: Date.now() - started,
          ok: false,
        });
        throw error;
      }
    }

    const { data: saved, error } = await db.rpc("apply_sorted_capture", {
      capture_id: capture.id,
      rows: rows as unknown as Json,
    });
    if (error) throw new Error(`Couldn't save entries: ${error.message}`);

    // Step 6: confident entries update their project's live context.
    // Entries waiting for review wait until the user confirms them.
    const byProject = new Map<string, string[]>();
    for (const entry of saved ?? []) {
      if (!entry.project_id || entry.needs_review) continue;
      byProject.set(entry.project_id, [
        ...(byProject.get(entry.project_id) ?? []),
        entry.id,
      ]);
    }
    for (const [projectId, entryIds] of byProject) {
      await updateProjectContext(db, projectId, entryIds, ai, capture.id);
    }
    return "processed";
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[pipeline] capture ${capture.id} failed`, {
      attempt: capture.attempts,
      modelCalled,
      message,
    });
    await db.rpc("fail_capture", {
      capture_id: capture.id,
      message,
      max_attempts: MAX_ATTEMPTS,
    });
    return "failed";
  }
}

/**
 * Retries captures that were not sorted: pending ones nobody picked up,
 * failed ones after a pause, and ones stuck in `processing`.
 */
export async function sweepCaptures(
  db: Db,
  ai: SortModel | null,
  limit = 5,
  now: Date = new Date(),
): Promise<Record<ProcessOutcome, number>> {
  const cutoff = new Date(now.getTime() - SWEEP_AFTER_MS).toISOString();
  const stale = new Date(now.getTime() - STALE_CLAIM_MS).toISOString();
  const { data, error } = await db
    .from("captures")
    .select("id")
    .lt("attempts", MAX_ATTEMPTS)
    .or(
      `and(status.eq.pending,created_at.lt.${cutoff}),and(status.eq.failed,claimed_at.lt.${cutoff}),and(status.eq.processing,claimed_at.lt.${stale})`,
    )
    .order("created_at")
    .limit(limit);

  const counts: Record<ProcessOutcome, number> = {
    processed: 0,
    failed: 0,
    skipped: 0,
  };
  if (error) {
    console.error("[pipeline] sweep query failed", error.message);
    return counts;
  }
  for (const { id } of data) {
    counts[await processCapture(db, id, ai, now)] += 1;
  }
  return counts;
}
