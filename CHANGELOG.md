# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/m4rkellkka/second-brain-Engram/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/m4rkellkka/second-brain-Engram/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/m4rkellkka/second-brain-Engram/releases/tag/v0.1.0
