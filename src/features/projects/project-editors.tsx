"use client";

import { useOptimistic, useState, useTransition } from "react";
import {
  Archive,
  Check,
  Pencil,
  Plus,
  Sparkles,
  Trash2,
  X,
} from "lucide-react";
import { cn } from "@/lib/utils";
import {
  addContextItem,
  deleteContextItem,
  setArchived,
  setStatus,
  setSummary,
  toggleTask,
  updateContextItem,
  updateProject,
  type ProjectActionResult,
} from "./actions";
import { PROJECT_COLORS } from "./new-project";

export type SourceEntry = { id: string; content: string };

/** Runs an action in a transition and keeps its error message. */
function useAction() {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  function run(action: () => Promise<ProjectActionResult>, onOk?: () => void) {
    setError(null);
    startTransition(async () => {
      const result = await action();
      if (result.ok) startTransition(() => onOk?.());
      else setError(result.message);
    });
  }
  return { error, pending, run };
}

function ErrorText({ error }: { error: string | null }) {
  return error ? (
    <p role="alert" className="text-sm text-destructive">
      {error}
    </p>
  ) : null;
}

const iconButton =
  "flex size-11 shrink-0 items-center justify-center rounded-xl text-muted-foreground transition-colors hover:text-foreground disabled:opacity-40";
const field =
  "w-full rounded-xl border border-border-strong bg-surface-2 px-3 py-2.5 text-base outline-none placeholder:text-subtle focus:border-ring md:text-sm";

/** "From these notes": the entries an AI change came from. */
function Sources({ sources }: { sources: SourceEntry[] }) {
  if (sources.length === 0) return null;
  return (
    <details className="text-xs text-subtle">
      <summary className="inline-flex min-h-8 cursor-pointer items-center">
        from {sources.length} {sources.length === 1 ? "note" : "notes"}
      </summary>
      <ul className="mt-1 flex flex-col gap-1.5 border-l pl-3">
        {sources.map((source) => (
          <li key={source.id} className="break-words whitespace-pre-wrap">
            {source.content}
          </li>
        ))}
      </ul>
    </details>
  );
}

export function EditableSummary(props: {
  projectId: string;
  summary: string | null;
  byUser: boolean;
  updatedLabel: string | null;
  sources: SourceEntry[];
}) {
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(props.summary ?? "");
  const { error, pending, run } = useAction();

  return (
    <section
      aria-labelledby="summary-title"
      className="flex flex-col gap-2.5 rounded-card border bg-surface p-4"
    >
      <div className="flex items-center justify-between gap-2">
        <h2
          id="summary-title"
          className="font-mono text-[11px] tracking-[0.08em] text-primary-text"
        >
          LIVE CONTEXT
        </h2>
        <span className="text-xs text-subtle">
          {props.byUser ? "edited by you" : "updated by AI"}
          {props.updatedLabel ? ` · ${props.updatedLabel}` : ""}
        </span>
      </div>

      {editing ? (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            run(
              () => setSummary({ projectId: props.projectId, summary: text }),
              () => setEditing(false),
            );
          }}
          className="flex flex-col gap-2"
        >
          <label htmlFor="summary" className="sr-only">
            Summary
          </label>
          <textarea
            id="summary"
            value={text}
            onChange={(event) => setText(event.target.value)}
            rows={4}
            maxLength={2000}
            autoFocus
            className={cn(field, "resize-none")}
          />
          <div className="flex gap-2">
            <button
              type="submit"
              disabled={pending}
              className="h-11 rounded-xl bg-primary px-4 text-sm font-medium text-primary-foreground disabled:opacity-40"
            >
              Save
            </button>
            <button
              type="button"
              onClick={() => {
                setEditing(false);
                setText(props.summary ?? "");
              }}
              className="h-11 rounded-xl border border-border-strong px-4 text-sm"
            >
              Cancel
            </button>
          </div>
        </form>
      ) : (
        <>
          <p className="break-words whitespace-pre-wrap text-foreground/90">
            {props.summary || (
              <span className="text-muted-foreground">
                No summary yet. It fills in as you capture notes about this
                project.
              </span>
            )}
          </p>
          {!props.byUser && <Sources sources={props.sources} />}
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => setEditing(true)}
              aria-label="Edit summary"
              className="flex h-11 items-center gap-1.5 rounded-xl border border-border-strong px-3.5 text-sm"
            >
              <Pencil className="size-4" aria-hidden="true" />
              Edit
            </button>
            {props.byUser && (
              <button
                type="button"
                disabled={pending}
                onClick={() =>
                  run(() =>
                    setSummary({ projectId: props.projectId, summary: null }),
                  )
                }
                className="flex h-11 items-center gap-1.5 rounded-xl border border-border-strong px-3.5 text-sm disabled:opacity-40"
              >
                <Sparkles className="size-4" aria-hidden="true" />
                Let AI update
              </button>
            )}
          </div>
        </>
      )}
      <ErrorText error={error} />
    </section>
  );
}

