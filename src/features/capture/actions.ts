"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/server/db/server";
import { captureTextSchema } from "./schema";

export type SavedEntry = { id: string; content: string; createdAt: string };

export type SaveCaptureResult =
  { ok: true; entry: SavedEntry } | { ok: false; message: string };

/** Saves a typed thought as a capture with one `note` entry (no AI yet). */
export async function saveCapture(text: string): Promise<SaveCaptureResult> {
  const parsed = captureTextSchema.safeParse(text);
  if (!parsed.success) {
    return {
      ok: false,
      message: parsed.error.issues[0]?.message ?? "Couldn't save.",
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_text_capture", {
    content: parsed.data,
  });
  if (error || !data) {
    return { ok: false, message: "Couldn't save. Try again." };
  }

  revalidatePath("/inbox");
  return {
    ok: true,
    entry: { id: data.id, content: data.content, createdAt: data.created_at },
  };
}
