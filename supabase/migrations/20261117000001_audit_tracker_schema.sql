-- Audit Tracker schema
-- Passwords live only in Supabase Auth (auth.users). public.profiles holds the app-level
-- user record (username, display name, role, active flag) and is linked 1:1 to auth.users.

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                   uuid primary key references auth.users (id) on delete cascade,
  username             text not null unique check (username ~ '^[a-z0-9][a-z0-9._-]{1,31}$'),
  display_name         text not null default '',
  role                 text not null default 'auditor' check (role in ('admin', 'auditor')),
  active               boolean not null default false,
  must_change_password boolean not null default true,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
comment on table public.profiles is 'App user records, one per auth.users row. Role/active are changed only by the admin-users edge function (service role).';

-- Helper checks used by RLS policies (security definer so they can read profiles regardless of RLS)
create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.active);
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.active and p.role = 'admin');
$$;

-- Create a profile for every new auth user. Only users created by an administrator
-- (role set in app_metadata, which end users cannot write) are active; self sign-ups get
-- an inactive profile and therefore no data access.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_username text := lower(coalesce(new.raw_app_meta_data ->> 'username', split_part(new.email, '@', 1)));
  v_role     text := new.raw_app_meta_data ->> 'role';
begin
  insert into public.profiles (id, username, display_name, role, active, must_change_password)
  values (
    new.id,
    v_username,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), v_username),
    case when v_role in ('admin', 'auditor') then v_role else 'auditor' end,
    coalesce(v_role in ('admin', 'auditor'), false),
    true
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Engagements, workbooks, issues (shared by all active users)
-- ---------------------------------------------------------------------------
create table public.engagements (
  id          uuid primary key default gen_random_uuid(),
  name        text not null default 'Untitled engagement',
  settings    jsonb not null default '{}'::jsonb,
  issue_seq   integer not null default 0,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_by  uuid,
  updated_at  timestamptz not null default now()
);

create table public.workbooks (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements (id) on delete cascade,
  name          text not null,
  sheets        jsonb not null default '[]'::jsonb,
  uploaded_by   uuid default auth.uid(),
  uploaded_at   timestamptz not null default now()
);
create index workbooks_engagement_id_idx on public.workbooks (engagement_id);

create table public.issues (
  id                uuid primary key default gen_random_uuid(),
  engagement_id     uuid not null references public.engagements (id) on delete cascade,
  ref               text not null,
  workbook_id       uuid references public.workbooks (id) on delete cascade,
  dedupe_key        text,
  test              text,
  source            text not null default 'manual' check (source in ('auto', 'manual')),
  title             text not null,
  description       text not null default '',
  amount            numeric(18, 2) not null default 0,
  likelihood        smallint not null default 3 check (likelihood between 1 and 5),
  category          text not null,
  assertion         text,
  ssa_refs          text[] not null default '{}',
  sfrs_refs         text[] not null default '{}',
  status            text not null default 'Open' check (status in ('Open', 'In review', 'Resolved')),
  owner             text not null default '',
  notes             text not null default '',
  priority_override text check (priority_override in ('P1', 'P2', 'P3', 'P4')),
  level_override    text check (level_override in ('Significant', 'High', 'Medium', 'Low')),
  location          jsonb,
  created_by        uuid default auth.uid(),
  created_at        timestamptz not null default now(),
  updated_by        uuid,
  updated_at        timestamptz not null default now(),
  unique (engagement_id, ref)
);
create index issues_workbook_id_idx on public.issues (workbook_id);

-- updated_at / updated_by bookkeeping
create or replace function public.touch_row()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  new.updated_by := (select auth.uid());
  return new;
end;
$$;
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger engagements_touch before update on public.engagements for each row execute function public.touch_row();
create trigger issues_touch      before update on public.issues      for each row execute function public.touch_row();
create trigger profiles_touch    before update on public.profiles    for each row execute function public.touch_updated_at();

-- Atomically reserve a block of issue reference numbers (AT-001, AT-002, …) for an engagement
create or replace function public.reserve_issue_refs(p_engagement uuid, p_count integer)
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_start integer;
begin
  if p_count is null or p_count < 1 or p_count > 5000 then
    raise exception 'p_count must be between 1 and 5000';
  end if;
  update public.engagements
     set issue_seq = issue_seq + p_count
   where id = p_engagement
  returning issue_seq - p_count + 1 into v_start;
  if v_start is null then
    raise exception 'Engagement not found or not accessible';
  end if;
  return v_start;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.engagements enable row level security;
alter table public.workbooks   enable row level security;
alter table public.issues      enable row level security;

revoke all on public.profiles, public.engagements, public.workbooks, public.issues from anon;

-- profiles: everyone active can see the team list; users can edit only their own display name / password flag
create policy "Profiles are visible to self and active users" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_active_user()));
create policy "Users can update their own profile" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
revoke insert, update, delete on public.profiles from authenticated;
grant update (display_name, must_change_password) on public.profiles to authenticated;

-- engagements
create policy "Active users can read engagements" on public.engagements
  for select to authenticated using ((select public.is_active_user()));
create policy "Active users can create engagements" on public.engagements
  for insert to authenticated with check ((select public.is_active_user()));
create policy "Active users can update engagements" on public.engagements
  for update to authenticated using ((select public.is_active_user())) with check ((select public.is_active_user()));
create policy "Admins can delete engagements" on public.engagements
  for delete to authenticated using ((select public.is_admin()));

-- workbooks
create policy "Active users can read workbooks" on public.workbooks
  for select to authenticated using ((select public.is_active_user()));
create policy "Active users can add workbooks" on public.workbooks
  for insert to authenticated with check ((select public.is_active_user()));
create policy "Active users can update workbooks" on public.workbooks
  for update to authenticated using ((select public.is_active_user())) with check ((select public.is_active_user()));
create policy "Active users can delete workbooks" on public.workbooks
  for delete to authenticated using ((select public.is_active_user()));

-- issues
create policy "Active users can read issues" on public.issues
  for select to authenticated using ((select public.is_active_user()));
create policy "Active users can add issues" on public.issues
  for insert to authenticated with check ((select public.is_active_user()));
create policy "Active users can update issues" on public.issues
  for update to authenticated using ((select public.is_active_user())) with check ((select public.is_active_user()));
create policy "Active users can delete issues" on public.issues
  for delete to authenticated using ((select public.is_active_user()));

-- Function privileges
revoke execute on function public.handle_new_user()                      from public, anon, authenticated;
revoke execute on function public.touch_row()                            from public, anon, authenticated;
revoke execute on function public.touch_updated_at()                     from public, anon, authenticated;
revoke execute on function public.is_active_user()                       from public, anon;
revoke execute on function public.is_admin()                             from public, anon;
revoke execute on function public.reserve_issue_refs(uuid, integer)      from public, anon;
grant  execute on function public.is_active_user()                       to authenticated;
grant  execute on function public.is_admin()                             to authenticated;
grant  execute on function public.reserve_issue_refs(uuid, integer)      to authenticated;
