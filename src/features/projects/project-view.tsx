import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { ChevronLeft } from "lucide-react";
import { formatAge, formatDue } from "@/features/inbox/format-age";
import { createClient } from "@/server/db/server";
import {
  ContextList,
  EditableStatus,
  EditableSummary,
  ProjectSettings,
  TaskList,
  type SourceEntry,
} from "./project-editors";

const SECTIONS = [
  { section: "stack", title: "Stack" },
  { section: "decision", title: "Decisions" },
  { section: "idea", title: "Open ideas" },
] as const;

/** A project's page: live context the AI keeps up to date, and its tasks. */
export async function ProjectView({
  params,
}: Pick<PageProps<"/projects/[slug]">, "params">) {
  await connection();
  const { slug } = await params;
  const supabase = await createClient();

  const { data: project } = await supabase
    .from("projects")
    .select(
      "id, name, color, status, status_source, summary, summary_source, summary_entry_ids, context_updated_at, archived_at",
    )
    .eq("slug", slug)
    .maybeSingle();
  if (!project) notFound();

  const [items, tasks] = await Promise.all([
    supabase
      .from("project_context_items")
      .select("id, section, text, source, entry_ids")
      .eq("project_id", project.id)
      .order("created_at"),
    supabase
      .from("entries")
      .select("id, content, done_at, due_at, captures(timezone)")
      .eq("project_id", project.id)
      .eq("kind", "task")
      .order("done_at", { ascending: true, nullsFirst: true })
      .order("created_at", { ascending: false })
      .limit(100),
  ]);

  // Entries the AI context came from, for "from N notes".
  const sourceIds = [
    ...new Set([
      ...project.summary_entry_ids,
      ...(items.data ?? []).flatMap((i) => i.entry_ids),
    ]),
  ];
  const { data: sources } = sourceIds.length
    ? await supabase.from("entries").select("id, content").in("id", sourceIds)
    : { data: [] as SourceEntry[] };
  const byId = new Map((sources ?? []).map((s) => [s.id, s]));
  const pick = (ids: string[]) =>
    ids.map((id) => byId.get(id)).filter((s): s is SourceEntry => Boolean(s));

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-6 px-4 py-6 md:py-12">
      <Link
        href="/projects"
        className="-ml-1 flex min-h-11 w-fit items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
      >
        <ChevronLeft className="size-4" aria-hidden="true" />
        Projects
      </Link>

      <header className="flex flex-col gap-1">
        <div className="flex items-center gap-2.5">
          <span
            aria-hidden="true"
            className="size-3 shrink-0 rounded-full"
            style={{ backgroundColor: project.color }}
          />
          <h1 className="min-w-0 text-3xl font-semibold tracking-tight break-words">
            {project.name}
          </h1>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <EditableStatus
            projectId={project.id}
            status={project.status}
            byUser={project.status_source === "user"}
          />
          {project.archived_at && (
            <span className="rounded-full border px-2.5 py-1 font-mono text-xs text-subtle">
              archived
            </span>
          )}
        </div>
      </header>

      <EditableSummary
        projectId={project.id}
        summary={project.summary}
        byUser={project.summary_source === "user"}
        updatedLabel={
          project.context_updated_at
            ? formatAge(new Date(project.context_updated_at), new Date())
            : null
        }
        sources={pick(project.summary_entry_ids)}
      />

      {SECTIONS.map(({ section, title }) => (
        <ContextList
          key={section}
          projectId={project.id}
          section={section}
          title={title}
          items={(items.data ?? [])
            .filter((i) => i.section === section)
            .map((i) => ({
              id: i.id,
              text: i.text,
              byUser: i.source === "user",
              sources: pick(i.entry_ids),
            }))}
        />
      ))}

      <TaskList
        tasks={(tasks.data ?? []).map((t) => ({
          id: t.id,
          content: t.content,
          done: Boolean(t.done_at),
          due: t.due_at
            ? formatDue(new Date(t.due_at), t.captures?.timezone ?? null)
            : null,
        }))}
      />

      <ProjectSettings
        projectId={project.id}
        name={project.name}
        color={project.color}
        archived={Boolean(project.archived_at)}
      />
    </div>
  );
}

export function ProjectViewSkeleton() {
  return (
    <div
      aria-hidden="true"
      className="mx-auto flex w-full max-w-2xl flex-col gap-6 px-4 py-6 md:py-12"
    >
      <div className="h-11 w-24 rounded-xl" />
      <div className="h-10 w-48 rounded-xl bg-surface" />
      <div className="h-36 rounded-card border bg-surface" />
      <div className="h-24 rounded-card border" />
    </div>
  );
}
