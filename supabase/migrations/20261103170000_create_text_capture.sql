-- Saves a typed thought as one capture plus one `note` entry, atomically.
-- Runs as the caller (security invoker), so RLS applies to both inserts.
-- Phase 3 will switch new captures to `pending` for AI sorting.
create function public.create_text_capture(content text)
returns public.entries
language plpgsql
security invoker
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  clean text := btrim(content);
  new_capture_id uuid;
  new_entry public.entries;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if clean is null or clean = '' or length(clean) > 10000 then
    raise exception 'content must be 1 to 10000 characters' using errcode = '22023';
  end if;

  insert into public.captures (user_id, source, raw_text, status, processed_at)
  values (uid, 'text', clean, 'processed', now())
  returning id into new_capture_id;

  insert into public.entries (user_id, capture_id, kind, content)
  values (uid, new_capture_id, 'note', clean)
  returning * into new_entry;

  return new_entry;
end;
$$;

revoke execute on function public.create_text_capture(text) from public, anon;
grant execute on function public.create_text_capture(text) to authenticated;
