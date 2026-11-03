-- Private bucket for voice notes, stored at `{user_id}/{capture_id}.<ext>`.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('audio', 'audio', false, 26214400, array['audio/*']); -- 25 MB

-- The first path segment must be the owner's user id.
create policy "Owners can read their audio" on storage.objects
  for select to authenticated
  using (bucket_id = 'audio' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Owners can upload their audio" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'audio' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Owners can update their audio" on storage.objects
  for update to authenticated
  using (bucket_id = 'audio' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'audio' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Owners can delete their audio" on storage.objects
  for delete to authenticated
  using (bucket_id = 'audio' and (storage.foldername(name))[1] = (select auth.uid())::text);
