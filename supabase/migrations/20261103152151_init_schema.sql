-- Engram core schema: projects, captures, entries, entry_links.
-- A capture is what the user sent; it is split into entries, each filed
-- into a project and linked to similar entries.

create extension if not exists vector with schema extensions;

create type public.entry_kind as enum ('idea', 'task', 'note', 'link');
create type public.capture_source as enum ('text', 'voice');
create type public.processing_status as enum ('pending', 'processing', 'processed', 'failed');
create type public.link_kind as enum ('semantic', 'manual');

-- Keeps updated_at current on every UPDATE.
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  name text not null check (length(trim(name)) > 0),
  slug text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  color text not null check (color ~ '^#[0-9A-Fa-f]{6}$'),
  status text,
  context jsonb not null default '{}'::jsonb, -- { summary, stack[], decisions[], openIdeas[] }
  context_updated_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, slug),
  -- Target for composite foreign keys, so rows can only reference
  -- projects owned by the same user.
  unique (id, user_id)
);

create table public.captures (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  source public.capture_source not null,
  raw_text text,   -- typed text or transcript
  audio_path text, -- Storage path for voice notes
  status public.processing_status not null default 'pending',
  attempts int not null default 0 check (attempts >= 0),
  error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (id, user_id)
);

create table public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  capture_id uuid,
  project_id uuid,
  kind public.entry_kind not null,
  content text not null,
  url text,
  due_at timestamptz,
  done_at timestamptz,
  confidence real check (confidence between 0 and 1), -- AI confidence in kind + project
  needs_review boolean not null default false,
  embedding extensions.vector(1536), -- dimension fixed by the embedding model
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (capture_id, user_id)
    references public.captures (id, user_id) on delete cascade,
  -- Only project_id is cleared when the project is deleted; user_id stays.
  foreign key (project_id, user_id)
    references public.projects (id, user_id) on delete set null (project_id)
);

create trigger entries_set_updated_at
  before update on public.entries
  for each row execute function public.set_updated_at();

create table public.entry_links (
  user_id uuid not null references auth.users on delete cascade,
  source_id uuid not null,
  target_id uuid not null,
  kind public.link_kind not null,
  weight real,
  primary key (source_id, target_id),
  check (source_id <> target_id),
  foreign key (source_id, user_id)
    references public.entries (id, user_id) on delete cascade,
  foreign key (target_id, user_id)
    references public.entries (id, user_id) on delete cascade
);

-- Inbox feed.
create index entries_user_created_idx on public.entries (user_id, created_at desc);
create index entries_project_idx on public.entries (project_id);
create index entries_capture_idx on public.entries (capture_id);
-- Semantic search (pgvector, cosine distance).
create index entries_embedding_idx on public.entries
  using hnsw (embedding extensions.vector_cosine_ops);
-- Full-text search for hybrid Ask. 'simple' config: notes mix Russian and English.
create index entries_content_fts_idx on public.entries
  using gin (to_tsvector('simple', content));

create index captures_user_created_idx on public.captures (user_id, created_at desc);
-- Retry sweep only looks at unfinished captures.
create index captures_retry_idx on public.captures (created_at)
  where status in ('pending', 'failed');

create index entry_links_target_idx on public.entry_links (target_id);
create index entry_links_user_idx on public.entry_links (user_id);
