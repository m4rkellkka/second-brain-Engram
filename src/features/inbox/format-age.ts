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
