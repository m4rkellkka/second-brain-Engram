import { SignOutButton } from "@/features/auth/sign-out-button";
import { EngramMark } from "./engram-mark";

/** Top bar on mobile (below md): logo and account action. */
export function MobileHeader() {
  return (
    <header className="sticky top-0 z-30 flex items-center justify-between bg-background/90 px-4 pt-[max(0.5rem,env(safe-area-inset-top))] pb-1 backdrop-blur md:hidden">
      <div className="flex items-center gap-2">
        <EngramMark className="size-5 text-primary" />
        <span className="font-semibold">Engram</span>
      </div>
      <SignOutButton className="-mr-2" />
    </header>
  );
}
