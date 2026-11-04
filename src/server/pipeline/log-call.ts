import type { SupabaseClient } from "@supabase/supabase-js";
import type { LanguageModelUsage } from "ai";
import type { Database } from "@/server/db/database.types";
import { costUsd, tokenCounts } from "@/server/ai/pricing";

/** Records one model call with its tokens and cost. Never throws. */
export async function logAiCall(
  db: SupabaseClient<Database>,
  call: {
    userId: string;
    captureId: string | null;
    step: "sort" | "context";
    modelId: string;
    durationMs: number;
    ok: boolean;
    usage?: LanguageModelUsage;
  },
): Promise<void> {
  const tokens = call.usage
    ? tokenCounts(call.usage)
    : {
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
      };
  const cost = costUsd(call.modelId, tokens);
  const { error } = await db.from("ai_calls").insert({
    user_id: call.userId,
    capture_id: call.captureId,
    step: call.step,
    model: call.modelId,
    input_tokens: tokens.inputTokens,
    output_tokens: tokens.outputTokens,
    cache_read_tokens: tokens.cacheReadTokens,
    cost_usd: cost,
    duration_ms: Math.round(call.durationMs),
    ok: call.ok,
  });
  if (error) console.error("[ai] couldn't log call", error.message);
  console.info(`[ai] ${call.step}`, {
    modelId: call.modelId,
    ok: call.ok,
    durationMs: call.durationMs,
    ...tokens,
    costUsd: cost,
  });
}
