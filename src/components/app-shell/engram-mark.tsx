import type { SVGProps } from "react";

/** Engram logo mark: three linked nodes. Also used as the Brain nav icon. */
export function EngramMark(props: SVGProps<SVGSVGElement>) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      aria-hidden="true"
      {...props}
    >
      <circle cx="6" cy="6" r="2.5" />
      <circle cx="18" cy="8" r="2.5" />
      <circle cx="10" cy="18" r="2.5" />
      <path d="M8.2 7 15.6 7.8M7 8.3l2.2 7.4M16.6 10.1l-4.8 6.2" />
    </svg>
  );
}
