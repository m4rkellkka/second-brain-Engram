import type { Metadata } from "next";
import { Inbox } from "lucide-react";
import { EmptyState } from "@/components/empty-state";

export const metadata: Metadata = { title: "Inbox" };

export default function InboxPage() {
  return (
    <EmptyState
      icon={Inbox}
      title="Inbox is empty"
      description="Everything you capture shows up here, already sorted."
    />
  );
}
