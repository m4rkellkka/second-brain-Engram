"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { retryPendingCaptures } from "./actions";

const POLL_MS = 3_000;
/** Stop polling after this; refresh on focus takes over. */
const MAX_POLL_MS = 90_000;

/**
 * While captures are being sorted, re-fetches the Inbox every few seconds
 * so sorted entries replace the "Sorting" cards. Captures that waited too
 * long get one retry request.
 */
export function PendingWatcher({
  count,
  stale,
}: {
  count: number;
  stale: boolean;
}) {
  const router = useRouter();

  useEffect(() => {
    if (stale) void retryPendingCaptures();
  }, [stale]);

  useEffect(() => {
    if (count === 0) return;
    const started = Date.now();
    const timer = window.setInterval(() => {
      if (Date.now() - started > MAX_POLL_MS) {
        window.clearInterval(timer);
        return;
      }
      if (document.visibilityState === "visible") router.refresh();
    }, POLL_MS);
    return () => window.clearInterval(timer);
  }, [count, router]);

  return null;
}
