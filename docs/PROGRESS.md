# Progress

**Current version:** 0.9.1 · **Current phase:** Phase 10 — Open-source launch · status: **not started**

Engram was rebuilt as a native macOS app on 2026-11-05 (see `docs/SPEC.md`). Phases 0–5 shipped the Next.js + Supabase web app, kept on the `web-archive` branch.

| Phase | Name                         | Status                 |
| ----- | ---------------------------- | ---------------------- |
| 0–5   | Web app (Next.js + Supabase) | done (v0.1.0 – v0.5.0) |
| 6     | Native foundation            | done (v0.6.0)          |
| 7     | Claude connector + search    | done (v0.7.0)          |
| 8     | Projects & live context      | done (v0.8.0)          |
| 9     | Brain graph                  | done (v0.9.0)          |
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

## Phase 7 checklist (done)

- [x] `Engram --mcp` connector on the MCP Swift SDK with 7 tools; save rules and validation in EngramKit
- [x] Migration v2: `suggested_project`, search index rebuilt with "ё" folded into "е"
- [x] Keyword links (≥ 2 shared keywords) in `entry_links`
- [x] Full-text search (prefix, filters, light Russian ending trim) for the tool and ⌘K
- [x] Settings: connect / disconnect Claude Desktop, backup of its config
- [x] Live refresh of the open app after connector writes (Darwin notification)
- [x] "Not sure" cards, kind menu, source label, corrections
- [x] 61 tests; `make eval-connector`
- [x] Eval on 2026-11-05 (Sonnet, `claude -p`): 10/10 conversations filed correctly, both questions answered correctly after the local-time fix
- [x] CHANGELOG, README, release v0.7.0

## Phase 8 checklist (done)

- [x] Bulk filing: creating a suggested project files every entry with that suggestion
- [x] Migration v3 (`dismissed_at`); `contextUpdates` in `save_to_engram` and `sort_capture`; items point at entries by index
- [x] Rules: Claude only adds, repeats skipped, user summary/status kept, removed items not re-added
- [x] Hand edits: summary/status ("Let Claude update"), add/edit/remove items, rename (slug kept), recolor, archive
- [x] Projects list and live project page; task checkboxes on the page and in the Inbox; Inbox and ⌘K open projects
- [x] `get_project_context` returns the full live context
- [x] 73 tests; eval extended with 3 context conversations
- [x] Eval on 2026-11-05: user-written Tamam summary kept, status and new items added, repeated decision not duplicated
- [x] CHANGELOG, README, release v0.8.0

## Phase 9 checklist (done)

- [x] SceneKit vs RealityKit compared; RealityKit chosen (SceneKit deprecated at WWDC 2025)
- [x] Graph snapshot (active projects, unfiled entries, keyword links) and a deterministic layout in EngramKit
- [x] Merged meshes: per-project dots, hub with halo, spokes; links inside and across projects
- [x] Auto-rotate (pauses on drag), drag, scroll/pinch zoom, hover label, click opens the project or the Inbox
- [x] Legend, empty state, live updates; debug fps counter and picking markers
- [x] `make demo-graph`: 2,000 entries and 2,858 links at 60 fps on the MacBook (screenshot in docs/images/brain.png)
- [x] 78 tests; CHANGELOG, README, release v0.9.0

## Phase 9 follow-up (v0.9.1, Mikhail's feedback)

- [x] `update_project` and `complete_task` tools: in a real chat Claude couldn't update a page or tick a task
- [x] Graph redrawn with Metal ("synapses"): glow, depth fog, link-sized dots, labels, pulses, flashes, hover highlight, focus + side panel; 60 fps on 2,000 entries

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
| 2026-11-05 | Connector is `Engram --mcp` (same binary), not a separate helper target                  | No second target, embedding step or signature                                                          |
| 2026-11-05 | Official MCP Swift SDK (pulls swift-nio and 5 more packages)                              | Protocol versions are the SDK's job, not ours                                                          |
| 2026-11-05 | Connect by writing `claude_desktop_config.json` from Settings; `.mcpb` in Phase 10       | Simplest path that works now; one-click install matters for other people at launch                    |
| 2026-11-05 | Below 0.7 confidence or no matching project → "not sure"; Claude never creates projects  | Same rule as the web app                                                                               |
| 2026-11-05 | Tool results use local time; date-only deadlines come back as plain dates                 | Eval: Claude read a UTC midnight deadline as "today 21:00"                                             |
| 2026-11-05 | Search index stores text with "ё" → "е"                                                   | unicode61 doesn't fold Cyrillic "ё"; people type both                                                  |
| 2026-11-05 | Context items point at entries by index in the same call                                   | Claude knows indexes before the entries have ids                                                       |
| 2026-11-05 | Removed context items stay as tombstones (`dismissed_at`)                                 | Otherwise Claude re-adds what the user removed                                                         |
| 2026-11-05 | "Create <suggested project>" files all matching "not sure" entries                        | Mikhail's first real save: 29 entries, no projects yet, 29 clicks                                       |
| 2026-11-05 | Project rename keeps the slug                                                             | Claude and links keep working                                                                          |
| 2026-11-05 | RealityKit for the graph, with a dozen merged meshes and our own picking                 | SceneKit is deprecated; per-entity rendering wouldn't scale to 2,000 dots                              |
| 2026-11-05 | Fixed, deterministic layout instead of a live physics simulation                         | Same picture every launch; the slow rotation gives the "alive" feel                                     |
| 2026-11-05 | Entries of archived projects stay out of the graph                                       | The graph shows what is active                                                                         |
| 2026-11-05 | Graph moved from RealityKit to a small Metal renderer (v0.9.1)                           | Mikhail found it flat; glow, fog and dashes need custom shaders                                        |
| 2026-11-05 | Shaders compile at launch from source, and a test compiles them                          | No Metal toolchain download needed to build; a shader typo can't ship silently                         |
| 2026-11-05 | Dedicated `update_project` and `complete_task` tools                                     | Claude didn't discover `contextUpdates` inside `save_to_engram` in a real chat                          |

## Open questions

- [ ] Entries from one save show newest-first in the Inbox, so their order is reversed; fine for now, revisit with project pages
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
