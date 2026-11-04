import {
  generateText,
  Output,
  type LanguageModel,
  type LanguageModelUsage,
} from "ai";
import { z } from "zod";
import { Constants } from "@/server/db/database.types";

/**
 * What the model returns. Kept loose on purpose (no formats or ranges):
 * dates, URLs and confidence are checked when entries are built, so one
 * odd field never fails the whole capture.
 */
export const sortedCaptureSchema = z.object({
  entries: z.array(
    z.object({
      kind: z.enum(Constants.public.Enums.entry_kind),
      content: z.string(),
      projectSlug: z.string().nullable(),
      newProjectName: z.string().nullable(),
      dueAt: z.string().nullable(),
      url: z.string().nullable(),
      confidence: z.number(),
    }),
  ),
});

export type SortedCapture = z.infer<typeof sortedCaptureSchema>;

export type SortProject = {
  slug: string;
  name: string;
  summary: string | null;
};

// Stable across calls so it can be cached; everything variable goes in the
// user message.
const SYSTEM = `You file a person's quick notes into their second brain.

The user message has their projects, the current time and one capture: something they typed or said in a hurry. Return the entries it contains.

Entries
- Usually a capture is one entry. Split it only when it holds clearly separate thoughts, e.g. two unrelated tasks.
- content: the thought, cleaned up and short, in the capture's own language. Never translate. Drop filler words, keep every fact, name and number.
- kind: "task" for something to do, "idea" for a possibility or plan, "link" when the point is a URL or an article to read, "note" for everything else (facts, observations, summaries).

Project
- projectSlug: the slug of the project the entry belongs to, only from the given list. null if none fits.
- newProjectName: when no project fits but the entry clearly belongs to a recurring area of life or work, a short name for a new project (in the capture's language). Otherwise null. Never both a slug and a new name.

Details
- dueAt: only for a task with a time or date, absolute or relative ("tomorrow", "on Friday", "в пятницу"). Resolve it against the current time in the person's time zone and return ISO 8601 with the UTC offset. A date without a time means 09:00 local. Otherwise null.
- url: a URL from the capture, if any. Otherwise null.
- confidence: from 0 to 1, how sure you are about both kind and project together. Use less than 0.7 when the project is a guess.`;

/** "Wednesday, 2026-11-04 15:20, Europe/Istanbul (GMT+03:00)". */
export function describeNow(now: Date, timeZone: string | null): string {
  let zone = timeZone ?? "UTC";
  try {
    new Intl.DateTimeFormat("en", { timeZone: zone });
  } catch {
    zone = "UTC";
  }
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      weekday: "long",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
      timeZoneName: "longOffset",
    })
      .formatToParts(now)
      .map((part) => [part.type, part.value]),
  );
  return `${parts.weekday}, ${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}, ${zone} (${parts.timeZoneName})`;
}

export type SortResult = {
  output: SortedCapture;
  usage: LanguageModelUsage;
  durationMs: number;
};

/** One model call: splits a capture into entries with kind, project and dates. */
export async function sortCapture(input: {
  model: LanguageModel;
  text: string;
  projects: SortProject[];
  now: Date;
  timeZone: string | null;
}): Promise<SortResult> {
  const started = Date.now();
  const projects = input.projects.length
    ? input.projects
        .map(
          (p) => `- ${p.slug}: ${p.name}${p.summary ? ` — ${p.summary}` : ""}`,
        )
        .join("\n")
    : "(no projects yet)";

  const { output, usage } = await generateText({
    model: input.model,
    system: SYSTEM,
    prompt: `Projects:\n${projects}\n\nCurrent time: ${describeNow(input.now, input.timeZone)}\n\nCapture:\n<capture>\n${input.text}\n</capture>`,
    output: Output.object({ schema: sortedCaptureSchema }),
    // Sorting is a simple, high-volume task: low effort keeps it fast and cheap.
    providerOptions: { anthropic: { effort: "low" } },
    maxRetries: 1,
  });

  return { output, usage, durationMs: Date.now() - started };
}
