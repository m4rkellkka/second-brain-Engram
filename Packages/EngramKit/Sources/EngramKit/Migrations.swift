import GRDB

extension AppDatabase {
  /// Schema migrations. Never edit a migration that has shipped; add a new one.
  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()

    migrator.registerMigration("v1") { db in
      try db.execute(
        sql: """
          create table projects (
            id text primary key,
            name text not null,
            slug text not null unique,
            color text not null,
            status text,
            summary text,
            summary_source text not null default 'ai' check (summary_source in ('ai', 'user')),
            status_source text not null default 'ai' check (status_source in ('ai', 'user')),
            context_updated_at text,
            archived_at text,
            created_at text not null
          );

          create table captures (
            id text primary key,
            source text not null check (source in ('typed', 'claude')),
            raw_text text not null,
            conversation_ref text,
            content_hash text not null,
            status text not null check (status in ('unsorted', 'sorted')),
            time_zone text not null,
            created_at text not null,
            sorted_at text
          );

          create table entries (
            id text primary key,
            capture_id text references captures (id) on delete cascade,
            project_id text references projects (id) on delete set null,
            kind text not null check (kind in ('idea', 'task', 'note', 'link')),
            content text not null,
            keywords text,
            url text,
            due_at text,
            done_at text,
            confidence real check (confidence between 0 and 1),
            needs_review integer not null default 0 check (needs_review in (0, 1)),
            created_at text not null,
            updated_at text not null
          );

          create table project_context_items (
            id text primary key,
            project_id text not null references projects (id) on delete cascade,
            section text not null check (section in ('stack', 'decision', 'idea')),
            text text not null,
            source text not null check (source in ('ai', 'user')),
            entry_ids text not null default '[]',
            created_at text not null
          );

          create table entry_links (
            source_id text not null references entries (id) on delete cascade,
            target_id text not null references entries (id) on delete cascade,
            weight real not null,
            primary key (source_id, target_id)
          );

          create table entry_corrections (
            id text primary key,
            entry_id text not null references entries (id) on delete cascade,
            field text not null,
            old_value text,
            new_value text,
            created_at text not null
          );

          create index entries_created_at on entries (created_at desc);
          create index entries_project_id on entries (project_id);
          create index entries_capture_id on entries (capture_id);
          create index captures_status on captures (status);
          -- Only summaries from Claude are deduplicated; typing the same
          -- thought twice is fine.
          create unique index captures_claude_hash on captures (content_hash)
            where source = 'claude';
          create unique index project_context_items_unique
            on project_context_items (project_id, section, lower(text));
          create index entry_links_target on entry_links (target_id);
          create index entry_corrections_entry on entry_corrections (entry_id);
          """)

      // Full-text index kept in sync with `entries` by triggers.
      try db.create(virtualTable: "entries_fts", using: FTS5()) { t in
        t.synchronize(withTable: "entries")
        t.tokenizer = .unicode61(diacritics: .remove)
        t.column("content")
        t.column("keywords")
      }
    }

    return migrator
  }
}
