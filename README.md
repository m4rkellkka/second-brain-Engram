<h1 align="center">Engram</h1>

<p align="center">
  <strong>A self-hosted second brain.</strong><br>
  Dump thoughts by voice or text. AI files them into the right project,<br>
  keeps each project's context up to date and lets you ask your own notes.
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-0.2.1-8B9CFF">
  <img alt="Status" src="https://img.shields.io/badge/status-in%20development-F2A65A">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-3FD0B6">
  <img alt="Next.js" src="https://img.shields.io/badge/Next.js-16-EDEDF0">
  <img alt="Supabase" src="https://img.shields.io/badge/Supabase-Postgres%20%2B%20pgvector-3FD0B6">
</p>

---

> **Work in progress.** Engram is being built in public, one phase at a time.
> Sign-in, the secure data model and the app shell work today; AI sorting,
> voice, Ask and the 3D graph are on the roadmap below.

## Why

Ideas get lost, notes live nowhere, and every AI tool starts from zero about
your projects. Manual systems fail because filing is work and the payoff comes
late. Engram takes the filing off your hands:

- **Capture in under 3 seconds.** Open the app and type or talk. No folders, tags or required fields.
- **AI does the filing.** Type, project, tasks and due dates are extracted for you; you only fix mistakes.
- **Projects that remember.** Each project keeps a live context (summary, decisions, open ideas) updated from your notes.
- **Ask your notes.** Answers cite the entries they come from.
- **Your data, any model.** Your own Supabase, your own API keys, configurable LLM provider.

## Screens

| Screen       | What it does                                                             |
| ------------ | ------------------------------------------------------------------------ |
| **Capture**  | Instant text or voice input; shows how the last thought was filed        |
| **Inbox**    | Feed of recent entries, already typed and filed; fix anything in one tap |
| **Projects** | A project page with a context the AI keeps up to date                    |
| **Ask**      | Chat with your own notes, with source cards                              |
| **Brain**    | A 3D graph of everything, clustered by project                           |

One installable PWA for the phone and the desktop, dark theme only.

## Roadmap

| Phase | What                                               | Status         |
| ----- | -------------------------------------------------- | -------------- |
| 0     | Foundation: app shell, design tokens, CI           | ✅ v0.1.0      |
| 1     | Auth and data model: RLS, private storage, sign-in | ✅ v0.2.1      |
| 2     | Text capture, Inbox and PWA                        | 🚧 in progress |
| 3     | AI sorting                                         | ⏳             |
| 4     | Voice capture                                      | ⏳             |
| 5     | Projects and live context                          | ⏳             |
| 6     | Search and Ask (hybrid pgvector + full-text)       | ⏳             |
| 7     | Brain graph (3D)                                   | ⏳             |
| 8     | Open-source launch                                 | ⏳             |

See [CHANGELOG.md](CHANGELOG.md) for what each release contains.

## Stack

- **App:** Next.js 16 (App Router, Cache Components), React 19, TypeScript strict
- **UI:** Tailwind CSS v4, shadcn/ui, Geist, lucide icons
- **Data:** Supabase: Postgres with Row Level Security, pgvector, Auth, Storage
- **AI:** Vercel AI SDK, any provider via env
- **Quality:** zod everywhere, Vitest, RLS tests against a real local database

## Security model

- One person per instance. Public sign-up is disabled in Supabase Auth; only emails in `ALLOWED_EMAILS` can sign in.
- Row Level Security on every table, plus composite `(id, user_id)` foreign keys, so a row can never reference someone else's data.
- Voice notes live in a private bucket, readable only from the owner's folder.
- API keys and every model call stay on the server.

## Run it locally

You need Node 24, Docker and Corepack (ships with Node).

```bash
corepack enable          # provides the pinned pnpm version
pnpm install
cp .env.example .env.local
pnpm db:start            # local Supabase in Docker
pnpm db:reset            # migrations + seed
pnpm dev                 # http://localhost:3000
```

Sign in with the seeded local account: `dev@engram.local` / `engram-dev`.

### Scripts

| Command                                        | What it does                                                |
| ---------------------------------------------- | ----------------------------------------------------------- |
| `pnpm dev` / `pnpm build`                      | Run or build the app                                        |
| `pnpm lint` / `pnpm typecheck` / `pnpm format` | Code quality                                                |
| `pnpm test`                                    | Vitest: schemas, auth and RLS tests (needs the local stack) |
| `pnpm db:start` / `db:stop` / `db:reset`       | Local Supabase stack                                        |
| `pnpm db:push`                                 | Apply migrations to the linked cloud project                |
| `pnpm db:types`                                | Regenerate TypeScript types from the schema                 |

### Your own cloud instance

1. Create a Supabase project and link it: `pnpm supabase link --project-ref <ref>`.
2. Apply migrations: `pnpm db:push`.
3. In the dashboard, add your user under Authentication → Users (tick "Auto confirm").
4. Put the project URL, publishable key and your email (`ALLOWED_EMAILS`) in `.env.local`.

A one-command setup and a deploy guide come with the open-source launch (phase 8).

## Project structure

```text
src/
  app/            routes: (app)/capture, inbox, projects, ask, brain; (auth)/login
  components/     app shell and shadcn/ui
  features/       feature code (auth, capture, …)
  server/         Supabase clients, server-only env
  lib/            public env, utilities
supabase/         migrations, seed, local config
tests/            Vitest suites against the local stack
docs/             spec and progress log
```

## License

[MIT](LICENSE) © 2026 Mikhail Savushkin
