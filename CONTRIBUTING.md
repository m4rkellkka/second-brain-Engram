# Contributing to Engram

Thanks for wanting to help. Engram is a small, local-first Mac app, so the bar is simple:
keep it fast, keep the user's data safe, and keep the code easy to read.

## Before you start

- **Bugs:** open an issue with the bug template; steps to reproduce and your macOS version
  help most.
- **Features:** open an issue with the idea template first, so we can agree on the shape
  before you spend time on code. The roadmap in the [README](README.md#roadmap) shows what is
  already planned.

## Set up

You need macOS 15 or later and Xcode 26 or later. No Apple Developer account is needed.

```bash
git clone https://github.com/m4rkellkka/second-brain-Engram.git
cd second-brain-Engram
make run
```

Debug builds take `-EngramDatabasePath <file>` (in Xcode: Product → Scheme → Edit Scheme →
Arguments), so you can try things without touching your own notes. `make demo-graph` opens
the graph on synthetic data.

## Where things live

- `Packages/EngramKit/Sources/EngramKit`: all logic: the schema and migrations, save and
  project-context rules, search, the journal, the graph layout, the Markdown export.
- `Packages/EngramKit/Sources/EngramMCP`: the tools Claude sees and their descriptions.
- `App/`: SwiftUI views. Views stay thin; anything that can break silently belongs in
  EngramKit, with a test.

## Rules of the road

- **Swift 6 strict concurrency.** No force unwraps (`!`) or `try!` outside tests, and no
  disabling warnings or lint rules to make something pass.
- **Schema changes only through a new GRDB migration.** Never edit a migration that has
  shipped; people already have databases built from it.
- **Validate every connector input in EngramKit** before it touches the database, and
  report problems back to Claude in plain words it can act on.
- **The user's words win.** Claude may add to project pages and the journal, but never
  overwrite what the user wrote by hand.
- **No network calls and no secrets.** Claude does all AI work through the connector.
- **Tests where bugs live:** migrations, save and context rules, search, input validation,
  the export. Use [Swift Testing](https://developer.apple.com/documentation/testing);
  there are no coverage targets and no tests for SwiftUI views.

## Before you open a pull request

```bash
make format   # swift format, ships with Xcode
make lint
make test
make build
```

All four must pass. Keep pull requests small and focused on one thing.

### Commits

Small [conventional commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`,
`test:`, `refactor:`, `chore:`, `ci:`, `style:`, with a scope where it helps
(`fix(journal): …`). The subject is imperative and at most 72 characters; the body says what
changed and why, wrapped at 72.

Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for anything a user would
notice. Versions follow [SemVer](https://semver.org); releases are cut by the maintainer.

## License

By contributing you agree that your work is released under the [MIT License](LICENSE).
