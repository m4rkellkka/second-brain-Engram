# Progress

**Current version:** 0.6.0 · **Current phase:** Phase 7 — Claude connector + search · status: **not started**

Engram was rebuilt as a native macOS app on 2026-11-05 (see `docs/SPEC.md`). Phases 0–5 shipped the Next.js + Supabase web app, kept on the `web-archive` branch.

| Phase | Name                         | Status                 |
| ----- | ---------------------------- | ---------------------- |
| 0–5   | Web app (Next.js + Supabase) | done (v0.1.0 – v0.5.0) |
| 6     | Native foundation            | done (v0.6.0)          |
| 7     | Claude connector + search    | —                      |
| 8     | Projects & live context      | —                      |
| 9     | Brain graph                  | —                      |
| 10    | Open-source launch           | —                      |

## Phase 6 checklist (done)

- [x] Web app removed from `demo` (kept on `web-archive`); local Supabase stack and its volumes deleted
- [x] Xcode project with a synchronized `App/` folder + `EngramKit` package; `Makefile`; `swift format`; version in `Config/Version.xcconfig`
- [x] Design tokens, bundled Geist fonts, app icon
- [x] SQLite via GRDB, WAL, migration v1 with the full schema and an FTS5 index
- [x] Window with sidebar (Inbox, Projects, Brain placeholders); stays in the menu bar when closed
- [x] Menu-bar capture popover and ⌘N; Enter saves, Shift+Enter adds a line
- [x] Inbox: latest 50, kind filter, project menu with inline "New project…", live updates
- [x] 25 tests (schema, WAL reopen, FTS, thoughts, inbox, projects, slugs)
- [x] CI on `macos-26` for `chore` commits
- [x] README, CHANGELOG, release v0.6.0

## Environments

| What           | Where                                                        | Notes                                                             |
| -------------- | ------------------------------------------------------------ | ----------------------------------------------------------------- |
| Native app     | `~/Library/Application Support/Engram/engram.sqlite`         | Debug builds take `-EngramDatabasePath <file>` for test data      |
| Cloud Supabase | Project `engram` (`fsnmuvzztrelevofjkyv`), paused 2026-11-04 | Not used; restorable for 90 days, then delete it in the dashboard |

## Decisions

Rows before 2026-11-05 describe the web app (now on the `web-archive` branch).

