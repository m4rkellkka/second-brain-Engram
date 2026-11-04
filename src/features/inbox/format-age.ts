const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

const sameYear = new Intl.DateTimeFormat("en", {
  month: "short",
  day: "numeric",
});
const otherYear = new Intl.DateTimeFormat("en", {
  month: "short",
  day: "numeric",
  year: "numeric",
});

/** Compact age for the Inbox: `now`, `5m`, `2h`, `3d`, then `Oct 12`. */
export function formatAge(date: Date, now: Date): string {
  const age = now.getTime() - date.getTime();
  if (age < MINUTE) return "now";
  if (age < HOUR) return `${Math.floor(age / MINUTE)}m`;
  if (age < DAY) return `${Math.floor(age / HOUR)}h`;
  if (age < 7 * DAY) return `${Math.floor(age / DAY)}d`;
  return (
    date.getFullYear() === now.getFullYear() ? sameYear : otherYear
  ).format(date);
}

/** Due date in the capture's time zone: `Fri, Nov 6` or `Fri, Nov 6, 18:00`. */
export function formatDue(date: Date, timeZone: string | null): string {
  let zone = timeZone ?? "UTC";
  try {
    new Intl.DateTimeFormat("en", { timeZone: zone });
  } catch {
    zone = "UTC";
  }
  const time = new Intl.DateTimeFormat("en-GB", {
    timeZone: zone,
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
  const day = new Intl.DateTimeFormat("en", {
    timeZone: zone,
    weekday: "short",
    month: "short",
    day: "numeric",
  }).format(date);
  // 09:00 is what the sorter uses for a date without a time.
  return time === "09:00" ? day : `${day}, ${time}`;
}
