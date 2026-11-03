-- Cover the composite (id, user_id) foreign keys with matching indexes,
-- replacing the single-column ones they make redundant.
drop index public.entries_capture_idx;
drop index public.entries_project_idx;
drop index public.entry_links_target_idx;

create index entries_capture_user_idx on public.entries (capture_id, user_id);
create index entries_project_user_idx on public.entries (project_id, user_id);
create index entry_links_source_user_idx on public.entry_links (source_id, user_id);
create index entry_links_target_user_idx on public.entry_links (target_id, user_id);
