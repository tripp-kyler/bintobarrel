-- Bin to Bottle: Supabase setup
-- Paste this whole file into Supabase → SQL Editor → New query, then click Run.
-- Safe to run more than once.

-- 1. Tables -------------------------------------------------------------
create table if not exists public.orgs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists public.org_members (
  org_id      uuid not null references public.orgs(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        text not null default 'member' check (role in ('owner','admin','member')),
  created_at  timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index if not exists org_members_user_idx on public.org_members(user_id);

-- The whole ciderhouse record (bins, runs, lots, orders...) lives in one JSON document per org.
create table if not exists public.app_state (
  org_id      uuid primary key references public.orgs(id) on delete cascade,
  data        jsonb not null default '{}'::jsonb,
  version     bigint not null default 0,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id) on delete set null
);

-- Hourly snapshots, kept 30 days, for recovering from mistakes.
create table if not exists public.app_state_history (
  id        bigserial primary key,
  org_id    uuid not null references public.orgs(id) on delete cascade,
  version   bigint not null,
  data      jsonb not null,
  saved_at  timestamptz not null default now(),
  saved_by  uuid references auth.users(id) on delete set null
);
create index if not exists app_state_history_org_idx on public.app_state_history(org_id, saved_at desc);

-- 2. Helpers --------------------------------------------------------------
create or replace function public.is_member(p_org uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.org_members where org_id = p_org and user_id = auth.uid());
$$;

-- First sign-in: create the ciderhouse and make the caller its owner.
create or replace function public.create_org(p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if exists (select 1 from public.org_members where user_id = auth.uid()) then
    raise exception 'This account already belongs to a ciderhouse';
  end if;
  insert into public.orgs (name, created_by)
    values (coalesce(nullif(trim(p_name), ''), 'My ciderhouse'), auth.uid()) returning id into v_org;
  insert into public.org_members (org_id, user_id, role) values (v_org, auth.uid(), 'owner');
  insert into public.app_state (org_id) values (v_org);
  return v_org;
end $$;

-- Save with a version check. Returns the new version, or -1 if someone else saved first
-- (the app then merges their changes with yours and saves again).
create or replace function public.save_state(p_org uuid, p_data jsonb, p_version bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_new bigint; v_last timestamptz;
begin
  if not public.is_member(p_org) then raise exception 'Not a member of this ciderhouse'; end if;
  update public.app_state
     set data = p_data, version = version + 1, updated_at = now(), updated_by = auth.uid()
   where org_id = p_org and version = p_version
   returning version into v_new;
  if v_new is null then return -1; end if;
  select max(saved_at) into v_last from public.app_state_history where org_id = p_org;
  if v_last is null or v_last < now() - interval '1 hour' then
    insert into public.app_state_history (org_id, version, data, saved_by) values (p_org, v_new, p_data, auth.uid());
    delete from public.app_state_history where org_id = p_org and saved_at < now() - interval '30 days';
  end if;
  return v_new;
end $$;

-- Used only by the "members" edge function (server side) to find an account by email.
create or replace function public.uid_by_email(p_email text)
returns uuid language sql stable security definer set search_path = public, auth as $$
  select id from auth.users where lower(email) = lower(trim(p_email)) limit 1;
$$;

revoke all on function public.is_member(uuid) from public, anon;
revoke all on function public.create_org(text) from public, anon;
revoke all on function public.save_state(uuid, jsonb, bigint) from public, anon;
revoke all on function public.uid_by_email(text) from public, anon, authenticated;
grant execute on function public.is_member(uuid) to authenticated;
grant execute on function public.create_org(text) to authenticated;
grant execute on function public.save_state(uuid, jsonb, bigint) to authenticated;
grant execute on function public.uid_by_email(text) to service_role;

-- 3. Row level security: people only see their own ciderhouse -------------
alter table public.orgs enable row level security;
alter table public.org_members enable row level security;
alter table public.app_state enable row level security;
alter table public.app_state_history enable row level security;

drop policy if exists "members read org" on public.orgs;
create policy "members read org" on public.orgs for select to authenticated using (public.is_member(id));

drop policy if exists "members read members" on public.org_members;
create policy "members read members" on public.org_members for select to authenticated
  using (user_id = auth.uid() or public.is_member(org_id));

drop policy if exists "members read state" on public.app_state;
create policy "members read state" on public.app_state for select to authenticated using (public.is_member(org_id));
-- No insert/update/delete policies: all writes go through create_org / save_state / the members function.
-- app_state_history has no policies at all: read it from the SQL editor when you need to restore.

-- 4. Photo storage ---------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 20971520, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;

drop policy if exists "b2b members read photos" on storage.objects;
create policy "b2b members read photos" on storage.objects for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] in
         (select org_id::text from public.org_members where user_id = auth.uid()));

drop policy if exists "b2b members add photos" on storage.objects;
create policy "b2b members add photos" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] in
         (select org_id::text from public.org_members where user_id = auth.uid()));

drop policy if exists "b2b members delete photos" on storage.objects;
create policy "b2b members delete photos" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] in
         (select org_id::text from public.org_members where user_id = auth.uid()));
