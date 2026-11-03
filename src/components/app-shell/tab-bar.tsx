"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { NAV_ITEMS, isActive } from "./nav-items";

/** Mobile bottom navigation (below md). Respects the iPhone home indicator. */
export function TabBar() {
  const pathname = usePathname();

  return (
    <nav
      aria-label="Tabs"
      className="fixed inset-x-0 bottom-0 z-40 grid grid-cols-5 border-t bg-panel px-2 pt-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] md:hidden"
    >
      {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
        const active = isActive(pathname, href);
        return (
          <Link
            key={href}
            href={href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "flex min-h-11 flex-col items-center justify-center gap-1 rounded-[10px] text-[11px]",
              active ? "font-medium text-primary-text" : "text-subtle",
            )}
          >
            <Icon className="size-5.5" />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
