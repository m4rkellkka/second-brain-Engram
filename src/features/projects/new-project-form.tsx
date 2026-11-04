"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Plus } from "lucide-react";
import { createProject } from "./actions";

/** "+ New project": a name, then straight to the new project's page. */
export function NewProjectForm() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        const value = name.trim();
        if (!value) return;
        setError(null);
        startTransition(async () => {
          const result = await createProject({ name: value });
          if (result.ok) router.push(`/projects/${result.slug}`);
          else setError(result.message);
        });
      }}
      className="flex flex-col gap-2"
    >
      <div className="flex gap-2">
        <label htmlFor="new-project" className="sr-only">
          New project name
        </label>
        <input
          id="new-project"
          value={name}
          onChange={(event) => setName(event.target.value)}
          maxLength={60}
          placeholder="New project name"
          disabled={pending}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? "new-project-error" : undefined}
          className="h-11 min-w-0 flex-1 rounded-xl border border-border-strong bg-surface px-3 text-base outline-none placeholder:text-subtle focus:border-ring md:text-sm"
        />
        <button
          type="submit"
          disabled={pending || !name.trim()}
          className="flex h-11 shrink-0 items-center gap-1.5 rounded-xl bg-primary px-4 text-sm font-medium text-primary-foreground transition-opacity disabled:opacity-40"
        >
          {pending ? (
            <Loader2 className="size-4 animate-spin" aria-hidden="true" />
          ) : (
            <Plus className="size-4" aria-hidden="true" />
          )}
          Create
        </button>
      </div>
      {error && (
        <p
          id="new-project-error"
          role="alert"
          className="text-sm text-destructive"
        >
          {error}
        </p>
      )}
    </form>
  );
}
