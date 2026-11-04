# Progress

**Current version:** 0.5.0 · **Current phase:** Phase 6 — being redefined (local mode + Claude connector) · status: **not started**

| Phase | Name                      | Status        |
| ----- | ------------------------- | ------------- |
| 0     | Foundation                | done (v0.1.0) |
| 1     | Auth & data model         | done (v0.2.1) |
| 2     | Text capture, Inbox & PWA | done (v0.3.0) |
| 3     | AI sorting                | done (v0.4.0) |
| 4     | Voice capture             | dropped       |
| 5     | Projects & live context   | done (v0.5.0) |
| 6     | Search & Ask              | —             |
| 7     | Brain graph               | —             |
| 8     | Open-source launch        | —             |
| 9     | Claude connector (MCP)    | —             |

## Phase 2 checklist (done)

- [x] `create_text_capture` DB function: one text capture + one note entry, atomic (applied locally and in the cloud)
- [x] `saveCapture` server action with shared zod schema
- [x] Tests for the schema and the function
- [x] Capture screen: textarea focused on open, Save button and ⌘Enter, optimistic "Just saved" list (no mic button until Phase 4). Checked in WebKit on an iPhone viewport
- [x] Inbox: latest 50 entries, `?kind=` filter, project picker with inline "+ New project". Checked in WebKit (iPhone + desktop)
- [x] Refresh the Inbox on tab/app focus
- [x] PWA: `manifest.ts`, apple-touch-icon via `ImageResponse`, iOS meta, start at `/capture`. Installed and used on Mikhail's iPhone
- [x] Move rls/auth tests onto `tests/support/local-supabase.ts`
- [x] Release v0.3.0, CHANGELOG, phase report

## Phase 3 checklist (done)

- [x] Migration: pending captures with time zone, `claim_capture`, `apply_sorted_capture`, `fail_capture`, `ai_calls`, `entry_corrections` (local and cloud)
- [x] Provider layer on the Vercel AI SDK + `@ai-sdk/anthropic`; `AI_SORT_MODEL` (default Haiku 5.5), effort low
- [x] Sort step with structured output; projects, local time and time zone in the prompt
- [x] Pipeline in `after()`: claim → sort → entries → processed; failures retried, note kept after 3 attempts; no API key → plain note
- [x] Retry sweep after each save and from the Inbox; daily Vercel Cron route as a backstop
- [x] Inbox: "Sorting" cards with polling, "not sure" cards, kind select, due date and link chips; corrections saved
- [x] Token usage and cost logged per call in `ai_calls`
- [x] Tests: pipeline with a mock model against the local stack, row mapping, cost; WebKit check of the Inbox
- [x] `pnpm eval:sort` with an example fixture set
- [x] Eval on the 5 example captures with Haiku 5.5: 5/5 right, $0.00018 and ~1.8 s per capture. The 20 real captures are still open (see Open questions)
- [x] Release v0.4.0, CHANGELOG, phase report

## Phase 5 checklist (done)

- [x] Context as rows (`project_context_items`), summary and status with a source; old JSON migrated; `apply_context_patch` (local; **cloud push waits for Mikhail**: `pnpm db:push`)
- [x] Context updater (pipeline step 6) on Haiku: small patch, append-only, hand edits win; also runs after a manual fix in the Inbox
- [x] Projects list and project page: summary, status, stack, decisions, open ideas with sources, tasks with checkboxes
- [x] Create, rename, recolor, archive
- [x] Tests: patch cleaning, user-edit rules, RLS, updater with a mock model; WebKit check of list and page

## Environments

| Env   | Supabase                                                         | Notes                                                                      |
| ----- | ---------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Local | Docker stack, API `127.0.0.1:55321`                              | Migrations + seed via `pnpm db:reset`; mail in Mailpit                     |
| Cloud | Project `engram` (`fsnmuvzztrelevofjkyv`), **paused 2026-11-04** | Not used any more; restorable for 90 days, then delete it in the dashboard |

