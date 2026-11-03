import { LogOut } from "lucide-react";
import { cn } from "@/lib/utils";
import { signOut } from "./actions";

/** Icon-only sign-out button; posts to the signOut Server Action. */
export function SignOutButton({ className }: { className?: string }) {
  return (
    <form action={signOut}>
      <button
        type="submit"
        aria-label="Sign out"
        title="Sign out"
        className={cn(
          "flex size-11 items-center justify-center rounded-[10px] text-muted-foreground transition-colors hover:bg-surface-2 hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none",
          className,
        )}
      >
        <LogOut className="size-4.5" aria-hidden="true" />
      </button>
    </form>
  );
}
