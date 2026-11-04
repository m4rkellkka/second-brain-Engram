import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, Json } from "@/server/db/database.types";
import { costUsd, tokenCounts } from "@/server/ai/pricing";
import type { SortModel } from "@/server/ai/provider";
import { sortCapture, type SortProject } from "@/server/ai/sort";
import { toEntryRows, type EntryRow } from "./entry-rows";

type Db = SupabaseClient<Database>;

export const MAX_ATTEMPTS = 3;
/** Fresh captures are handled right after saving; the sweep waits this long. */
const SWEEP_AFTER_MS = 2 * 60_000;
/** A capture stuck in `processing` this long is taken again. */
const STALE_CLAIM_MS = 5 * 60_000;

export type ProcessOutcome = "processed" | "failed" | "skipped";

function contextSummary(context: Json): string | null {
  if (context && typeof context === "object" && !Array.isArray(context)) {
    const summary = context.summary;
    return typeof summary === "string" && summary.trim() ? summary : null;
  }
  return null;
}

/**
 * Pipeline steps 1, 3, 4 and 7 for one capture: claim it, sort it with the
 * model, write the entries, mark it processed. Without a model (no API key)
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
        .select("id, slug, name, context")
        .is("archived_at", null)
        .order("name");
      if (error) throw new Error(`Couldn't load projects: ${error.message}`);

      const forModel: SortProject[] = projects.map((p) => ({
        slug: p.slug,
        name: p.name,
        summary: contextSummary(p.context),
      }));

      modelCalled = true;
      const started = Date.now();
      try {
        const result = await sortCapture({
          model: ai.model,
          text,
          projects: forModel,
          now,
          timeZone: capture.timezone,
        });
        await logCall(
          db,
          capture,
          ai.modelId,
          result.durationMs,
          true,
          result.usage,
        );
        rows = toEntryRows(result.output, projects, text);
      } catch (error) {
        await logCall(db, capture, ai.modelId, Date.now() - started, false);
        throw error;
      }
    }

    const { error } = await db.rpc("apply_sorted_capture", {
      capture_id: capture.id,
      rows: rows as unknown as Json,
    });
    if (error) throw new Error(`Couldn't save entries: ${error.message}`);
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

async function logCall(
  db: Db,
  capture: { id: string; user_id: string },
  modelId: string,
  durationMs: number,
  ok: boolean,
  usage?: Parameters<typeof tokenCounts>[0],
): Promise<void> {
  const tokens = usage
    ? tokenCounts(usage)
    : {
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
      };
  const cost = costUsd(modelId, tokens);
  const { error } = await db.from("ai_calls").insert({
    user_id: capture.user_id,
    capture_id: capture.id,
    step: "sort",
    model: modelId,
    input_tokens: tokens.inputTokens,
    output_tokens: tokens.outputTokens,
    cache_read_tokens: tokens.cacheReadTokens,
    cost_usd: cost,
    duration_ms: Math.round(durationMs),
    ok,
  });
  // Logging must never break sorting.
  if (error) console.error("[pipeline] couldn't log AI call", error.message);
  console.info("[ai] sort", {
    modelId,
    ok,
    durationMs,
    ...tokens,
    costUsd: cost,
  });
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