## Decisions

| Date       | Decision                                                                                | Why                                                                                                    |
| ---------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 2026-11-03 | Own UI (PWA) instead of a Telegram bot                                                  | Wanted a polished app usable on phone and desktop                                                      |
| 2026-11-03 | Supabase + pgvector                                                                     | Sync across devices, auth, storage and vector search in one place                                      |
| 2026-11-03 | Single user per self-hosted instance                                                    | Simple open-source story, no storing other people's API keys                                           |
| 2026-11-03 | Name: Engram                                                                            | A "memory trace" in neuroscience; Synapse was taken by big products                                    |
| 2026-11-03 | All MVP phases on the `demo` branch; `main` after Phase 8                               | Simple flow for a solo project; each phase is still reviewed at its gate                               |
| 2026-11-03 | SemVer: each phase bumps minor, fixes bump patch, 1.0.0 = stable                        | Version history matches the build phases; CHANGELOG + git tag per release                              |
| 2026-11-03 | pnpm via corepack, pinned in `packageManager`                                           | No global install, everyone gets the same pnpm version                                                 |
| 2026-11-03 | Supabase CLI as a devDependency (`pnpm supabase …`)                                     | CLI version pinned per project; contributors get it with `pnpm install`                                |
| 2026-11-03 | Local Supabase ports moved to 553xx                                                     | Default 543xx ports are taken by another local project on the dev machine                              |
| 2026-11-03 | Next.js 16.4 defaults kept: Cache Components + Partial Prefetching                      | Recommended defaults for new apps                                                                      |
| 2026-11-03 | Env validated in `src/lib/env.ts` + `src/server/env.ts`, imported from `next.config.ts` | Missing or invalid env fails `dev`/`build` immediately                                                 |
| 2026-11-03 | shadcn/ui with Radix base, Nova preset; `cn` package for classes                        | shadcn's current default; `cn` replaces clsx + tailwind-merge                                          |
| 2026-11-03 | Cloud Supabase on the Free plan (2nd of 2 free projects)                                | Needed to sign in from the phone; DB quota is per project, other quotas are tiny here                  |
| 2026-11-03 | Sign-in limited by `ALLOWED_EMAILS` (only Mikhail for now)                              | Defense in depth next to disabled sign-up                                                              |
| 2026-11-03 | Composite FKs on `(id, user_id)` for every cross-table reference                        | RLS alone lets a user reference someone else's row by id                                               |
| 2026-11-03 | Email + password instead of magic links (v0.2.1)                                        | No SMTP needed, no email rate limit, works in the iOS PWA and across devices                           |
| 2026-11-03 | Public sign-up disabled in Supabase Auth; account created in the dashboard              | The publishable key is public, so the app-level allow-list alone could be bypassed                     |
| 2026-11-03 | Sign-out is per device (`scope: "local"`)                                               | Signing out on the laptop shouldn't sign out the phone                                                 |
| 2026-11-03 | Full-text search with the `simple` config                                               | Notes mix Russian and English                                                                          |
| 2026-11-03 | Seed (local only): dev user `dev@engram.local`, projects Tamam and Engram               | Realistic projects for development; cloud gets no seed                                                 |
| 2026-11-03 | RLS tests run in CI against a throwaway local stack                                     | Data isolation is checked on every push                                                                |
| 2026-11-03 | Next dev indicator disabled                                                             | It covers the mobile header and tab bar in every corner                                                |
| 2026-11-04 | CI runs only for `chore` head commits on `demo`/`dev`, never on `main`                  | Mikhail's call: fewer CI runs; every commit is checked locally before it is made                       |
| 2026-11-04 | Inbox project picker is a native `<select>`                                             | iOS shows its own wheel, accessible for free, no new dependency                                        |
| 2026-11-04 | New project slugs transliterate Cyrillic (`Жизнь` → `zhizn`)                            | Most project names are Russian; slugs feed project URLs in Phase 5                                     |
| 2026-11-04 | Visual checks run the dev server against the local stack, not the cloud                 | Test captures must not land in Mikhail's real data                                                     |
| 2026-11-04 | Cloud account recreated (old one deleted, new one made in the dashboard)                | Old password was lost; cascade removed the old data, allow-list updated, sign-up still closed          |
| 2026-11-04 | Default LLM provider: Claude API (Anthropic) via the Vercel AI SDK                      | Mikhail's call; provider and models stay configurable via env                                          |
| 2026-11-04 | New Phase 9: Claude connector (MCP), after the MVP, before 1.0.0                        | Mikhail wants to talk with Claude in its app and say "save this to Engram"                             |
| 2026-11-04 | Phase 3 sorting on Claude Haiku 5.5 in the app and in evals (Sonnet 5.5 via env)        | Mikhail's call: Sonnet costs ~20x more; Haiku got 5/5 on the example set                               |
| 2026-11-04 | Phase 4 (voice capture) dropped; releases numbered in order (Phase 5 → 0.5.0)           | No second AI provider just for speech; keyboard dictation and the Phase 9 Claude connector cover voice |
| 2026-11-04 | Project context stored as rows, not one JSON column                                     | No lost updates between captures, per-item source and provenance, easier for Phase 9                   |
| 2026-11-04 | Context updates use the same model as sorting (no separate env var)                     | One model setting is enough for now                                                                    |
| 2026-11-04 | Renaming a project keeps its slug; projects are archived, not deleted                   | Links stay stable; delete can come later                                                               |
| 2026-11-04 | Engram runs locally only; the cloud Supabase project is paused                          | Mikhail needs the free-plan slot; captures will come from conversations with Claude                    |
| 2026-11-04 | AI never creates projects; it suggests one on the "not sure" card                       | Avoids a pile of junk projects; creating is one tap                                                    |
| 2026-11-04 | Capture timezone comes from the browser and is stored on the capture                    | "Friday" resolves correctly, also on retries and when travelling                                       |
| 2026-11-04 | After 3 failed sorts the thought is kept as a plain note with `needs_review`            | Nothing typed is ever lost                                                                             |