export function EditableStatus(props: {
  projectId: string;
  status: string | null;
  byUser: boolean;
}) {
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(props.status ?? "");
  const { error, pending, run } = useAction();

  if (editing) {
    return (
      <form
        onSubmit={(event) => {
          event.preventDefault();
          run(
            () => setStatus({ projectId: props.projectId, status: text }),
            () => setEditing(false),
          );
        }}
        className="flex flex-wrap items-center gap-1"
      >
        <label htmlFor="status" className="sr-only">
          Status
        </label>
        <input
          id="status"
          value={text}
          onChange={(event) => setText(event.target.value)}
          maxLength={60}
          autoFocus
          placeholder="building, pilot, paused…"
          className={cn(field, "h-11 w-48 py-0")}
        />
        <button
          type="submit"
          disabled={pending}
          aria-label="Save status"
          className={iconButton}
        >
          <Check className="size-4" aria-hidden="true" />
        </button>
        <button
          type="button"
          onClick={() => setEditing(false)}
          aria-label="Cancel"
          className={iconButton}
        >
          <X className="size-4" aria-hidden="true" />
        </button>
        <ErrorText error={error} />
      </form>
    );
  }

  return (
    <div className="flex flex-wrap items-center gap-1">
      <button
        type="button"
        onClick={() => setEditing(true)}
        aria-label={
          props.status ? `Status: ${props.status}. Edit` : "Set status"
        }
        className="flex min-h-11 items-center"
      >
        <span className="rounded-full bg-surface-2 px-2.5 py-1 font-mono text-xs text-muted-foreground">
          {props.status || "+ status"}
        </span>
      </button>
      {props.byUser && (
        <button
          type="button"
          disabled={pending}
          onClick={() =>
            run(() => setStatus({ projectId: props.projectId, status: null }))
          }
          className="min-h-11 px-2 text-xs text-subtle hover:text-foreground"
        >
          let AI update
        </button>
      )}
    </div>
  );
}

type Item = {
  id: string;
  text: string;
  byUser: boolean;
  sources: SourceEntry[];
};

