import { Suspense } from "react";
import { MobileHeader } from "@/components/app-shell/mobile-header";
import { Sidebar } from "@/components/app-shell/sidebar";
import { TabBar } from "@/components/app-shell/tab-bar";
import { AccountCard, AccountCardSkeleton } from "@/features/auth/account-card";

export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <div className="flex min-h-dvh">
      <Sidebar
        footer={
          // Reads the session cookie, so it streams in behind a boundary.
          <Suspense fallback={<AccountCardSkeleton />}>
            <AccountCard />
          </Suspense>
        }
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <MobileHeader />
        <main className="flex flex-1 flex-col pb-[calc(4.5rem+env(safe-area-inset-bottom))] md:pb-0">
          {children}
        </main>
      </div>
      <TabBar />
    </div>
  );
}