## Open questions

- [ ] Is "Engram" free on GitHub, npm and a domain?
- [ ] Phase 3 "Done when" not fully met: the 17/20 check on real captures is still to run. Released without it at Mikhail's request; draft the 20 fixtures from his Inbox once it has real data, then `pnpm eval:sort`

## TODO (known gaps)

- [ ] **Service worker** (spec: PWA = manifest + service worker). Skipped in Phase 2: iOS installs the PWA without it and offline sync is out of the MVP. Add it with a cache strategy that never serves another session's data.
- [x] ~~Inline "+ New project" in the Inbox picker~~: kept as a shortcut; full project management shipped in Phase 5
- [ ] **Realtime Inbox.** Phase 2 refreshes on tab/app focus only: if the laptop window already has focus, a thought saved on the phone shows up only after switching away and back, or a reload (Mikhail noticed this in the Phase 2 check). Options: Supabase Realtime, or a light poll while the page is visible. Not needed now (Mikhail, 2026-11-04); revisit later if switching windows gets annoying.

## Ideas for later

- Voice recording inside Engram, only with a transcription provider the self-hoster picks (dropped as Phase 4)
- **Diary mode** (Mikhail, 2026-11-04): talk with Claude about how the day went and it saves a journal entry. Fits the Phase 9 connector (`save_to_engram` with a journal flavour); may need a `journal` entry kind
- Today screen, reminders, iOS Shortcut capture, Obsidian import
- Sidebar extras from the mockups: projects list with counts, top "Ask your brain" search with ⌘K (need data first)
- Desktop quick-capture shortcut (⌘⇧Space in the mockups)
- Phase 8: `pnpm user:create` script so self-hosters can create their account without the dashboard
- `pnpm/action-setup@v4` runs on deprecated Node 20 in CI; bump when a newer major is out
