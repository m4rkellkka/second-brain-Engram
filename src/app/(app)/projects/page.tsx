import type { Metadata } from "next";
import { Suspense } from "react";
import {
  ProjectsList,
  ProjectsListSkeleton,
} from "@/features/projects/projects-list";

export const metadata: Metadata = { title: "Projects" };

export default function ProjectsPage() {
  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 px-4 py-6 md:py-12">
      <h1 className="text-3xl font-semibold tracking-tight">Projects</h1>
      {/* Reads the session, so it streams in at request time. */}
      <Suspense fallback={<ProjectsListSkeleton />}>
        <ProjectsList />
      </Suspense>
    </div>
  );
}
