/** Mock Claude for pipeline tests: answers sorting and context calls. */
import { MockLanguageModelV4 } from "ai/test";
import type { ContextPatchOutput } from "@/server/ai/context";
import type { SortedCapture } from "@/server/ai/sort";

const EMPTY_PATCH: ContextPatchOutput = {
  summary: null,
  status: null,
  add: [],
};

export function mockAi(answers: {
  sort?: SortedCapture | Error;
  context?: ContextPatchOutput | Error;
}) {
  const model = new MockLanguageModelV4({
    doGenerate: async (options) => {
      const system = options.prompt.find((m) => m.role === "system");
      const isContext =
        typeof system?.content === "string" &&
        system.content.includes("living context");
      const answer = isContext
        ? (answers.context ?? EMPTY_PATCH)
        : answers.sort;
      if (!answer) throw new Error("no mock answer for this call");
      if (answer instanceof Error) throw answer;
      return {
        content: [{ type: "text", text: JSON.stringify(answer) }],
        finishReason: { unified: "stop", raw: undefined },
        usage: {
          inputTokens: {
            total: 1000,
            noCache: 1000,
            cacheRead: undefined,
            cacheWrite: undefined,
          },
          outputTokens: { total: 200, text: 200, reasoning: undefined },
        },
        warnings: [],
      };
    },
  });
  return { model, modelId: "claude-haiku-5-5" };
}
