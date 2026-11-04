import type { Metadata } from "next";
import { Suspense } from "react";
import {
  ProjectView,
  ProjectViewSkeleton,
} from "@/features/projects/project-view";

export const metadata: Metadata = { title: "Project" };

export default function ProjectPage({ params }: PageProps<"/projects/[slug]">) {
  return (
    <Suspense fallback={<ProjectViewSkeleton />}>
      <ProjectView params={params} />
    </Suspense>
  );
}
