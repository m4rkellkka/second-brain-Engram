import { z } from "zod";
import { Constants, type Database } from "@/server/db/database.types";
import { projectNameSchema } from "@/features/projects/new-project";

export type EntryKind = Database["public"]["Enums"]["entry_kind"];

export const ENTRY_KINDS = Constants.public.Enums.entry_kind;

/** Inbox `?kind=` filter. Anything unknown means "all". */
export function parseKindFilter(value: unknown): EntryKind | null {
  const parsed = z.enum(ENTRY_KINDS).safeParse(value);
  return parsed.success ? parsed.data : null;
}

export const assignProjectSchema = z.object({
  entryId: z.uuid(),
  /** `null` takes the entry out of its project. */
  projectId: z.uuid().nullable(),
});

export const assignNewProjectSchema = z.object({
  entryId: z.uuid(),
  name: projectNameSchema,
});

export const entryIdSchema = z.uuid();

export const changeKindSchema = z.object({
  entryId: z.uuid(),
  kind: z.enum(ENTRY_KINDS),
});
