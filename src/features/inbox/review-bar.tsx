"use client";

import { useState, useTransition } from "react";
import { Check, Plus } from "lucide-react";
import {
  assignNewProject,
  confirmEntry,
  type InboxActionResult,
} from "./actions";

type ReviewBarProps = {
  entryId: string;
  hasProject: boolean;
  suggestedProject: string | null;
};

/** The "not sure" part of a card: one tap to accept or fix the AI's guess. */
export function ReviewBar({
  entryId,
  hasProject,
  suggestedProject,
}: ReviewBarProps) {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function run(action: () => Promise<InboxActionResult>) {
    setError(null);
    startTransition(async () => {
      const result = await action();
      if (!result.ok) setError(result.message);
    });
  }

  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm text-review">
        {hasProject
          ? "Not sure about this one. Is it right?"
          : "Not sure where this goes. Pick one."}
      </p>
      <div className="flex flex-wrap gap-2">
        {hasProject && (
          <button
            type="button"
            disabled={pending}
            onClick={() => run(() => confirmEntry(entryId))}
            className="flex h-11 items-center gap-1.5 rounded-xl border border-border-strong bg-surface-2 px-3.5 text-sm transition-opacity disabled:opacity-50"
          >
            <Check className="size-4" aria-hidden="true" />
            Looks right
          </button>
        )}
        {!hasProject && suggestedProject && (
          <button
            type="button"
            disabled={pending}
            onClick={() =>
              run(() => assignNewProject({ entryId, name: suggestedProject }))
            }
            className="flex h-11 max-w-full items-center gap-1.5 rounded-xl border border-dashed border-border-strong px-3.5 text-sm transition-opacity disabled:opacity-50"
          >
            <Plus className="size-4 shrink-0" aria-hidden="true" />
            <span className="truncate">New project “{suggestedProject}”</span>
          </button>
        )}
      </div>
      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}
    </div>
  );
}
