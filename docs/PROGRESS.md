# Progress

**Current version:** 0.2.0 · **Current phase:** Phase 2 — Text capture, Inbox & PWA · status: **not started**

| Phase | Name                      | Status        |
| ----- | ------------------------- | ------------- |
| 0     | Foundation                | done (v0.1.0) |
| 1     | Auth & data model         | done (v0.2.0) |
| 2     | Text capture, Inbox & PWA | —             |
| 3     | AI sorting                | —             |
| 4     | Voice capture             | —             |
| 5     | Projects & live context   | —             |
| 6     | Search & Ask              | —             |
| 7     | Brain graph               | —             |
| 8     | Open-source launch        | —             |

## Environments

| Env   | Supabase                                                      | Notes                                                                 |
| ----- | ------------------------------------------------------------- | --------------------------------------------------------------------- |
| Local | Docker stack, API `127.0.0.1:55321`                           | Migrations + seed via `pnpm db:reset`; mail in Mailpit                |
| Cloud | Project `engram` (`fsnmuvzztrelevofjkyv`), eu-central-1, Free | Migrations via `pnpm db:push`; auth config via `supabase config push` |

## Decisions

| Date       | Decision                                                                                | Why                                                                                   |
| ---------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| 2026-11-03 | Own UI (PWA) instead of a Telegram bot                                                  | Wanted a polished app usable on phone and desktop                                     |
| 2026-11-03 | Supabase + pgvector                                                                     | Sync across devices, auth, storage and vector search in one place                     |
| 2026-11-03 | Single user per self-hosted instance                                                    | Simple open-source story, no storing other people's API keys                          |
| 2026-11-03 | Name: Engram                                                                            | A "memory trace" in neuroscience; Synapse was taken by big products                   |
| 2026-11-03 | All MVP phases on the `demo` branch; `main` after Phase 8                               | Simple flow for a solo project; each phase is still reviewed at its gate              |
| 2026-11-03 | SemVer: each phase bumps minor, fixes bump patch, 1.0.0 = stable                        | Version history matches the build phases; CHANGELOG + git tag per release             |
| 2026-11-03 | pnpm via corepack, pinned in `packageManager`                                           | No global install, everyone gets the same pnpm version                                |
| 2026-11-03 | Supabase CLI as a devDependency (`pnpm supabase …`)                                     | CLI version pinned per project; contributors get it with `pnpm install`               |
| 2026-11-03 | Local Supabase ports moved to 553xx                                                     | Default 543xx ports are taken by another local project on the dev machine             |
| 2026-11-03 | Next.js 16.4 defaults kept: Cache Components + Partial Prefetching                      | Recommended defaults for new apps                                                     |
| 2026-11-03 | Env validated in `src/lib/env.ts` + `src/server/env.ts`, imported from `next.config.ts` | Missing or invalid env fails `dev`/`build` immediately                                |
| 2026-11-03 | shadcn/ui with Radix base, Nova preset; `cn` package for classes                        | shadcn's current default; `cn` replaces clsx + tailwind-merge                         |
| 2026-11-03 | Cloud Supabase on the Free plan (2nd of 2 free projects)                                | Needed to sign in from the phone; DB quota is per project, other quotas are tiny here |
| 2026-11-03 | Sign-in limited by `ALLOWED_EMAILS` (only Mikhail for now)                              | Magic link would otherwise create an account for any email                            |
| 2026-11-03 | Composite FKs on `(id, user_id)` for every cross-table reference                        | RLS alone lets a user reference someone else's row by id                              |
| 2026-11-03 | `/auth/confirm` handles both `token_hash` and PKCE `code`                               | Free tier can't edit email templates; cloud uses PKCE until custom SMTP               |
| 2026-11-03 | Sign-out is per device (`scope: "local"`)                                               | Signing out on the laptop shouldn't sign out the phone                                |
| 2026-11-03 | Full-text search with the `simple` config                                               | Notes mix Russian and English                                                         |
| 2026-11-03 | Seed (local only): dev user `dev@engram.local`, projects Tamam and Engram               | Realistic projects for development; cloud gets no seed                                |
| 2026-11-03 | RLS tests run in CI against a throwaway local stack                                     | Data isolation is checked on every push                                               |
| 2026-11-03 | Next dev indicator disabled                                                             | It covers the mobile header and tab bar in every corner                               |

## Open questions

- [ ] Is "Engram" free on GitHub, npm and a domain?
- [ ] Default LLM provider for sorting and Ask?
- [ ] Custom SMTP (e.g. Resend) for the cloud project? Unlocks the `token_hash` template (open the link on any device) and lifts the built-in hourly email limit.

## Ideas for later

- MCP server so Claude / Cursor can read Engram context
- Today screen, reminders, iOS Shortcut capture, Obsidian import
- Sidebar extras from the mockups: projects list with counts, top "Ask your brain" search with ⌘K (need data first)
- Desktop quick-capture shortcut (⌘⇧Space in the mockups)
- Phase 4: voice files share the org-wide 1 GB Storage quota with clinic-requests; delete audio after transcription or keep it only for N days
- One-time code (OTP) sign-in as an alternative to links, for the installed iOS PWA (links open in Safari, not in the PWA)
- `pnpm/action-setup@v4` runs on deprecated Node 20 in CI; bump when a newer major is out
