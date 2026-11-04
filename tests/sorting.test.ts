/** Pure sorting logic: model answer → entry rows, the time prompt, cost. */
import { describe, expect, it } from "vitest";
import { costUsd } from "@/server/ai/pricing";
import {
  describeNow,
  sortedCaptureSchema,
  type SortedCapture,
} from "@/server/ai/sort";
import { toEntryRows } from "@/server/pipeline/entry-rows";

const projects = [
  { id: "p-engram", slug: "engram", name: "Engram" },
  { id: "p-life", slug: "zhizn", name: "Жизнь" },
];

type Entry = SortedCapture["entries"][number];
const entry = (over: Partial<Entry>): Entry => ({
  kind: "note",
  content: "text",
  projectSlug: null,
  newProjectName: null,
  dueAt: null,
  url: null,
  confidence: 0.9,
  ...over,
});
const rows = (...entries: Entry[]) => toEntryRows({ entries }, projects, "raw");

describe("toEntryRows", () => {
  it("files a confident entry into a known project, slug case-insensitive", () => {
    expect(rows(entry({ projectSlug: "Engram" }))[0]).toMatchObject({
      project_id: "p-engram",
      needs_review: false,
    });
  });

  it("flags low confidence and missing or unknown projects", () => {
    const [low, none, unknown] = rows(
      entry({ projectSlug: "engram", confidence: 0.69 }),
      entry({}),
      entry({ projectSlug: "made-up" }),
    );
    expect(low.needs_review).toBe(true);
    expect(none).toMatchObject({ project_id: null, needs_review: true });
    expect(unknown).toMatchObject({ project_id: null, needs_review: true });
  });

  it("uses an existing project when the 'new' name already exists", () => {
    expect(rows(entry({ newProjectName: " жизнь " }))[0]).toMatchObject({
      project_id: "p-life",
      suggested_project_name: null,
    });
  });

  it("keeps a new project only as a suggestion", () => {
    expect(rows(entry({ newProjectName: "Скейт" }))[0]).toMatchObject({
      project_id: null,
      suggested_project_name: "Скейт",
      needs_review: true,
    });
  });

  it("drops invalid dates and non-web URLs, normalises valid ones", () => {
    const [bad, good] = rows(
      entry({ dueAt: "next friday", url: "javascript:alert(1)" }),
      entry({
        dueAt: "2026-11-06T09:00:00+03:00",
        url: "https://supabase.com/docs",
      }),
    );
    expect(bad).toMatchObject({ due_at: null, url: null });
    expect(good).toMatchObject({
      due_at: "2026-11-06T06:00:00.000Z",
      url: "https://supabase.com/docs",
    });
  });

  it("clamps confidence and trims content", () => {
    const [high, nan] = rows(
      entry({ confidence: 7, content: "  hi  " }),
      entry({ confidence: Number.NaN }),
    );
    expect(high).toMatchObject({ confidence: 1, content: "hi" });
    expect(nan.confidence).toBe(0);
  });

  it("keeps the raw text as a note to review when nothing usable came back", () => {
    expect(
      toEntryRows(
        { entries: [entry({ content: "   " })] },
        projects,
        "raw text",
      ),
    ).toEqual([
      {
        kind: "note",
        content: "raw text",
        project_id: null,
        suggested_project_name: null,
        url: null,
        due_at: null,
        confidence: 0,
        needs_review: true,
      },
    ]);
  });

  it("caps the number of entries", () => {
    expect(rows(...Array.from({ length: 15 }, () => entry({})))).toHaveLength(
      10,
    );
  });
});

describe("sortedCaptureSchema", () => {
  it("rejects an unknown kind", () => {
    expect(
      sortedCaptureSchema.safeParse({
        entries: [entry({ kind: "memo" as never })],
      }).success,
    ).toBe(false);
  });
});

describe("describeNow", () => {
  const now = new Date("2026-11-04T12:20:00Z");

  it("shows local time with weekday and offset", () => {
    expect(describeNow(now, "Europe/Istanbul")).toBe(
      "Wednesday, 2026-11-04 15:20, Europe/Istanbul (GMT+03:00)",
    );
  });

  it("falls back to UTC for a missing or unknown zone", () => {
    expect(describeNow(now, null)).toBe(
      "Wednesday, 2026-11-04 12:20, UTC (GMT+00:00)",
    );
    expect(describeNow(now, "Mars/Olympus")).toMatch(/, UTC \(GMT\+00:00\)$/);
  });
});

describe("costUsd", () => {
  const tokens = {
    inputTokens: 1_000_000,
    outputTokens: 100_000,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
  };

  it("prices Sonnet 5.5 at $2 in / $10 out per million", () => {
    expect(costUsd("claude-sonnet-5-5", tokens)).toBeCloseTo(3);
  });

  it("returns 0 for an unknown model", () => {
    expect(costUsd("some-other-model", tokens)).toBe(0);
  });
});
