import { createAnthropic } from "@ai-sdk/anthropic";
import type { LanguageModel } from "ai";
import { serverEnv } from "@/server/env";

export type SortModel = { model: LanguageModel; modelId: string };

/** Claude model by id, or null when no API key is configured. */
export function anthropicModel(modelId: string): SortModel | null {
  if (!serverEnv.ANTHROPIC_API_KEY) return null;
  const anthropic = createAnthropic({ apiKey: serverEnv.ANTHROPIC_API_KEY });
  return { model: anthropic(modelId), modelId };
}

/** The model that sorts captures (`AI_SORT_MODEL`). */
export function sortModel(): SortModel | null {
  return anthropicModel(serverEnv.AI_SORT_MODEL);
}
