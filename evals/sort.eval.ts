/**
 * Sorting eval: runs real captures through the model and checks that each
 * lands in the expected project. Fixtures: evals/fixtures/sort.local.json
 * (private, git-ignored) or the example file.
 *
 *   pnpm eval:sort                                  # Claude Haiku 5.5
 *   EVAL_MODEL=claude-sonnet-5-5 pnpm eval:sort     # the app's model
 */
import { existsSync, readFileSync } from "node:fs";
import { createAnthropic } from "@ai-sdk/anthropic";
import { expect, it } from "vitest";
import { costUsd, tokenCounts } from "@/server/ai/pricing";
import { sortCapture, type SortProject } from "@/server/ai/sort";
import { toEntryRows } from "@/server/pipeline/entry-rows";

type Fixtures = {
  projects: SortProject[];
  captures: { text: string; project: string | null }[];
};

const LOCAL = "evals/fixtures/sort.local.json";
const file = existsSync(LOCAL) ? LOCAL : "evals/fixtures/sort.example.json";
const fixtures = JSON.parse(readFileSync(file, "utf8")) as Fixtures;
const modelId = process.env.EVAL_MODEL ?? "claude-haiku-5-5";
/** Spec bar: 17 of 20 in the right project. */
const PASS_RATE = 0.85;

it(`sorts the captures in ${file} with ${modelId}`, async () => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("Set ANTHROPIC_API_KEY in .env.local first.");
  const model = createAnthropic({ apiKey })(modelId);
  // Slugs double as ids here, so a row's project_id is the expected slug.
  const projects = fixtures.projects.map((p) => ({ ...p, id: p.slug }));

  let right = 0;
  let cost = 0;
  let ms = 0;
  for (const capture of fixtures.captures) {
    const result = await sortCapture({
      model,
      text: capture.text,
      projects: fixtures.projects,
      now: new Date(),
      timeZone: "Europe/Istanbul",
    });
    const rows = toEntryRows(result.output, projects, capture.text);
    const got = rows[0]?.project_id ?? null;
    const ok = got === capture.project;
    if (ok) right += 1;
    cost += costUsd(modelId, tokenCounts(result.usage));
    ms += result.durationMs;
    const detail = rows
      .map(
        (r) =>
          `${r.kind} ${r.confidence.toFixed(2)}${r.needs_review ? " review" : ""}`,
      )
      .join(", ");
    console.log(
      `${ok ? "PASS" : "FAIL"} ${capture.text.slice(0, 60)}\n     expected ${capture.project ?? "none"}, got ${got ?? "none"} (${detail})`,
    );
  }

  const n = fixtures.captures.length;
  console.log(
    `\n${right}/${n} right · $${(cost / n).toFixed(5)} and ${Math.round(ms / n)} ms per capture · total $${cost.toFixed(4)}`,
  );
  expect(right / n).toBeGreaterThanOrEqual(PASS_RATE);
});