| Date       | Decision                                                                                | Why                                                                                                       |
| ---------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 2026-11-03 | Own UI (PWA) instead of a Telegram bot                                                  | Wanted a polished app usable on phone and desktop                                                         |
| 2026-11-03 | Supabase + pgvector                                                                     | Sync across devices, auth, storage and vector search in one place                                         |
| 2026-11-03 | Single user per self-hosted instance                                                    | Simple open-source story, no storing other people's API keys                                              |
| 2026-11-03 | Name: Engram                                                                            | A "memory trace" in neuroscience; Synapse was taken by big products                                       |
| 2026-11-03 | All MVP phases on the `demo` branch; `main` after Phase 8                               | Simple flow for a solo project; each phase is still reviewed at its gate                                  |
| 2026-11-03 | SemVer: each phase bumps minor, fixes bump patch, 1.0.0 = stable                        | Version history matches the build phases; CHANGELOG + git tag per release                                 |
| 2026-11-03 | pnpm via corepack, pinned in `packageManager`                                           | No global install, everyone gets the same pnpm version                                                    |
| 2026-11-03 | Supabase CLI as a devDependency (`pnpm supabase …`)                                     | CLI version pinned per project; contributors get it with `pnpm install`                                   |
| 2026-11-03 | Local Supabase ports moved to 553xx                                                     | Default 543xx ports are taken by another local project on the dev machine                                 |
| 2026-11-03 | Next.js 16.4 defaults kept: Cache Components + Partial Prefetching                      | Recommended defaults for new apps                                                                         |
| 2026-11-03 | Env validated in `src/lib/env.ts` + `src/server/env.ts`, imported from `next.config.ts` | Missing or invalid env fails `dev`/`build` immediately                                                    |
| 2026-11-03 | shadcn/ui with Radix base, Nova preset; `cn` package for classes                        | shadcn's current default; `cn` replaces clsx + tailwind-merge                                             |
| 2026-11-03 | Cloud Supabase on the Free plan (2nd of 2 free projects)                                | Needed to sign in from the phone; DB quota is per project, other quotas are tiny here                     |
| 2026-11-03 | Sign-in limited by `ALLOWED_EMAILS` (only Mikhail for now)                              | Defense in depth next to disabled sign-up                                                                 |
| 2026-11-03 | Composite FKs on `(id, user_id)` for every cross-table reference                        | RLS alone lets a user reference someone else's row by id                                                  |
| 2026-11-03 | Email + password instead of magic links (v0.2.1)                                        | No SMTP needed, no email rate limit, works in the iOS PWA and across devices                              |
| 2026-11-03 | Public sign-up disabled in Supabase Auth; account created in the dashboard              | The publishable key is public, so the app-level allow-list alone could be bypassed                        |
| 2026-11-03 | Sign-out is per device (`scope: "local"`)                                               | Signing out on the laptop shouldn't sign out the phone                                                    |
| 2026-11-03 | Full-text search with the `simple` config                                               | Notes mix Russian and English                                                                             |
| 2026-11-03 | Seed (local only): dev user `dev@engram.local`, projects Tamam and Engram               | Realistic projects for development; cloud gets no seed                                                    |
| 2026-11-03 | RLS tests run in CI against a throwaway local stack                                     | Data isolation is checked on every push                                                                   |
| 2026-11-03 | Next dev indicator disabled                                                             | It covers the mobile header and tab bar in every corner                                                   |
| 2026-11-04 | CI runs only for `chore` head commits on `demo`/`dev`, never on `main`                  | Mikhail's call: fewer CI runs; every commit is checked locally before it is made                          |
| 2026-11-04 | Inbox project picker is a native `<select>`                                             | iOS shows its own wheel, accessible for free, no new dependency                                           |
| 2026-11-04 | New project slugs transliterate Cyrillic (`Жизнь` → `zhizn`)                            | Most project names are Russian; slugs feed project URLs in Phase 5                                        |
| 2026-11-04 | Visual checks run the dev server against the local stack, not the cloud                 | Test captures must not land in Mikhail's real data                                                        |
| 2026-11-04 | Cloud account recreated (old one deleted, new one made in the dashboard)                | Old password was lost; cascade removed the old data, allow-list updated, sign-up still closed             |
| 2026-11-04 | Default LLM provider: Claude API (Anthropic) via the Vercel AI SDK                      | Mikhail's call; provider and models stay configurable via env                                             |
| 2026-11-04 | New Phase 9: Claude connector (MCP), after the MVP, before 1.0.0                        | Mikhail wants to talk with Claude in its app and say "save this to Engram"                                |
| 2026-11-04 | Phase 3 sorting on Claude Haiku 5.5 in the app and in evals (Sonnet 5.5 via env)        | Mikhail's call: Sonnet costs ~20x more; Haiku got 5/5 on the example set                                  |
| 2026-11-04 | Phase 4 (voice capture) dropped; releases numbered in order (Phase 5 → 0.5.0)           | No second AI provider just for speech; keyboard dictation and the Phase 9 Claude connector cover voice    |
| 2026-11-04 | Project context stored as rows, not one JSON column                                     | No lost updates between captures, per-item source and provenance, easier for Phase 9                      |
| 2026-11-04 | Context updates use the same model as sorting (no separate env var)                     | One model setting is enough for now                                                                       |
| 2026-11-04 | Renaming a project keeps its slug; projects are archived, not deleted                   | Links stay stable; delete can come later                                                                  |
| 2026-11-04 | Engram runs locally only; the cloud Supabase project is paused                          | Mikhail needs the free-plan slot; captures will come from conversations with Claude                       |
| 2026-11-04 | AI never creates projects; it suggests one on the "not sure" card                       | Avoids a pile of junk projects; creating is one tap                                                       |
| 2026-11-04 | Capture timezone comes from the browser and is stored on the capture                    | "Friday" resolves correctly, also on retries and when travelling                                          |
| 2026-11-04 | After 3 failed sorts the thought is kept as a plain note with `needs_review`            | Nothing typed is ever lost                                                                                |
| 2026-11-05 | Engram becomes a native macOS app (Swift, SwiftUI); web app archived on `web-archive`   | Local and simple: one `.app`, no Docker, server or login; easier for open-source users                    |
| 2026-11-05 | Claude Desktop is the main way in, through a local MCP connector (stdio)                | Claude already understands the conversation, so it sorts and saves; uses the subscription, not an API key |
| 2026-11-05 | No in-app AI provider in the MVP; typed thoughts are sorted by Claude on request        | Zero cost and zero keys to run Engram; an optional API key can come later                                 |
| 2026-11-05 | SQLite via GRDB (not SwiftData), FTS5 search, no embeddings                             | Full-text search that handles Russian, safe access from the app and the connector process                 |
| 2026-11-05 | Automatic pickup of Claude chats dropped from the MVP                                   | Test: a scheduled task saw only memory, not today's chats; scheduled tasks run in the cloud               |
| 2026-11-05 | Releases ad-hoc signed, not notarized; install step documented (`xattr` or Open Anyway) | No paid Apple Developer account needed                                                                    |
| 2026-11-05 | Version numbers continue (Phase 6 → 0.6.0 … Phase 10 → 0.10.0); macOS only for now      | Keeps SemVer history; Windows is a post-MVP idea                                                          |
| 2026-11-05 | No global hotkey and no launch at login for now; capture from the menu bar and ⌘N        | Mikhail's call; both are post-MVP ideas                                                                |
| 2026-11-05 | Hand-written Xcode project with a synchronized `App/` folder, no XcodeGen                | New files need no project edits; contributors just open it in Xcode                                    |
| 2026-11-05 | Capture field is an `NSTextView` bridge                                                  | Only AppKit tells Return (save) from Shift+Return (new line) reliably                                   |
| 2026-11-05 | Timestamps in GRDB's UTC text format; dedupe hash unique only for Claude summaries       | Sortable and SQLite-friendly; typing the same thought twice is fine                                    |
| 2026-11-05 | Bundle id `io.github.m4rkellkka.Engram`, ad-hoc signed, hardened runtime                 | No paid developer account; an id tied to the GitHub account, not a domain we don't own                 |
| 2026-11-05 | CI on the stable `macos-26` image (Xcode 26.6), not the Xcode 27 preview                 | Nothing needs Xcode 27; previews break                                                                 |

## Open questions

- [ ] Phase 6 "done when" (under 3 seconds from the menu-bar icon) needs Mikhail's hand check: keystrokes can't be automated here without Accessibility permission
- [ ] Phase 7: connect through a Claude Desktop Extension (`.mcpb`) or by editing `claude_desktop_config.json`?
- [ ] Is "Engram" free on GitHub and as a Mac app name?
- [ ] iPhone path while the Mac is off (see SPEC → Post-MVP): scheduled task into a connected folder, iCloud Drive inbox via a Shortcut, or a tunnel

## Ideas for later

- **Diary mode** (Mikhail, 2026-11-04): talk with Claude about how the day went and it saves a journal entry; may need a `journal` entry kind
- Claude scheduled task triggered by API from Engram (Mikhail, 2026-11-05), once a task can reach the connector or a connected folder
- Optional in-app sorting with the user's own API key
- Today screen, reminders, Obsidian and Apple Notes import
- Global hotkey for capture (⌘⇧Space in the mockups) and launch at login (Mikhail, 2026-11-05: not now)
- Windows version
- Notarized releases and a Homebrew cask
