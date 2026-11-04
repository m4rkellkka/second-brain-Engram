import {
  generateText,
  Output,
  type LanguageModel,
  type LanguageModelUsage,
} from "ai";
import { z } from "zod";

export const CONTEXT_SECTIONS = ["stack", "decision", "idea"] as const;
export type ContextSection = (typeof CONTEXT_SECTIONS)[number];

/** A small patch, never a rewrite. Loose on purpose; cleaned in toContextPatch. */
export const contextPatchSchema = z.object({
  summary: z.string().nullable(),
  status: z.string().nullable(),
  add: z.array(
    z.object({
      section: z.enum(CONTEXT_SECTIONS),
      text: z.string(),
      from: z.array(z.string()),
    }),
  ),
});

export type ContextPatchOutput = z.infer<typeof contextPatchSchema>;

export type ContextSnapshot = {
  name: string;
  summary: string | null;
  status: string | null;
  items: { section: ContextSection; text: string }[];
};

export type ContextEntry = { ref: string; kind: string; content: string };

const SYSTEM = `You keep the living context of one project up to date from new notes.

The user message has the project's current context (summary, status, stack, decisions, open ideas) and new entries just filed into it, each with a ref like e1. Return a small patch, never a rewrite.

- summary: a new 1-3 sentence summary, in the language of the current summary (or of the entries if there is none), only when the new entries change what the project is or where it stands. Otherwise null.
- status: 1-3 words such as "idea", "building", "pilot", "paused", only when the entries clearly change it. Otherwise null.
- add: only new facts from the entries. stack = a technology, tool or service the project uses; decision = a choice that was made; idea = an open idea or possibility for the project. Each under 120 characters, in the entries' language. from = the refs it came from. Skip anything the context already says, even in other words. Tasks are tracked elsewhere: never add tasks.

Most notes change nothing. Then return null, null and an empty list.`;

function describe(project: ContextSnapshot): string {
  const list = (section: ContextSection) => {
    const items = project.items.filter((i) => i.section === section);
    return items.length
      ? items.map((i) => `  - ${i.text}`).join("\n")
      : "  (none)";
  };
  return [
    `Project: ${project.name}`,
    `Summary: ${project.summary ?? "(none)"}`,
    `Status: ${project.status ?? "(none)"}`,
    `Stack:\n${list("stack")}`,
    `Decisions:\n${list("decision")}`,
    `Open ideas:\n${list("idea")}`,
  ].join("\n");
}

export type ContextResult = {
  output: ContextPatchOutput;
  usage: LanguageModelUsage;
  durationMs: number;
};

/** One model call: proposes what the new entries add to the project's context. */
export async function proposeContextPatch(input: {
  model: LanguageModel;
  project: ContextSnapshot;
  entries: ContextEntry[];
}): Promise<ContextResult> {
  const started = Date.now();
  const entries = input.entries
    .map(
      (e) => `<entry ref="${e.ref}" kind="${e.kind}">\n${e.content}\n</entry>`,
    )
    .join("\n");
  const { output, usage } = await generateText({
    model: input.model,
    system: SYSTEM,
    prompt: `${describe(input.project)}\n\nNew entries:\n${entries}`,
    output: Output.object({ schema: contextPatchSchema }),
    providerOptions: { anthropic: { effort: "low" } },
    maxRetries: 1,
  });
  return { output, usage, durationMs: Date.now() - started };
}
