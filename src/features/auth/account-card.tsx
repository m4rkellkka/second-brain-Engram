import { connection } from "next/server";
import { createClient } from "@/server/db/server";
import { SignOutButton } from "./sign-out-button";

/** Signed-in user and sign-out, shown at the bottom of the desktop sidebar. */
export async function AccountCard() {
  // Request-time only: supabase-js reads the clock, which Cache Components
  // forbids during prerendering.
  await connection();
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const email = data?.claims.email ?? "";

  return (
    <div className="flex items-center gap-2.5 rounded-xl border bg-surface py-1.5 pr-1.5 pl-2.5">
      <span
        aria-hidden="true"
        className="flex size-7.5 shrink-0 items-center justify-center rounded-full bg-surface-2 text-[13px] font-semibold uppercase"
      >
        {email.charAt(0) || "?"}
      </span>
      <span className="min-w-0 flex-1 truncate text-sm" title={email}>
        {email}
      </span>
      <SignOutButton />
    </div>
  );
}

export function AccountCardSkeleton() {
  return <div className="h-14 rounded-xl border bg-surface" />;
}
