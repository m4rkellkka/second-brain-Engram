import Link from "next/link";
import { connection } from "next/server";
import { ChevronRight } from "lucide-react";
import { formatAge } from "@/features/inbox/format-age";
import { createClient } from "@/server/db/server";
import { NewProjectForm } from "./new-project-form";

type Row = {
  id: string;
  name: string;
  slug: string;
  color: string;
  status: string | null;
  context_updated_at: string | null;
  created_at: string;
};

/** All projects with open-task and entry counts; archived ones folded away. */
export async function ProjectsList() {
  await connection();
  const supabase = await createClient();
  const [projects, entries] = await Promise.all([
    supabase
      .from("projects")
      .select(
        "id, name, slug, color, status, context_updated_at, created_at, archived_at",
      )
      .order("name"),
    supabase
      .from("entries")
      .select("project_id, kind, done_at")
      .not("project_id", "is", null),
  ]);

  if (projects.error || entries.error) {
    return (
      <p role="alert" className="text-sm text-destructive">
        Couldn&apos;t load projects. Reopen the app to try again.
      </p>
    );
  }

  const counts = new Map<string, { entries: number; openTasks: number }>();
  for (const entry of entries.data) {
    if (!entry.project_id) continue;
    const count = counts.get(entry.project_id) ?? { entries: 0, openTasks: 0 };
    count.entries += 1;
    if (entry.kind === "task" && !entry.done_at) count.openTasks += 1;
    counts.set(entry.project_id, count);
  }

  const active = projects.data.filter((p) => !p.archived_at);
  const archived = projects.data.filter((p) => p.archived_at);
  const now = new Date();

  const card = (project: Row) => {
    const count = counts.get(project.id) ?? { entries: 0, openTasks: 0 };
    const updated = project.context_updated_at ?? project.created_at;
    return (
      <li key={project.id}>
        <Link
          href={`/projects/${project.slug}`}
          className="flex min-h-16 items-center gap-3 rounded-card border bg-surface px-4 py-3.5 transition-colors hover:border-border-strong"
        >
          <span
            aria-hidden="true"
            className="size-3 shrink-0 rounded-full"
            style={{ backgroundColor: project.color }}
          />
          <span className="flex min-w-0 flex-1 flex-col gap-0.5">
            <span className="flex items-center gap-2">
              <span className="truncate font-medium">{project.name}</span>
              {project.status && (
                <span className="shrink-0 rounded-full bg-surface-2 px-2 py-0.5 font-mono text-[11px] text-muted-foreground">
                  {project.status}
                </span>
              )}
            </span>
            <span className="text-xs text-subtle">
              {count.openTasks} open {count.openTasks === 1 ? "task" : "tasks"}{" "}
              · {count.entries} {count.entries === 1 ? "entry" : "entries"} ·
              updated {formatAge(new Date(updated), now)}
            </span>
          </span>
          <ChevronRight
            className="size-4 shrink-0 text-subtle"
            aria-hidden="true"
          />
        </Link>
      </li>
    );
  };

  return (
    <>
      <NewProjectForm />
      {active.length === 0 ? (
        <p className="rounded-card border border-dashed px-6 py-12 text-center text-muted-foreground">
          No projects yet. Create one, or let the AI suggest them from your
          captures.
        </p>
      ) : (
        <ul className="flex flex-col gap-2.5">{active.map(card)}</ul>
      )}
      {archived.length > 0 && (
        <details className="flex flex-col gap-2.5">
          <summary className="flex min-h-11 cursor-pointer items-center font-mono text-[11px] tracking-[0.08em] text-subtle">
            ARCHIVED · {archived.length}
          </summary>
          <ul className="mt-2.5 flex flex-col gap-2.5 opacity-70">
            {archived.map(card)}
          </ul>
        </details>
      )}
    </>
  );
}

export function ProjectsListSkeleton() {
  return (
    <div aria-hidden="true" className="flex flex-col gap-2.5">
      <div className="h-11 rounded-xl border" />
      {[0, 1, 2].map((i) => (
        <div key={i} className="h-16 rounded-card border bg-surface" />
      ))}
    </div>
  );
}