function ContextItem({ item }: { item: Item }) {
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(item.text);
  const { error, pending, run } = useAction();

  return (
    <li className="flex flex-col gap-1 rounded-xl border bg-surface px-3.5 py-1">
      {editing ? (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            run(
              () => updateContextItem({ itemId: item.id, text }),
              () => setEditing(false),
            );
          }}
          className="flex items-center gap-1 py-1"
        >
          <label htmlFor={`item-${item.id}`} className="sr-only">
            Edit item
          </label>
          <input
            id={`item-${item.id}`}
            value={text}
            onChange={(event) => setText(event.target.value)}
            maxLength={500}
            autoFocus
            className={cn(field, "h-11 py-0")}
          />
          <button
            type="submit"
            disabled={pending}
            aria-label="Save"
            className={iconButton}
          >
            <Check className="size-4" aria-hidden="true" />
          </button>
          <button
            type="button"
            onClick={() => {
              setEditing(false);
              setText(item.text);
            }}
            aria-label="Cancel"
            className={iconButton}
          >
            <X className="size-4" aria-hidden="true" />
          </button>
        </form>
      ) : (
        <div className="flex items-center gap-1">
          <span className="min-w-0 flex-1 py-1.5 text-sm break-words">
            {item.text}
          </span>
          <button
            type="button"
            onClick={() => setEditing(true)}
            aria-label={`Edit “${item.text}”`}
            className={iconButton}
          >
            <Pencil className="size-4" aria-hidden="true" />
          </button>
          <button
            type="button"
            disabled={pending}
            onClick={() => run(() => deleteContextItem(item.id))}
            aria-label={`Delete “${item.text}”`}
            className={iconButton}
          >
            <Trash2 className="size-4" aria-hidden="true" />
          </button>
        </div>
      )}
      {!item.byUser && !editing && <Sources sources={item.sources} />}
      <ErrorText error={error} />
    </li>
  );
}

export function ContextList(props: {
  projectId: string;
  section: "stack" | "decision" | "idea";
  title: string;
  items: Item[];
}) {
  const [adding, setAdding] = useState(false);
  const [text, setText] = useState("");
  const { error, pending, run } = useAction();
  const inputId = `add-${props.section}`;

  return (
    <section aria-label={props.title} className="flex flex-col gap-2">
      <div className="flex items-center justify-between">
        <h2 className="font-mono text-[11px] tracking-[0.08em] text-subtle">
          {props.title.toUpperCase()}
        </h2>
        <button
          type="button"
          onClick={() => setAdding(true)}
          aria-label={`Add to ${props.title}`}
          className={iconButton}
        >
          <Plus className="size-4" aria-hidden="true" />
        </button>
      </div>
      {props.items.length === 0 && !adding && (
        <p className="text-sm text-subtle">Nothing yet.</p>
      )}
      {props.items.length > 0 && (
        <ul className="flex flex-col gap-2">
          {props.items.map((item) => (
            <ContextItem key={item.id} item={item} />
          ))}
        </ul>
      )}
      {adding && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            run(
              () =>
                addContextItem({
                  projectId: props.projectId,
                  section: props.section,
                  text,
                }),
              () => {
                setText("");
                setAdding(false);
              },
            );
          }}
          className="flex items-center gap-1"
        >
          <label htmlFor={inputId} className="sr-only">
            New item for {props.title}
          </label>
          <input
            id={inputId}
            value={text}
            onChange={(event) => setText(event.target.value)}
            maxLength={500}
            autoFocus
            className={cn(field, "h-11 py-0")}
          />
          <button
            type="submit"
            disabled={pending || !text.trim()}
            aria-label="Add"
            className={iconButton}
          >
            <Check className="size-4" aria-hidden="true" />
          </button>
          <button
            type="button"
            onClick={() => setAdding(false)}
            aria-label="Cancel"
            className={iconButton}
          >
            <X className="size-4" aria-hidden="true" />
          </button>
        </form>
      )}
      <ErrorText error={error} />
    </section>
  );
}

type Task = { id: string; content: string; done: boolean; due: string | null };

