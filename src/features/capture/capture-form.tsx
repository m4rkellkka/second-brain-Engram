"use client";

import { useOptimistic, useRef, useState, useTransition } from "react";
import { ArrowUp, Check, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { saveCapture } from "./actions";

type JustSaved = { id: string; content: string; pending: boolean };

const RECENT_LIMIT = 5;

/** Capture screen: type a thought, save with the button or ⌘/Ctrl+Enter. */
export function CaptureForm() {
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<JustSaved[]>([]);
  const [optimistic, addOptimistic] = useOptimistic(
    saved,
    (state, item: JustSaved) => [item, ...state].slice(0, RECENT_LIMIT),
  );
  const [, startTransition] = useTransition();
  const inputRef = useRef<HTMLTextAreaElement>(null);

  function submit() {
    const value = text.trim();
    if (!value) return;
    setError(null);
    setText("");
    inputRef.current?.focus();

    startTransition(async () => {
      addOptimistic({
        id: `pending-${Date.now()}`,
        content: value,
        pending: true,
      });
      const result = await saveCapture(
        value,
        Intl.DateTimeFormat().resolvedOptions().timeZone,
      );
      if (result.ok) {
        setSaved((state) =>
          [
            {
              id: result.entry.id,
              content: result.entry.content,
              pending: false,
            },
            ...state,
          ].slice(0, RECENT_LIMIT),
        );
      } else {
        // Give the text back so nothing typed is lost.
        setError(result.message);
        setText(value);
      }
    });
  }

  return (
    <div className="mx-auto flex w-full max-w-xl flex-col gap-5 px-4 py-6 md:py-12">
      <h1 className="text-3xl font-semibold tracking-tight">
        What&apos;s on your mind?
      </h1>

      <form
        onSubmit={(event) => {
          event.preventDefault();
          submit();
        }}
        className="flex flex-col gap-3 rounded-card border bg-surface p-4 focus-within:border-border-strong"
      >
        <label htmlFor="capture-text" className="sr-only">
          Thought
        </label>
        <textarea
          id="capture-text"
          ref={inputRef}
          value={text}
          onChange={(event) => setText(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
              event.preventDefault();
              submit();
            }
          }}
          autoFocus
          rows={4}
          maxLength={10_000}
          placeholder="Type a thought. Engram keeps it in your Inbox."
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? "capture-error" : "capture-hint"}
          className="w-full resize-none bg-transparent text-base leading-relaxed outline-none placeholder:text-subtle"
        />
        <div className="flex items-center justify-between gap-3">
          <span
            id="capture-hint"
            className="hidden text-xs text-subtle md:inline"
          >
            ⌘ Enter to save
          </span>
          <button
            type="submit"
            disabled={!text.trim()}
            aria-label="Save thought"
            className="ml-auto flex size-11 items-center justify-center rounded-full bg-primary text-primary-foreground transition-opacity disabled:opacity-40"
          >
            <ArrowUp className="size-5" aria-hidden="true" />
          </button>
        </div>
      </form>

      {error && (
        <p id="capture-error" role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}

      {optimistic.length > 0 && (
        <section aria-labelledby="just-saved" className="flex flex-col gap-2.5">
          <h2
            id="just-saved"
            className="font-mono text-[11px] tracking-[0.08em] text-subtle"
          >
            JUST SAVED
          </h2>
          <ul className="overflow-hidden rounded-card border bg-surface">
            {optimistic.map((item) => (
              <li
                key={item.id}
                className="flex items-start gap-3 border-b px-4 py-3 last:border-b-0"
              >
                {item.pending ? (
                  <Loader2
                    className="mt-0.5 size-4 shrink-0 animate-spin text-subtle"
                    aria-label="Saving"
                  />
                ) : (
                  <Check
                    className="mt-0.5 size-4 shrink-0 text-project-3"
                    aria-label="Saved"
                  />
                )}
                <span
                  className={cn(
                    "min-w-0 flex-1 text-sm break-words whitespace-pre-wrap",
                    item.pending && "text-muted-foreground",
                  )}
                >
                  {item.content}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
