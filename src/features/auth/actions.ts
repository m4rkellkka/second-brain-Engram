"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/server/db/server";
import { serverEnv } from "@/server/env";

/**
 * `email` is sent back on errors: React resets the form after every action,
 * and the field is refilled from it so only the password has to be retyped.
 */
export type LoginState =
  { status: "idle" } | { status: "error"; message: string; email: string };

const loginSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email()),
  password: z.string().min(1).max(256),
});

const WRONG_CREDENTIALS = "Wrong email or password.";

/** Signs in with email and password, then opens Capture. */
export async function signIn(
  _previous: LoginState,
  formData: FormData,
): Promise<LoginState> {
  const rawEmail = formData.get("email");
  const typedEmail = typeof rawEmail === "string" ? rawEmail : "";
  const parsed = loginSchema.safeParse({
    email: rawEmail,
    password: formData.get("password"),
  });
  if (!parsed.success) {
    return {
      status: "error",
      message: "Enter your email and password.",
      email: typedEmail,
    };
  }
  const { email, password } = parsed.data;

  // Same message as a wrong password, so the form doesn't reveal who may sign in.
  if (!serverEnv.ALLOWED_EMAILS.includes(email)) {
    return { status: "error", message: WRONG_CREDENTIALS, email: typedEmail };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    const message =
      error.code === "invalid_credentials"
        ? WRONG_CREDENTIALS
        : error.status === 429
          ? "Too many attempts. Wait a few minutes and try again."
          : "Couldn't sign in. Try again.";
    return { status: "error", message, email: typedEmail };
  }

  redirect("/capture");
}

export async function signOut() {
  const supabase = await createClient();
  // Only this device; sessions on the phone or laptop stay signed in.
  await supabase.auth.signOut({ scope: "local" });
  redirect("/login");
}
