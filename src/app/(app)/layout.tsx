import { Sidebar } from "@/components/app-shell/sidebar";
import { TabBar } from "@/components/app-shell/tab-bar";

export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <div className="flex min-h-dvh">
      <Sidebar />
      <main className="flex min-w-0 flex-1 flex-col pb-[calc(4.5rem+env(safe-area-inset-bottom))] md:pb-0">
        {children}
      </main>
      <TabBar />
    </div>
  );
}
