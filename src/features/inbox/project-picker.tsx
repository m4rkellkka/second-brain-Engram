"use client";

import { useId, useOptimistic, useState, useTransition } from "react";
import { Check, ChevronDown, Loader2, X } from "lucide-react";
import { cn } from "@/lib/utils";
import { assignNewProject, assignProject } from "./actions";

export type PickerProject = { id: string; name: string; color: string };

const NEW_PROJECT = "__new__";

type ProjectPickerProps = {
  entryId: string;
  projectId: string | null;
  projects: PickerProject[];
};

/**
 * Project of one Inbox entry. A native select, so iOS shows its own wheel;
 * the last option turns it into an inline "new project" field.
 */
export function ProjectPicker({
  entryId,
  projectId,
  projects,
}: ProjectPickerProps) {
  const [shownId, setShownId] = useOptimistic(projectId);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const id = useId();
  const current = projects.find((project) => project.id === shownId);

  function move(next: string | null) {
    setError(null);
    startTransition(async () => {
      setShownId(next);
      const result = await assignProject({ entryId, projectId: next });
      if (!result.ok) setError(result.message);
    });
  }

  function create() {
    const value = name.trim();
    if (!value) return;
    setError(null);
    startTransition(async () => {
      const result = await assignNewProject({ entryId, name: value });
      // Close the field in the same update that brings the new project in.
      startTransition(() => {
        if (result.ok) {
          setCreating(false);
          setName("");
        } else {
          setError(result.message);
        }
      });
    });
  }

  function cancel() {
    setCreating(false);
    setName("");
    setError(null);
  }

  return (
    <div className="flex flex-col gap-2">
      {creating ? (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            create();
          }}
          className="flex items-center gap-2"
        >
          <label htmlFor={`${id}-name`} className="sr-only">
            New project name
          </label>
          <input
            id={`${id}-name`}
            value={name}
            onChange={(event) => setName(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Escape") cancel();
            }}
            autoFocus
            maxLength={60} // projectNameSchema limit
            placeholder="New project name"
            disabled={pending}
            aria-invalid={error ? true : undefined}
            aria-describedby={error ? `${id}-error` : undefined}
            className="h-11 min-w-0 flex-1 rounded-xl border border-border-strong bg-surface-2 px-3 text-base outline-none placeholder:text-subtle focus:border-ring disabled:opacity-60 md:text-sm"
          />
          <button
            type="submit"
            disabled={pending || !name.trim()}
            aria-label="Create project"
            className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground transition-opacity disabled:opacity-40"
          >
            {pending ? (
              <Loader2 className="size-4 animate-spin" aria-hidden="true" />
            ) : (
              <Check className="size-4" aria-hidden="true" />
            )}
          </button>
          <button
            type="button"
            onClick={cancel}
            disabled={pending}
            aria-label="Cancel"
            className="flex size-11 shrink-0 items-center justify-center rounded-xl border border-border-strong text-muted-foreground transition-colors hover:text-foreground"
          >
            <X className="size-4" aria-hidden="true" />
          </button>
        </form>
      ) : (
        <div className="relative w-fit max-w-full">
          {current && (
            <span
              aria-hidden="true"
              className="pointer-events-none absolute top-1/2 left-3.5 size-1.5 -translate-y-1/2 rounded-full"
              style={{ backgroundColor: current.color }}
            />
          )}
          <select
            aria-label="Project"
            value={shownId ?? ""}
            onChange={(event) => {
              const value = event.target.value;
              if (value === NEW_PROJECT) setCreating(true);
              else move(value || null);
            }}
            aria-invalid={error ? true : undefined}
            aria-describedby={error ? `${id}-error` : undefined}
            className={cn(
              "h-11 max-w-full cursor-pointer appearance-none truncate rounded-full border bg-surface-2 pr-9 text-base transition-colors outline-none focus-visible:border-ring md:text-sm",
              current
                ? "border-transparent pl-7 text-foreground"
                : "border-dashed border-border-strong bg-transparent pl-3.5 text-muted-foreground hover:text-foreground",
            )}
          >
            <option value="">No project</option>
            {projects.map((project) => (
              <option key={project.id} value={project.id}>
                {project.name}
              </option>
            ))}
            <option value={NEW_PROJECT}>+ New project…</option>
          </select>
          <ChevronDown
            aria-hidden="true"
            className="pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2 text-subtle"
          />
        </div>
      )}

      {error && (
        <p id={`${id}-error`} role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}
    </div>
  );
}
