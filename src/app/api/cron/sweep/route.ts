import { timingSafeEqual } from "node:crypto";
import { sortModel } from "@/server/ai/provider";
import { createAdminClient } from "@/server/db/admin";
import { serverEnv } from "@/server/env";
import { sweepCaptures } from "@/server/pipeline/process-capture";

function authorized(header: string | null, secret: string): boolean {
  const expected = Buffer.from(`Bearer ${secret}`);
  const given = Buffer.from(header ?? "");
  return given.length === expected.length && timingSafeEqual(given, expected);
}

/**
 * Daily backstop for captures that were never sorted (Vercel Cron; the
 * Hobby plan allows one run a day). Normal retries happen after each save.
 */
export async function GET(request: Request) {
  const secret = serverEnv.CRON_SECRET;
  const admin = createAdminClient();
  if (!secret || !admin) {
    return Response.json({ error: "Cron is not configured" }, { status: 503 });
  }
  if (!authorized(request.headers.get("authorization"), secret)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const counts = await sweepCaptures(admin, sortModel(), 20);
  return Response.json(counts);
}
