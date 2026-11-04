"use server";

import { after } from "next/server";
import { revalidatePath } from "next/cache";
import { sortModel } from "@/server/ai/provider";
import { createClient } from "@/server/db/server";
import {
  processCapture,
  sweepCaptures,
} from "@/server/pipeline/process-capture";
import { captureTextSchema, timeZoneSchema } from "./schema";

export type SavedEntry = { id: string; content: string; createdAt: string };

export type SaveCaptureResult =
  { ok: true; entry: SavedEntry } | { ok: false; message: string };

/**
 * Saves a typed thought and answers at once; AI sorting runs after the
 * response, so capturing never waits for the model.
 */
export async function saveCapture(
  text: string,
  timeZone?: string,
): Promise<SaveCaptureResult> {
  const parsed = captureTextSchema.safeParse(text);
  if (!parsed.success) {
    return {
      ok: false,
      message: parsed.error.issues[0]?.message ?? "Couldn't save.",
    };
  }
  const zone = timeZoneSchema.safeParse(timeZone);

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_text_capture", {
    content: parsed.data,
    timezone: zone.success ? zone.data : undefined,
  });
  if (error || !data?.id) {
    return { ok: false, message: "Couldn't save. Try again." };
  }

  after(async () => {
    const db = await createClient();
    const ai = sortModel();
    await processCapture(db, data.id, ai);
    // Pick up anything an earlier request left unsorted.
    await sweepCaptures(db, ai, 3);
  });

  revalidatePath("/inbox");
  return {
    ok: true,
    entry: {
      id: data.id,
      content: data.raw_text ?? parsed.data,
      createdAt: data.created_at,
    },
  };
}
