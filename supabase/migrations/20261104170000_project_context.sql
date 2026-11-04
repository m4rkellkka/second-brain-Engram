-- Phase 5: live project context as rows instead of one JSON blob, so two
-- captures about the same project never overwrite each other, every item
-- knows who wrote it, and hand edits win over the AI.

alter table public.projects
  add column summary text check (summary is null or length(summary) <= 2000),
  add column summary_source text not null default 'ai' check (summary_source in ('ai', 'user')),
  add column summary_entry_ids uuid[] not null default '{}',
  add column status_source text not null default 'ai' check (status_source in ('ai', 'user')),
  add constraint projects_status_length check (status is null or length(status) <= 60);

create table public.project_context_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  project_id uuid not null,
  section text not null check (section in ('stack', 'decision', 'idea')),
  text text not null check (length(btrim(text)) between 1 and 500),
  source text not null check (source in ('ai', 'user')),
  entry_ids uuid[] not null default '{}', -- entries this item came from
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, user_id)
    references public.projects (id, user_id) on delete cascade
);
-- Same text twice in one section is a duplicate, whoever wrote it.
create unique index project_context_items_unique_text
  on public.project_context_items (project_id, section, lower(btrim(text)));
create index project_context_items_user_idx on public.project_context_items (user_id);

create trigger project_context_items_set_updated_at
  before update on public.project_context_items
  for each row execute function public.set_updated_at();

alter table public.project_context_items enable row level security;
create policy "Owners can read their context items" on public.project_context_items
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Owners can create context items" on public.project_context_items
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Owners can update their context items" on public.project_context_items
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Owners can delete their context items" on public.project_context_items
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Move the old JSON context over, then drop it.
update public.projects
set summary = nullif(btrim(context->>'summary'), '')
where context ? 'summary';

insert into public.project_context_items (user_id, project_id, section, text, source)
select p.user_id, p.id, s.section, btrim(v.value), 'ai'
from public.projects p
cross join (values ('stack', 'stack'), ('decision', 'decisions'), ('idea', 'openIdeas')) as s(section, key)
cross join lateral jsonb_array_elements_text(
  case when jsonb_typeof(p.context->s.key) = 'array' then p.context->s.key else '[]'::jsonb end
) as v(value)
where length(btrim(v.value)) between 1 and 500
on conflict do nothing;

alter table public.projects drop column context;

-- Applies an AI patch to a project's context, atomically. A summary or
-- status the user wrote by hand is never replaced; list items are only
-- added, and duplicates are skipped.
create function public.apply_context_patch(
  project_id uuid,
  new_summary text default null,
  new_status text default null,
  items jsonb default '[]',
  entry_ids uuid[] default '{}'
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target public.projects;
begin
  select * into target from public.projects p where p.id = project_id for update;
  if not found then
    raise exception 'project not found' using errcode = 'P0002';
  end if;

  update public.projects p
  set
    summary = case
      when new_summary is not null and p.summary_source = 'ai' then left(btrim(new_summary), 2000)
      else p.summary end,
    summary_entry_ids = case
      when new_summary is not null and p.summary_source = 'ai' then entry_ids
      else p.summary_entry_ids end,
    status = case
      when new_status is not null and p.status_source = 'ai' then left(btrim(new_status), 60)
      else p.status end,
    context_updated_at = now()
  where p.id = target.id;

  insert into public.project_context_items (user_id, project_id, section, text, source, entry_ids)
  select target.user_id, target.id, i.section, btrim(i.text), 'ai', coalesce(i.entry_ids, '{}')
  from jsonb_to_recordset(items) as i(section text, text text, entry_ids uuid[])
  where length(btrim(i.text)) between 1 and 500
  on conflict do nothing;
end;
$$;

revoke execute on function public.apply_context_patch(uuid, text, text, jsonb, uuid[]) from public, anon;
grant execute on function public.apply_context_patch(uuid, text, text, jsonb, uuid[]) to authenticated, service_role;

alter table public.ai_calls drop constraint ai_calls_step_check;
alter table public.ai_calls add constraint ai_calls_step_check check (step in ('sort', 'context'));
