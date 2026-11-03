import type { Metadata } from "next";
import { EngramMark } from "@/components/app-shell/engram-mark";
import { EmptyState } from "@/components/empty-state";

export const metadata: Metadata = { title: "Brain" };

export default function BrainPage() {
  return (
    <EmptyState
      icon={EngramMark}
      title="Your brain is empty"
      description="Every entry becomes a node in a 3D graph, clustered by project."
    />
  );
}
