import type { Metadata } from "next";
import { FolderClosed } from "lucide-react";
import { EmptyState } from "@/components/empty-state";

export const metadata: Metadata = { title: "Projects" };

export default function ProjectsPage() {
  return (
    <EmptyState
      icon={FolderClosed}
      title="No projects yet"
      description="Projects appear as soon as you capture something about them."
    />
  );
}
