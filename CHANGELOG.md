# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-11-04

### Added

- Projects list with status, open tasks, entry count and last update; create a project from it.
- Project page with a live context: summary, status, stack, decisions and open ideas, each AI item showing the notes it came from, plus the project's tasks with checkboxes.
- Live context updates itself: after a capture is sorted, Claude adds what the new entries say to the project's page. It only adds, never deletes, and anything you write by hand stays as you wrote it ("Let AI update" hands it back).
- Filing an entry by hand or confirming it in the Inbox also updates its project.
- Rename, recolor and archive projects.

### Changed

- Project context is stored as rows instead of one JSON column; existing context is migrated.

### Fixed

- The active navigation item no longer blocks rendering on dynamic routes.

## [0.4.0] - 2026-11-04

### Added

- AI sorting: after a capture is saved, Claude splits it into entries and sets kind, project, due date, link and confidence. It runs after the response, so saving stays instant. Default model Claude Haiku 5.5 (`AI_SORT_MODEL`), about $0.0002 per capture.
- "Sorting" cards in the Inbox for captures still being sorted; the Inbox refreshes itself until they are done.
- "Not sure" cards for entries with low confidence or no project: "Looks right", one tap to create a suggested project, or pick one.
- The type of an entry can be changed from its card; due dates and links show on the card.
- Corrections (project, type, confirm) are stored for later use as examples.
- Every model call is logged with tokens, cost and duration (`ai_calls`).
- Retries: up to 3 attempts per capture, run after each save, from the Inbox and from a daily Vercel Cron route. After the last failure the text is kept as a note to review.
- `pnpm eval:sort` checks sorting accuracy and cost against fixture captures.

### Changed

- Saving a capture no longer creates the entry directly; the sorting pipeline does. Without `ANTHROPIC_API_KEY` captures are kept as plain notes, as before.

## [0.3.0] - 2026-11-04

### Added

- Capture screen: the text field is focused on open; save with the button or ⌘/Ctrl+Enter. Saved thoughts show up at once in a "Just saved" list, and the text comes back if saving fails.
- `create_text_capture` database function: one text capture and one `note` entry, saved atomically under RLS.
- Inbox: the latest 50 entries, newest first, with type filters (`?kind=`) and a project picker on every entry, including an inline "+ New project".
- The Inbox refreshes when the tab or the installed app comes back to the foreground, so a thought saved on the phone shows up on the laptop.
- Installable PWA: web app manifest, home-screen icon and iOS meta tags; the app opens on Capture.

### Changed

- CI runs only when the pushed head commit is a `chore` commit on `demo` or `dev`, and never on `main` or pull requests.

## [0.2.1] - 2026-11-03

### Changed

- Sign-in uses email and password instead of magic links. No emails are sent, so it works on every device, in the installed iOS PWA and without an SMTP provider.
- After a failed sign-in the email stays in the form; only the password is cleared.
- The seeded local user `dev@engram.local` has the password `engram-dev`.

### Removed

- Magic link flow: the `/auth/confirm` route, the custom email template and the LAN redirect URLs.

### Security

- Public sign-up is disabled in Supabase Auth, locally and in the cloud, so nobody can create an account through the API with the publishable key. Covered by a new auth test.
- A non-allowed email gets the same error as a wrong password, so the form doesn't reveal who may sign in.

## [0.2.0] - 2026-11-03

### Added

- Database schema: projects, captures, entries and entry links, with enums, pgvector embeddings, full-text and retry indexes.
- Row Level Security on every table and a private `audio` Storage bucket limited to the owner's folder.
- Composite `(id, user_id)` foreign keys, so rows can only reference rows of the same owner.
- Generated TypeScript database types (`pnpm db:types`).
- Magic-link sign-in at `/login`, link confirmation at `/auth/confirm`, sign-out on desktop and mobile.
- Route protection in `proxy.ts`: signed-out visitors land on `/login`.
- `ALLOWED_EMAILS` server env var: only listed emails can sign in.
- Local seed with a dev user and sample projects.
- RLS test suite (Vitest) against the local stack, also run in CI.
- Cloud Supabase project with migrations and redirect URLs for laptop and phone.

### Changed

- Next.js dev indicator is disabled; it covered the mobile header.

## [0.1.0] - 2026-11-03

### Added

- Next.js 16 app (App Router, TypeScript strict) with pnpm, ESLint and Prettier.
- Tailwind CSS v4 + shadcn/ui themed with the Engram design tokens (dark theme, Geist fonts, project colors).
- App shell: desktop sidebar and mobile tab bar with empty Capture, Inbox, Projects, Ask and Brain screens.
- Zod-validated environment variables and `.env.example`.
- Local Supabase stack config (`pnpm db:start`).
- GitHub Actions CI: lint, format check, typecheck and build.
- MIT license.

[Unreleased]: https://github.com/m4rkellkka/second-brain-Engram/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/m4rkellkka/second-brain-Engram/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/m4rkellkka/second-brain-Engram/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/m4rkellkka/second-brain-Engram/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/m4rkellkka/second-brain-Engram/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/m4rkellkka/second-brain-Engram/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/m4rkellkka/second-brain-Engram/releases/tag/v0.1.0
