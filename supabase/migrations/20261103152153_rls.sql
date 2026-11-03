-- Row Level Security: every row is visible and writable only by its owner.
-- `(select auth.uid())` is evaluated once per statement instead of per row.

alter table public.projects enable row level security;
alter table public.captures enable row level security;
alter table public.entries enable row level security;
alter table public.entry_links enable row level security;

-- projects
create policy "Owners can read their projects" on public.projects
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Owners can create projects" on public.projects
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Owners can update their projects" on public.projects
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Owners can delete their projects" on public.projects
  for delete to authenticated using ((select auth.uid()) = user_id);

-- captures
create policy "Owners can read their captures" on public.captures
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Owners can create captures" on public.captures
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Owners can update their captures" on public.captures
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Owners can delete their captures" on public.captures
  for delete to authenticated using ((select auth.uid()) = user_id);

-- entries
create policy "Owners can read their entries" on public.entries
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Owners can create entries" on public.entries
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Owners can update their entries" on public.entries
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Owners can delete their entries" on public.entries
  for delete to authenticated using ((select auth.uid()) = user_id);

-- entry_links
create policy "Owners can read their links" on public.entry_links
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Owners can create links" on public.entry_links
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Owners can update their links" on public.entry_links
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Owners can delete their links" on public.entry_links
  for delete to authenticated using ((select auth.uid()) = user_id);
