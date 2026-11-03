-- Local development seed. Applied by `supabase db reset`; never pushed to the cloud.
-- Sign in locally as dev@engram.local with the password `engram-dev`.
-- This account exists only in the local Docker stack.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'dev@engram.local',
  extensions.crypt('engram-dev', extensions.gen_salt('bf')), now(),
  '{"provider": "email", "providers": ["email"]}', '{}', now(), now(),
  '', '', '', ''
);

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
) values (
  gen_random_uuid(),
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000001',
  '{"sub": "00000000-0000-4000-8000-000000000001", "email": "dev@engram.local", "email_verified": true}',
  'email', now(), now(), now()
);

insert into public.projects (user_id, name, slug, color, status, context) values
(
  '00000000-0000-4000-8000-000000000001',
  'Tamam', 'tamam', '#3FD0B6', 'pilot',
  '{
    "summary": "Requests and approvals app for an operations team, running as a pilot.",
    "stack": ["Next.js", "Supabase"],
    "decisions": [],
    "openIdeas": []
  }'
),
(
  '00000000-0000-4000-8000-000000000001',
  'Engram', 'engram', '#B79CFF', 'building',
  '{
    "summary": "Self-hosted second brain: capture by voice or text, AI files it into projects.",
    "stack": ["Next.js", "Supabase", "pgvector", "Vercel AI SDK"],
    "decisions": [],
    "openIdeas": []
  }'
);
