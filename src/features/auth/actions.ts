"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/server/db/server";
import { serverEnv } from "@/server/env";

export type LoginState =
  | { status: "idle" }
  | { status: "sent"; email: string }
  | { status: "error"; message: string };

const loginSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email()),
});

/** Sends a magic link to an allowed email. */
export async function sendMagicLink(
  _previous: LoginState,
  formData: FormData,
): Promise<LoginState> {
  const parsed = loginSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) {
    return { status: "error", message: "Enter a valid email address." };
  }
  const { email } = parsed.data;

  if (!serverEnv.ALLOWED_EMAILS.includes(email)) {
    return {
      status: "error",
      message: "This email can't sign in to this Engram instance.",
    };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: `${await requestOrigin()}/auth/confirm` },
  });

  if (error) {
    const message =
      error.code === "over_email_send_rate_limit"
        ? "Too many emails sent. Wait a few minutes and try again."
        : "Couldn't send the link. Try again.";
    return { status: "error", message };
  }
  return { status: "sent", email };
}

export async function signOut() {
  const supabase = await createClient();
  // Only this device; sessions on the phone or laptop stay signed in.
  await supabase.auth.signOut({ scope: "local" });
  redirect("/login");
}

/**
 * The origin the user is on (localhost, LAN IP or the deployed domain), so the
 * magic link brings them back to the same place. Supabase only accepts
 * origins listed in its redirect allow-list and falls back to the Site URL.
 */
async function requestOrigin(): Promise<string> {
  const h = await headers();
  const origin = h.get("origin");
  if (origin) return origin;
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "localhost:3000";
  const proto = h.get("x-forwarded-proto") ?? "http";
  return `${proto}://${host}`;
}
