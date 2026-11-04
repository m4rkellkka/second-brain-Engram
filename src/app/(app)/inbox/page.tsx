import type { Metadata } from "next";
import { Suspense } from "react";
import { InboxFeed, InboxFeedSkeleton } from "@/features/inbox/inbox-feed";

export const metadata: Metadata = { title: "Inbox" };

export default function InboxPage({ searchParams }: PageProps<"/inbox">) {
  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 px-4 py-6 md:py-12">
      <h1 className="text-3xl font-semibold tracking-tight">Inbox</h1>
      {/* Reads the session and the URL, so it streams in at request time. */}
      <Suspense fallback={<InboxFeedSkeleton />}>
        <InboxFeed searchParams={searchParams} />
      </Suspense>
    </div>
  );
}
