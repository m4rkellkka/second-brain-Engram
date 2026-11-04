"use client";

import { Suspense, type ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { EngramMark } from "./engram-mark";
import { NAV_ITEMS, isActive } from "./nav-items";

/** Desktop navigation (md and up). `footer` is rendered at the bottom. */
export function Sidebar({ footer }: { footer?: ReactNode }) {
  return (
    <aside className="sticky top-0 hidden h-dvh w-58 shrink-0 flex-col gap-7 border-r bg-panel px-3.5 py-5 md:flex">
      <Link
        href="/capture"
        className="flex items-center gap-2.5 rounded-lg px-2 py-1"
      >
        <EngramMark className="size-5.5 text-primary" />
        <span className="text-base font-semibold tracking-tight">Engram</span>
      </Link>

      <nav aria-label="Main" className="flex flex-col gap-0.5">
        {/* Active item streams in on dynamic routes; see TabBar. */}
        <Suspense fallback={<SidebarLinks pathname={null} />}>
          <CurrentSidebarLinks />
        </Suspense>
      </nav>

      {footer && <div className="mt-auto">{footer}</div>}
    </aside>
  );
}

function CurrentSidebarLinks() {
  return <SidebarLinks pathname={usePathname()} />;
}

function SidebarLinks({ pathname }: { pathname: string | null }) {
  return NAV_ITEMS.map(({ href, label, icon: Icon }) => {
    const active = pathname !== null && isActive(pathname, href);
    return (
      <Link
        key={href}
        href={href}
        aria-current={active ? "page" : undefined}
        className={cn(
          "flex min-h-11 items-center gap-2.5 rounded-[10px] px-2.5 text-sm transition-colors",
          active
            ? "bg-surface-2 font-medium text-foreground"
            : "text-muted-foreground hover:bg-surface hover:text-foreground",
        )}
      >
        <Icon className="size-4.5" />
        {label}
      </Link>
    );
  });
}
