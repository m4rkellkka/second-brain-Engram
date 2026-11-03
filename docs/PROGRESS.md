# Progress

**Current version:** 0.1.0 · **Current phase:** Phase 1 — Auth & data model · status: **not started**

| Phase | Name                      | Status        |
| ----- | ------------------------- | ------------- |
| 0     | Foundation                | done (v0.1.0) |
| 1     | Auth & data model         | —             |
| 2     | Text capture, Inbox & PWA | —             |
| 3     | AI sorting                | —             |
| 4     | Voice capture             | —             |
| 5     | Projects & live context   | —             |
| 6     | Search & Ask              | —             |
| 7     | Brain graph               | —             |
| 8     | Open-source launch        | —             |

## Decisions

| Date       | Decision                                                           | Why                                                                       |
| ---------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------- |
| 2026-11-03 | Own UI (PWA) instead of a Telegram bot                             | Wanted a polished app usable on phone and desktop                         |
| 2026-11-03 | Supabase + pgvector                                                | Sync across devices, auth, storage and vector search in one place         |
| 2026-11-03 | Single user per self-hosted instance                               | Simple open-source story, no storing other people's API keys              |
| 2026-11-03 | Name: Engram                                                       | A "memory trace" in neuroscience; Synapse was taken by big products       |
| 2026-11-03 | All MVP phases on the `demo` branch; `main` after Phase 8          | Simple flow for a solo project; each phase is still reviewed at its gate  |
| 2026-11-03 | SemVer: each phase bumps minor, fixes bump patch, 1.0.0 = stable   | Version history matches the build phases; CHANGELOG + git tag per release |
| 2026-11-03 | pnpm via corepack, pinned in `packageManager`                      | No global install, everyone gets the same pnpm version                    |
| 2026-11-03 | Supabase CLI as a devDependency (`pnpm supabase …`)                | CLI version pinned per project; contributors get it with `pnpm install`   |
| 2026-11-03 | Local Supabase ports moved to 553xx                                | Default 543xx ports are taken by another local project on the dev machine |
| 2026-11-03 | Next.js 16.4 defaults kept: Cache Components + Partial Prefetching | Recommended defaults for new apps; all current routes are static          |
| 2026-11-03 | Env validated in `src/lib/env.ts`, imported from `next.config.ts`  | Missing or invalid env fails `dev`/`build` immediately                    |
| 2026-11-03 | shadcn/ui with Radix base, Nova preset; `cn` package for classes   | shadcn's current default; `cn` replaces clsx + tailwind-merge             |
| 2026-11-03 | Vitest deferred to Phase 1                                         | No logic worth testing in Phase 0; first real tests are RLS               |

## Open questions

- [ ] Is "Engram" free on GitHub, npm and a domain?
- [ ] Default LLM provider for sorting and Ask?
- [ ] Supabase cloud free tier or local Docker for Mikhail's own instance?

## Ideas for later

- MCP server so Claude / Cursor can read Engram context
- Today screen, reminders, iOS Shortcut capture, Obsidian import
- Sidebar extras from the mockups: projects list with counts, user card, top "Ask your brain" search with ⌘K (need data/auth first)
- Desktop quick-capture shortcut (⌘⇧Space in the mockups)
