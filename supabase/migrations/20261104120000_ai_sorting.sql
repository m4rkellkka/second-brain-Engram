-- Phase 3: captures are sorted by an LLM after they are saved.
-- All functions run as the caller (security invoker), so RLS applies.

alter table public.captures
  add column timezone text check (timezone is null or length(timezone) between 1 and 64),
  add column claimed_at timestamptz;

-- A project the AI proposed but did not create; shown on the review card.
alter table public.entries
  add column suggested_project_name text
    check (suggested_project_name is null or length(btrim(suggested_project_name)) between 1 and 60);

create index entries_needs_review_idx on public.entries (user_id) where needs_review;

-- Saving no longer creates the entry: the pipeline does, after sorting.
drop function public.create_text_capture(text);

create function public.create_text_capture(content text, timezone text default null)
returns public.captures
language plpgsql
security invoker
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  clean text := btrim(content);
  new_capture public.captures;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if clean is null or clean = '' or length(clean) > 10000 then
    raise exception 'content must be 1 to 10000 characters' using errcode = '22023';
  end if;

  insert into public.captures (user_id, source, raw_text, status, timezone)
  values (uid, 'text', clean, 'pending', nullif(btrim(timezone), ''))
  returning * into new_capture;

  return new_capture;
end;
$$;

-- Takes a capture for processing. Returns nothing if it is already being
-- processed (claimed less than 5 minutes ago), done, or out of attempts.
create function public.claim_capture(capture_id uuid, max_attempts int default 3)
returns public.captures
language sql
security invoker
set search_path = ''
as $$
  update public.captures
  set status = 'processing', attempts = attempts + 1, claimed_at = now(), error = null
  where id = capture_id
    and attempts < max_attempts
    and (
      status in ('pending', 'failed')
      or (status = 'processing' and claimed_at < now() - interval '5 minutes')
    )
  returning *;
$$;

-- Writes the sorted entries and marks the capture processed, atomically.
-- `rows` is a JSON array of entry fields; project ids are checked by the
-- composite foreign key, so only the caller's projects can be used.
create function public.apply_sorted_capture(capture_id uuid, rows jsonb)
returns setof public.entries
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target public.captures;
begin
  select * into target from public.captures c
  where c.id = capture_id and c.status = 'processing'
  for update;
  if not found then
    raise exception 'capture is not being processed' using errcode = '55000';
  end if;

  return query
  insert into public.entries (
    user_id, capture_id, project_id, kind, content, url, due_at,
    confidence, needs_review, suggested_project_name
  )
  select
    target.user_id, target.id, r.project_id, r.kind, r.content, r.url, r.due_at,
    r.confidence, r.needs_review, r.suggested_project_name
  from jsonb_to_recordset(rows) as r(
    project_id uuid, kind public.entry_kind, content text, url text,
    due_at timestamptz, confidence real, needs_review boolean,
    suggested_project_name text
  )
  returning *;

  update public.captures
  set status = 'processed', processed_at = now(), error = null
  where id = target.id;
end;
$$;

-- Records a failed attempt. On the last attempt the raw text is kept as a
-- plain note to review, so nothing typed is ever lost.
create function public.fail_capture(capture_id uuid, message text, max_attempts int default 3)
returns public.captures
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target public.captures;
begin
  update public.captures
  set status = 'failed', error = left(message, 1000)
  where id = capture_id and status = 'processing'
  returning * into target;

  if found and target.attempts >= max_attempts and target.raw_text is not null then
    insert into public.entries (user_id, capture_id, kind, content, needs_review)
    values (target.user_id, target.id, 'note', target.raw_text, true);
  end if;

  return target;
end;
$$;

revoke execute on function public.create_text_capture(text, text) from public, anon;
revoke execute on function public.claim_capture(uuid, int) from public, anon;
revoke execute on function public.apply_sorted_capture(uuid, jsonb) from public, anon;
revoke execute on function public.fail_capture(uuid, text, int) from public, anon;
grant execute on function public.create_text_capture(text, text) to authenticated, service_role;
grant execute on function public.claim_capture(uuid, int) to authenticated, service_role;
grant execute on function public.apply_sorted_capture(uuid, jsonb) to authenticated, service_role;
grant execute on function public.fail_capture(uuid, text, int) to authenticated, service_role;

-- One row per model call, so cost per capture is known.
create table public.ai_calls (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  capture_id uuid,
  step text not null check (step in ('sort')),
  model text not null,
  input_tokens int not null default 0 check (input_tokens >= 0),
  output_tokens int not null default 0 check (output_tokens >= 0),
  cache_read_tokens int not null default 0 check (cache_read_tokens >= 0),
  cost_usd numeric(12, 6) not null default 0 check (cost_usd >= 0),
  duration_ms int not null check (duration_ms >= 0),
  ok boolean not null,
  created_at timestamptz not null default now(),
  foreign key (capture_id, user_id)
    references public.captures (id, user_id) on delete set null (capture_id)
);
create index ai_calls_user_created_idx on public.ai_calls (user_id, created_at desc);
create index ai_calls_capture_idx on public.ai_calls (capture_id);

-- Manual fixes of AI sorting; later usable as few-shot examples.
create table public.entry_corrections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  entry_id uuid not null,
  field text not null check (field in ('project', 'kind', 'confirm')),
  from_value text,
  to_value text,
  created_at timestamptz not null default now(),
  foreign key (entry_id, user_id)
    references public.entries (id, user_id) on delete cascade
);
create index entry_corrections_entry_idx on public.entry_corrections (entry_id);
create index entry_corrections_user_idx on public.entry_corrections (user_id, created_at desc);

alter table public.ai_calls enable row level security;
alter table public.entry_corrections enable row level security;

create policy "Owners can read their AI calls" on public.ai_calls
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Owners can log their AI calls" on public.ai_calls
  for insert to authenticated with check ((select auth.uid()) = user_id);

create policy "Owners can read their corrections" on public.entry_corrections
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Owners can record corrections" on public.entry_corrections
  for insert to authenticated with check ((select auth.uid()) = user_id);
