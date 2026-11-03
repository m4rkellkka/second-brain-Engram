import { z } from "zod";

/**
 * Every environment variable the app uses is declared and validated here.
 * Document each one in `.env.example`.
 *
 * NEXT_PUBLIC_* values must be read as literal `process.env.NAME` expressions
 * so Next.js can inline them into the client bundle.
 */
const envSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
});

export type Env = z.infer<typeof envSchema>;

export function parseEnv(source: Record<keyof Env, string | undefined>): Env {
  const result = envSchema.safeParse(source);
  if (!result.success) {
    throw new Error(
      `Invalid environment variables:\n${z.prettifyError(result.error)}\nSee .env.example.`,
    );
  }
  return result.data;
}

export const env: Env = parseEnv({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
});
