"use client";

import { useOptimistic, useState, useTransition } from "react";
import { changeKind } from "./actions";

const LABELS = {
  idea: "IDEA",
  task: "TASK",
  note: "NOTE",
  link: "LINK",
} as const;
type Kind = keyof typeof LABELS;

/** Entry type shown as a small label; tap to fix what the AI picked. */
export function KindSelect({ entryId, kind }: { entryId: string; kind: Kind }) {
  const [shown, setShown] = useOptimistic(kind);
  const [failed, setFailed] = useState(false);
  const [, startTransition] = useTransition();

  return (
    <select
      aria-label="Type"
      value={shown}
      onChange={(event) => {
        const next = event.target.value as Kind;
        setFailed(false);
        startTransition(async () => {
          setShown(next);
          const result = await changeKind({ entryId, kind: next });
          if (!result.ok) setFailed(true);
        });
      }}
      aria-invalid={failed || undefined}
      title={failed ? "Couldn't change the type. Try again." : undefined}
      // 16px on phones so iOS doesn't zoom; looks like the mono label.
      className="-my-2 h-9 cursor-pointer appearance-none rounded-md bg-transparent px-1 font-mono text-base tracking-[0.06em] text-muted-foreground outline-none hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring aria-invalid:text-destructive md:text-[11px]"
    >
      {Object.entries(LABELS).map(([value, label]) => (
        <option key={value} value={value}>
          {label}
        </option>
      ))}
    </select>
  );
}
