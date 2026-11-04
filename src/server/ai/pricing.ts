import type { LanguageModelUsage } from "ai";

/** USD per million tokens: input, output, cache read. */
const PRICES: Record<
  string,
  { input: number; output: number; cacheRead: number }
> = {
  "claude-haiku-5-5": { input: 0.1, output: 0.5, cacheRead: 0.01 },
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.2 },
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2 },
};

/** Cache writes cost 1.25x the input price. */
const CACHE_WRITE_FACTOR = 1.25;

export type TokenCounts = {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
};

export function tokenCounts(usage: LanguageModelUsage): TokenCounts {
  const cacheRead = usage.inputTokenDetails.cacheReadTokens ?? 0;
  const cacheWrite = usage.inputTokenDetails.cacheWriteTokens ?? 0;
  const noCache =
    usage.inputTokenDetails.noCacheTokens ??
    Math.max(0, (usage.inputTokens ?? 0) - cacheRead - cacheWrite);
  return {
    inputTokens: noCache + cacheWrite,
    outputTokens: usage.outputTokens ?? 0,
    cacheReadTokens: cacheRead,
    cacheWriteTokens: cacheWrite,
  };
}

/** Cost of one call in USD; 0 for a model without a known price. */
export function costUsd(modelId: string, tokens: TokenCounts): number {
  const price = PRICES[modelId];
  if (!price) return 0;
  const noCache = tokens.inputTokens - tokens.cacheWriteTokens;
  return (
    (noCache * price.input +
      tokens.cacheWriteTokens * price.input * CACHE_WRITE_FACTOR +
      tokens.cacheReadTokens * price.cacheRead +
      tokens.outputTokens * price.output) /
    1_000_000
  );
}
