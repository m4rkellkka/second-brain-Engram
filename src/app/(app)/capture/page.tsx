import type { Metadata } from "next";
import { Mic } from "lucide-react";
import { EmptyState } from "@/components/empty-state";

export const metadata: Metadata = { title: "Capture" };

export default function CapturePage() {
  return (
    <EmptyState
      icon={Mic}
      title="What's on your mind?"
      description="Type or talk. Engram will sort it into the right project."
    />
  );
}
