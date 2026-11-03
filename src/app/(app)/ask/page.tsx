import type { Metadata } from "next";
import { MessageCircle } from "lucide-react";
import { EmptyState } from "@/components/empty-state";

export const metadata: Metadata = { title: "Ask" };

export default function AskPage() {
  return (
    <EmptyState
      icon={MessageCircle}
      title="Ask your brain"
      description="Ask anything about your notes. Answers cite the entries they come from."
    />
  );
}
