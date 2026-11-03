import { z } from "zod";

/**
 * Server-only environment variables. Never import this module from a
 * Client Component: these values must not reach the browser.
 * Public variables live in `src/lib/env.ts`. Document each one in `.env.example`.
 */
const emailList = z
  .string()
  .transform((value) =>
    value
      .split(",")
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
  )
  .pipe(z.array(z.email()).min(1, "List at least one email"));

const serverEnvSchema = z.object({
  /** Comma-separated emails allowed to sign in to this instance. */
  ALLOWED_EMAILS: emailList,
});

export type ServerEnv = z.infer<typeof serverEnvSchema>;

export function parseServerEnv(
  source: Record<keyof ServerEnv, string | undefined>,
): ServerEnv {
  const result = serverEnvSchema.safeParse(source);
  if (!result.success) {
    throw new Error(
      `Invalid server environment variables:\n${z.prettifyError(result.error)}\nSee .env.example.`,
    );
  }
  return result.data;
}

export const serverEnv: ServerEnv = parseServerEnv({
  ALLOWED_EMAILS: process.env.ALLOWED_EMAILS,
});
