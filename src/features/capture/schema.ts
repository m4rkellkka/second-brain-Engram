import { z } from "zod";

/** Limit shared with the `create_text_capture` database function. */
export const MAX_CAPTURE_LENGTH = 10_000;

export const captureTextSchema = z
  .string()
  .trim()
  .min(1, "Write something first.")
  .max(MAX_CAPTURE_LENGTH, "That's too long: 10,000 characters max.");

/** IANA time zone from the browser, used to resolve "tomorrow" or "Friday". */
export const timeZoneSchema = z
  .string()
  .trim()
  .min(1)
  .max(64)
  .refine((zone) => {
    try {
      new Intl.DateTimeFormat("en", { timeZone: zone });
      return true;
    } catch {
      return false;
    }
  }, "Unknown time zone");
