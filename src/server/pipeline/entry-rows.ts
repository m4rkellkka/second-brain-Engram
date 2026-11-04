import type { Database } from "@/server/db/database.types";
import type { SortedCapture } from "@/server/ai/sort";

/** Below this the entry gets a "not sure" card in the Inbox. */
export const REVIEW_THRESHOLD = 0.7;
const MAX_ENTRIES = 10;
const MAX_CONTENT = 10_000;
const MAX_PROJECT_NAME = 60;

type EntryKind = Database["public"]["Enums"]["entry_kind"];

/** Shape `apply_sorted_capture` expects for each entry. */
export type EntryRow = {
  kind: EntryKind;
  content: string;
  project_id: string | null;
  suggested_project_name: string | null;
  url: string | null;
  due_at: string | null;
  confidence: number;
  needs_review: boolean;
};

export type KnownProject = { id: string; slug: string; name: string };

function cleanUrl(value: string | null): string | null {
  if (!value) return null;
  try {
    const url = new URL(value.trim());
    return url.protocol === "http:" || url.protocol === "https:"
      ? url.href
      : null;
  } catch {
    return null;
  }
}

function cleanDate(value: string | null): string | null {
  if (!value) return null;
  const time = Date.parse(value);
  return Number.isNaN(time) ? null : new Date(time).toISOString();
}

function clamp01(value: number): number {
  return Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
}

/**
 * Turns the model's answer into entry rows. Unknown slugs are dropped,
 * a "new project" that already exists by name is used as is, and anything
 * unsure or without a project is flagged for review. An empty answer
 * keeps the raw text as one note, so the capture is never lost.
 */
export function toEntryRows(
  sorted: SortedCapture,
  projects: KnownProject[],
  rawText: string,
): EntryRow[] {
  const bySlug = new Map(projects.map((p) => [p.slug.toLowerCase(), p]));
  const byName = new Map(projects.map((p) => [p.name.trim().toLowerCase(), p]));

  const rows = sorted.entries
    .filter((entry) => entry.content.trim())
    .slice(0, MAX_ENTRIES)
    .map((entry): EntryRow => {
      const newName =
        entry.newProjectName?.trim().slice(0, MAX_PROJECT_NAME) || null;
      const project =
        (entry.projectSlug &&
          bySlug.get(entry.projectSlug.trim().toLowerCase())) ||
        (newName && byName.get(newName.toLowerCase())) ||
        null;
      const confidence = clamp01(entry.confidence);
      return {
        kind: entry.kind,
        content: entry.content.trim().slice(0, MAX_CONTENT),
        project_id: project?.id ?? null,
        suggested_project_name: project ? null : newName,
        url: cleanUrl(entry.url),
        due_at: cleanDate(entry.dueAt),
        confidence,
        needs_review: !project || confidence < REVIEW_THRESHOLD,
      };
    });

  if (rows.length > 0) return rows;
  return [
    {
      kind: "note",
      content: rawText.slice(0, MAX_CONTENT),
      project_id: null,
      suggested_project_name: null,
      url: null,
      due_at: null,
      confidence: 0,
      needs_review: true,
    },
  ];
}
