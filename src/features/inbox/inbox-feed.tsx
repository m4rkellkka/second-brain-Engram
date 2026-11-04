import Link from "next/link";
import { connection } from "next/server";
import {
  FileText,
  Lightbulb,
  Link2,
  Loader2,
  SquareCheck,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { createClient } from "@/server/db/server";
import { MAX_ATTEMPTS } from "@/server/pipeline/process-capture";
import { formatAge, formatDue } from "./format-age";
import { KindSelect } from "./kind-select";
import { PendingWatcher } from "./pending-watcher";
import { ProjectPicker, type PickerProject } from "./project-picker";
import { ReviewBar } from "./review-bar";
import { ENTRY_KINDS, parseKindFilter, type EntryKind } from "./schema";

const INBOX_LIMIT = 50;
/** Sorting normally takes seconds; after this the Inbox asks for a retry. */
const STALE_AFTER_MS = 2 * 60_000;

const KINDS: Record<
  EntryKind,
  { label: string; plural: string; icon: LucideIcon; color: string }
> = {
  idea: {
    label: "IDEA",
    plural: "Ideas",
    icon: Lightbulb,
    color: "text-kind-idea",
  },
  task: {
    label: "TASK",
    plural: "Tasks",
    icon: SquareCheck,
    color: "text-kind-task",
  },
  note: {
    label: "NOTE",
    plural: "Notes",
    icon: FileText,
    color: "text-kind-note",
  },
  link: {
    label: "LINK",
    plural: "Links",
    icon: Link2,
    color: "text-kind-link",
  },
};

const FILTERS: { kind: EntryKind | null; label: string }[] = [
  { kind: null, label: "All" },
  ...ENTRY_KINDS.map((kind) => ({ kind, label: KINDS[kind].plural })),
];

/** Latest entries, newest first, with type filter chips. */
export async function InboxFeed({
  searchParams,
}: Pick<PageProps<"/inbox">, "searchParams">) {
  // Request-time only: supabase-js reads the clock, so do we.
  await connection();
  const kind = parseKindFilter((await searchParams).kind);
  const supabase = await createClient();

  let entriesQuery = supabase
    .from("entries")
    .select(
      "id, kind, content, created_at, project_id, needs_review, suggested_project_name, due_at, url, captures(timezone)",
    )
    .order("created_at", { ascending: false })
    .limit(INBOX_LIMIT);
  if (kind) entriesQuery = entriesQuery.eq("kind", kind);

  const [entries, projects, pending] = await Promise.all([
    entriesQuery,
    supabase
      .from("projects")
      .select("id, name, color, archived_at")
      .order("name"),
    // Captures still being sorted, so a thought never vanishes meanwhile.
    supabase
      .from("captures")
      .select("id, raw_text, created_at, status")
      .in("status", ["pending", "processing", "failed"])
      .lt("attempts", MAX_ATTEMPTS)
      .order("created_at", { ascending: false })
      .limit(10),
  ]);

  const filters = <KindFilters active={kind} />;

  if (entries.error || projects.error || pending.error) {
    return (
      <>
        {filters}
        <p role="alert" className="text-sm text-destructive">
          Couldn&apos;t load the Inbox. Reopen the app to try again.
        </p>
      </>
    );
  }

  const active: PickerProject[] = projects.data.filter((p) => !p.archived_at);
  const byId = new Map(projects.data.map((p) => [p.id, p]));
  const now = new Date();
  const sorting = kind ? [] : pending.data;
  const stale = sorting.some(
    (c) => now.getTime() - new Date(c.created_at).getTime() > STALE_AFTER_MS,
  );

  return (
    <>
      {filters}
      <PendingWatcher count={sorting.length} stale={stale} />
      {sorting.length > 0 && (
        <ul aria-label="Sorting" className="flex flex-col gap-2.5">
          {sorting.map((c) => (
            <li key={c.id}>
              <article className="flex flex-col gap-2.5 rounded-card border border-dashed bg-surface px-4 py-3.5">
                <div className="flex items-center gap-2">
                  <Loader2
                    className="size-4 animate-spin text-subtle"
                    aria-hidden="true"
                  />
                  <span className="font-mono text-[11px] tracking-[0.06em] text-muted-foreground">
                    {c.status === "failed" ? "RETRYING" : "SORTING"}
                  </span>
                  <time
                    dateTime={c.created_at}
                    className="ml-auto font-mono text-[11px] text-subtle"
                  >
                    {formatAge(new Date(c.created_at), now)}
                  </time>
                </div>
                <p className="text-base break-words whitespace-pre-wrap text-muted-foreground">
                  {c.raw_text}
                </p>
              </article>
            </li>
          ))}
        </ul>
      )}
      {entries.data.length === 0 && sorting.length === 0 ? (
        <div className="flex flex-col items-center gap-4 rounded-card border border-dashed px-6 py-12 text-center">
          <p className="text-muted-foreground">
            {kind
              ? `No ${KINDS[kind].plural.toLowerCase()} yet.`
              : "Nothing here yet. Thoughts you save show up here."}
          </p>
          {!kind && (
            <Link
              href="/capture"
              className="flex h-11 items-center rounded-xl bg-primary px-4 text-sm font-medium text-primary-foreground"
            >
              Capture a thought
            </Link>
          )}
        </div>
      ) : entries.data.length === 0 ? null : (
        <ul className="flex flex-col gap-2.5">
          {entries.data.map((entry) => {
            const meta = KINDS[entry.kind];
            const Icon = meta.icon;
            const current = entry.project_id
              ? byId.get(entry.project_id)
              : undefined;
            // An archived project stays visible on entries already in it.
            const options = current?.archived_at
              ? [...active, current]
              : active;

            return (
              <li key={entry.id}>
                <article
                  className={cn(
                    "flex flex-col gap-2.5 rounded-card border bg-surface px-4 py-3.5",
                    entry.needs_review && "border-review-border",
                  )}
                >
                  <div className="flex items-center gap-2">
                    <Icon
                      className={cn("size-4", meta.color)}
                      aria-hidden="true"
                    />
                    <KindSelect entryId={entry.id} kind={entry.kind} />
                    <time
                      dateTime={entry.created_at}
                      className="ml-auto font-mono text-[11px] text-subtle"
                    >
                      {formatAge(new Date(entry.created_at), now)}
                    </time>
                  </div>
                  <p className="text-base break-words whitespace-pre-wrap">
                    {entry.content}
                  </p>
                  {(entry.due_at || entry.url) && (
                    <div className="flex flex-wrap items-center gap-2">
                      {entry.due_at && (
                        <span className="rounded-full bg-surface-2 px-2.5 py-1 text-xs text-muted-foreground">
                          due{" "}
                          {formatDue(
                            new Date(entry.due_at),
                            entry.captures?.timezone ?? null,
                          )}
                        </span>
                      )}
                      {entry.url && (
                        <a
                          href={entry.url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="max-w-full truncate rounded-full bg-surface-2 px-2.5 py-1 text-xs text-primary-text hover:underline"
                        >
                          {new URL(entry.url).hostname}
                        </a>
                      )}
                    </div>
                  )}
                  {entry.needs_review && (
                    <ReviewBar
                      entryId={entry.id}
                      hasProject={Boolean(entry.project_id)}
                      suggestedProject={entry.suggested_project_name}
                    />
                  )}
                  <ProjectPicker
                    entryId={entry.id}
                    projectId={entry.project_id}
                    projects={options}
                  />
                </article>
              </li>
            );
          })}
        </ul>
      )}
      {entries.data.length === INBOX_LIMIT && (
        <p className="text-center text-xs text-subtle">
          Showing the latest {INBOX_LIMIT}.
        </p>
      )}
    </>
  );
}

function KindFilters({ active }: { active: EntryKind | null }) {
  return (
    <nav
      aria-label="Filter by type"
      className="-mx-4 flex gap-1.5 overflow-x-auto px-4 py-1"
    >
      {FILTERS.map(({ kind, label }) => {
        const selected = kind === active;
        return (
          <Link
            key={label}
            href={kind ? `/inbox?kind=${kind}` : "/inbox"}
            replace
            scroll={false}
            aria-current={selected ? "page" : undefined}
            className={cn(
              // The pseudo-element stretches the tap area to 44px.
              "relative flex h-9 shrink-0 items-center rounded-full border px-3.5 text-sm transition-colors before:absolute before:inset-x-0 before:-inset-y-1 before:content-['']",
              selected
                ? "border-foreground bg-foreground text-primary-foreground"
                : "border-border-strong text-muted-foreground hover:text-foreground",
            )}
          >
            {label}
          </Link>
        );
      })}
    </nav>
  );
}

export function InboxFeedSkeleton() {
  return (
    <div aria-hidden="true" className="flex flex-col gap-4">
      <div className="flex gap-1.5 py-1">
        {FILTERS.map(({ label }) => (
          <div key={label} className="h-9 w-16 rounded-full border" />
        ))}
      </div>
      {[0, 1, 2].map((i) => (
        <div key={i} className="h-32 rounded-card border bg-surface" />
      ))}
    </div>
  );
}
