"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

/** `focus` and `visibilitychange` often fire together; refresh once. */
const MIN_INTERVAL_MS = 2_000;

/**
 * Re-fetches the page when the tab or the installed app comes back to the
 * foreground, so a thought saved on another device shows up here.
 */
export function RefreshOnFocus() {
  const router = useRouter();

  useEffect(() => {
    let last = Date.now();
    function refresh() {
      if (document.visibilityState !== "visible") return;
      const now = Date.now();
      if (now - last < MIN_INTERVAL_MS) return;
      last = now;
      router.refresh();
    }
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      window.removeEventListener("focus", refresh);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, [router]);

  return null;
}
