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

const optional = z
  .string()
  .trim()
  .optional()
  .transform((value) => value || undefined);

const serverEnvSchema = z.object({
  /** Comma-separated emails allowed to sign in to this instance. */
  ALLOWED_EMAILS: emailList,
  /** Anthropic API key for sorting. Without it captures are kept as plain notes. */
  ANTHROPIC_API_KEY: optional,
  /** Claude model that sorts captures. */
  AI_SORT_MODEL: z.string().trim().min(1).default("claude-haiku-5-5"),
  /** Supabase secret key, used only by the cron retry sweep. */
  SUPABASE_SECRET_KEY: optional,
  /** Bearer token Vercel Cron sends to the retry sweep route. */
  CRON_SECRET: optional,
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
  ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
  AI_SORT_MODEL: process.env.AI_SORT_MODEL,
  SUPABASE_SECRET_KEY: process.env.SUPABASE_SECRET_KEY,
  CRON_SECRET: process.env.CRON_SECRET,
});
