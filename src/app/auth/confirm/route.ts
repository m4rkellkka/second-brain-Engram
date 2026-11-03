import { redirect } from "next/navigation";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { createClient } from "@/server/db/server";

/** Custom email template link: works on any device. */
const tokenHashSchema = z.object({
  token_hash: z.string().min(1),
  type: z.enum(["email", "magiclink", "signup"]),
});

/**
 * Default Supabase email link (PKCE). Must be opened in the same browser
 * that requested it, because the code verifier lives in its cookies.
 */
const codeSchema = z.object({ code: z.string().min(1) });

/** Magic link target: verifies the link and starts a session. */
export async function GET(request: NextRequest) {
  const params = Object.fromEntries(request.nextUrl.searchParams);
  const supabase = await createClient();

  const tokenHash = tokenHashSchema.safeParse(params);
  if (tokenHash.success) {
    const { error } = await supabase.auth.verifyOtp(tokenHash.data);
    if (!error) redirect("/capture");
  }

  const pkce = codeSchema.safeParse(params);
  if (pkce.success) {
    const { error } = await supabase.auth.exchangeCodeForSession(
      pkce.data.code,
    );
    if (!error) redirect("/capture");
  }

  redirect("/login?error=link");
}
