import type { ContextPatchOutput, ContextSection } from "@/server/ai/context";

const MAX_ITEMS = 8;
const MAX_ITEM_LENGTH = 300;
const MAX_SUMMARY_LENGTH = 2000;
const MAX_STATUS_LENGTH = 60;

export type ContextPatch = {
  summary: string | null;
  status: string | null;
  items: { section: ContextSection; text: string; entry_ids: string[] }[];
  /** Entries the summary change came from. */
  entryIds: string[];
};

const key = (section: string, text: string) =>
  `${section}:${text.trim().toLowerCase()}`;

/**
 * Cleans the model's patch: trims and caps text, drops items the context
 * already has or that repeat within the patch, and maps entry refs (e1,
 * e2) to ids. An item without known refs is credited to the whole batch.
 */
export function toContextPatch(
  output: ContextPatchOutput,
  refs: Map<string, string>,
  existing: { section: string; text: string }[],
): ContextPatch {
  const batch = [...refs.values()];
  const seen = new Set(existing.map((i) => key(i.section, i.text)));
  const items: ContextPatch["items"] = [];

  for (const item of output.add) {
    const text = item.text.trim().slice(0, MAX_ITEM_LENGTH);
    if (!text || seen.has(key(item.section, text))) continue;
    seen.add(key(item.section, text));
    const ids = item.from
      .map((ref) => refs.get(ref.trim()))
      .filter((id): id is string => Boolean(id));
    items.push({
      section: item.section,
      text,
      entry_ids: ids.length ? [...new Set(ids)] : batch,
    });
    if (items.length === MAX_ITEMS) break;
  }

  return {
    summary: output.summary?.trim().slice(0, MAX_SUMMARY_LENGTH) || null,
    status: output.status?.trim().slice(0, MAX_STATUS_LENGTH) || null,
    items,
    entryIds: batch,
  };
}

export function isEmptyPatch(patch: ContextPatch): boolean {
  return !patch.summary && !patch.status && patch.items.length === 0;
}
