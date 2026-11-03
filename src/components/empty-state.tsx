import type { ComponentType, SVGProps } from "react";

type EmptyStateProps = {
  icon: ComponentType<SVGProps<SVGSVGElement>>;
  title: string;
  description: string;
};

/** Placeholder for a screen that has no content yet. */
export function EmptyState({
  icon: Icon,
  title,
  description,
}: EmptyStateProps) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-4 py-16 text-center">
      <div className="flex size-14 items-center justify-center rounded-card border bg-surface text-primary">
        <Icon className="size-6" />
      </div>
      <h1 className="mt-5 text-2xl font-semibold tracking-tight">{title}</h1>
      <p className="mt-2 max-w-sm text-muted-foreground">{description}</p>
    </div>
  );
}