function TaskRow({ task }: { task: Task }) {
  const [done, setDone] = useOptimistic(task.done);
  const [failed, setFailed] = useState(false);
  const [, startTransition] = useTransition();

  return (
    <li>
      <label className="flex min-h-11 cursor-pointer items-center gap-3 px-1">
        <input
          type="checkbox"
          checked={done}
          onChange={(event) => {
            const next = event.target.checked;
            setFailed(false);
            startTransition(async () => {
              setDone(next);
              const result = await toggleTask({ entryId: task.id, done: next });
              if (!result.ok) setFailed(true);
            });
          }}
          className="size-5 shrink-0 cursor-pointer accent-primary"
        />
        <span
          className={cn(
            "min-w-0 flex-1 break-words",
            done && "text-subtle line-through",
            failed && "text-destructive",
          )}
        >
          {task.content}
        </span>
        {task.due && !done && (
          <span className="shrink-0 text-xs text-subtle">{task.due}</span>
        )}
      </label>
    </li>
  );
}

export function TaskList({ tasks }: { tasks: Task[] }) {
  const doneCount = tasks.filter((t) => t.done).length;
  return (
    <section aria-label="Tasks" className="flex flex-col gap-2">
      <h2 className="font-mono text-[11px] tracking-[0.08em] text-subtle">
        TASKS · {doneCount}/{tasks.length}
      </h2>
      {tasks.length === 0 ? (
        <p className="text-sm text-subtle">
          No tasks yet. Tasks you capture for this project show up here.
        </p>
      ) : (
        <ul className="flex flex-col">
          {tasks.map((task) => (
            <TaskRow key={task.id} task={task} />
          ))}
        </ul>
      )}
    </section>
  );
}

export function ProjectSettings(props: {
  projectId: string;
  name: string;
  color: string;
  archived: boolean;
}) {
  const [name, setName] = useState(props.name);
  const { error, pending, run } = useAction();
  const current = props.color.toLowerCase();

  return (
    <details className="rounded-card border bg-surface px-4">
      <summary className="flex min-h-12 cursor-pointer items-center font-mono text-[11px] tracking-[0.08em] text-subtle">
        PROJECT SETTINGS
      </summary>
      <div className="flex flex-col gap-4 pb-4">
        <form
          onSubmit={(event) => {
            event.preventDefault();
            run(() => updateProject({ projectId: props.projectId, name }));
          }}
          className="flex flex-col gap-1.5"
        >
          <label
            htmlFor="project-name"
            className="text-sm text-muted-foreground"
          >
            Name
          </label>
          <div className="flex gap-2">
            <input
              id="project-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              maxLength={60}
              className={cn(field, "h-11 py-0")}
            />
            <button
              type="submit"
              disabled={pending || !name.trim() || name.trim() === props.name}
              className="h-11 shrink-0 rounded-xl bg-primary px-4 text-sm font-medium text-primary-foreground disabled:opacity-40"
            >
              Rename
            </button>
          </div>
        </form>

        <fieldset>
          <legend className="mb-1.5 text-sm text-muted-foreground">
            Color
          </legend>
          <div className="flex flex-wrap gap-1">
            {PROJECT_COLORS.map((color) => (
              <button
                key={color}
                type="button"
                disabled={pending}
                aria-label={`Color ${color}`}
                aria-pressed={color.toLowerCase() === current}
                onClick={() =>
                  run(() =>
                    updateProject({ projectId: props.projectId, color }),
                  )
                }
                className="flex size-11 items-center justify-center rounded-xl"
              >
                <span
                  className={cn(
                    "size-7 rounded-full ring-offset-2 ring-offset-surface",
                    color.toLowerCase() === current && "ring-2 ring-foreground",
                  )}
                  style={{ backgroundColor: color }}
                />
              </button>
            ))}
          </div>
        </fieldset>

        <button
          type="button"
          disabled={pending}
          onClick={() =>
            run(() =>
              setArchived({
                projectId: props.projectId,
                archived: !props.archived,
              }),
            )
          }
          className="flex h-11 w-fit items-center gap-1.5 rounded-xl border border-border-strong px-3.5 text-sm disabled:opacity-40"
        >
          <Archive className="size-4" aria-hidden="true" />
          {props.archived ? "Restore from archive" : "Archive project"}
        </button>
        <ErrorText error={error} />
      </div>
    </details>
  );
}
