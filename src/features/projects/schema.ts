import { z } from "zod";
import { PROJECT_COLORS, projectNameSchema } from "./new-project";

export const CONTEXT_SECTIONS = ["stack", "decision", "idea"] as const;

export const createProjectSchema = z.object({ name: projectNameSchema });

export const updateProjectSchema = z.object({
  projectId: z.uuid(),
  name: projectNameSchema.optional(),
  color: z.enum(PROJECT_COLORS).optional(),
});

export const archiveProjectSchema = z.object({
  projectId: z.uuid(),
  archived: z.boolean(),
});

/** `null` hands the field back to the AI. */
export const setSummarySchema = z.object({
  projectId: z.uuid(),
  summary: z
    .string()
    .trim()
    .max(2000, "Keep it under 2,000 characters.")
    .nullable(),
});

export const setStatusSchema = z.object({
  projectId: z.uuid(),
  status: z.string().trim().max(60, "Keep it under 60 characters.").nullable(),
});

const itemText = z
  .string()
  .trim()
  .min(1, "Write something first.")
  .max(500, "Keep it under 500 characters.");

export const addContextItemSchema = z.object({
  projectId: z.uuid(),
  section: z.enum(CONTEXT_SECTIONS),
  text: itemText,
});

export const updateContextItemSchema = z.object({
  itemId: z.uuid(),
  text: itemText,
});

export const toggleTaskSchema = z.object({
  entryId: z.uuid(),
  done: z.boolean(),
});
