# Progress

**Current phase:** Phase 0 — Foundation · status: **not started**

| Phase | Name | Status |
| --- | --- | --- |
| 0 | Foundation | not started |
| 1 | Auth & data model | — |
| 2 | Text capture, Inbox & PWA | — |
| 3 | AI sorting | — |
| 4 | Voice capture | — |
| 5 | Projects & live context | — |
| 6 | Search & Ask | — |
| 7 | Brain graph | — |
| 8 | Open-source launch | — |

## Decisions

| Date | Decision | Why |
| --- | --- | --- |
| 2026-11-03 | Own UI (PWA) instead of a Telegram bot | Wanted a polished app usable on phone and desktop |
| 2026-11-03 | Supabase + pgvector | Sync across devices, auth, storage and vector search in one place |
| 2026-11-03 | Single user per self-hosted instance | Simple open-source story, no storing other people's API keys |
| 2026-11-03 | Name: Engram | A "memory trace" in neuroscience; Synapse was taken by big products |

## Open questions

- [ ] Is "Engram" free on GitHub, npm and a domain?
- [ ] Default LLM provider for sorting and Ask?
- [ ] Supabase cloud free tier or local Docker for Mikhail's own instance?

## Ideas for later

- MCP server so Claude / Cursor can read Engram context
- Today screen, reminders, iOS Shortcut capture, Obsidian import
