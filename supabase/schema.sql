-- ============================================================
-- Lock-In social backend — Postgres schema for Supabase
-- Paste this whole file into the Supabase SQL Editor and Run.
-- Safe to re-run (uses IF NOT EXISTS / OR REPLACE).
-- ============================================================

-- ---------- PROFILES ----------
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  username       text unique not null,
  display_name   text,
  current_streak int  not null default 0,   -- snapshot, updated by client on sync
  perfect_days   int  not null default 0,   -- lifetime count of all-goals-met days
  last_active    date,
  created_at     timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- ---------- FRIENDSHIPS (requests + accepted) ----------
create table if not exists public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending','accepted')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
alter table public.friendships enable row level security;

-- Helper: are two users accepted friends? (security definer so it can read all friendship rows)
create or replace function public.is_friend(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = a and f.addressee_id = b)
        or (f.requester_id = b and f.addressee_id = a))
  );
$$;

-- ---------- DAILY STATS (per user per day; powers leaderboard + friend view) ----------
create table if not exists public.daily_stats (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  day          date not null,
  water        int  not null default 0,
  water_goal   int  not null default 6,
  calories     int  not null default 0,
  calorie_goal int  not null default 3000,
  workouts     int  not null default 0,
  creatine     boolean not null default false,
  score        int  not null default 0,      -- 0..3 core goals hit that day
  updated_at   timestamptz not null default now(),
  unique (user_id, day)
);
alter table public.daily_stats enable row level security;

-- ---------- ACTIVITIES (feed items) ----------
create table if not exists public.activities (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('workout','meal','creatine','water_goal','perfect_day')),
  title      text not null,      -- e.g. "Upper Body" or "Chicken & rice"
  detail     text,               -- e.g. "7 exercises · felt strong" or "820 cal"
  day        date not null default current_date,
  created_at timestamptz not null default now()
);
alter table public.activities enable row level security;
create index if not exists activities_user_created_idx on public.activities(user_id, created_at desc);

-- ---------- REACTIONS (preset "comments" on activities) ----------
create table if not exists public.reactions (
  id          uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  preset      text not null,     -- canned reaction key: 'damn','work_on_it','clean'
  created_at  timestamptz not null default now(),
  unique (activity_id, user_id, preset)
);
alter table public.reactions enable row level security;

-- ============================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================

-- PROFILES: any signed-in user can read basic profiles (needed to search/add friends
-- and show names on the leaderboard — no health data lives here). Only you edit yours.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated using (true);
drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
  for insert to authenticated with check (id = auth.uid());
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated using (id = auth.uid());

-- FRIENDSHIPS: only the two people involved can see/act on the row.
drop policy if exists friendships_read on public.friendships;
create policy friendships_read on public.friendships
  for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());
drop policy if exists friendships_insert on public.friendships;
create policy friendships_insert on public.friendships
  for insert to authenticated with check (requester_id = auth.uid());
drop policy if exists friendships_update on public.friendships;
create policy friendships_update on public.friendships
  for update to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());
drop policy if exists friendships_delete on public.friendships;
create policy friendships_delete on public.friendships
  for delete to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- DAILY_STATS: you fully control yours; accepted friends may read.
drop policy if exists daily_stats_owner on public.daily_stats;
create policy daily_stats_owner on public.daily_stats
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists daily_stats_friends_read on public.daily_stats;
create policy daily_stats_friends_read on public.daily_stats
  for select to authenticated
  using (public.is_friend(auth.uid(), user_id));

-- ACTIVITIES: you fully control yours; accepted friends may read.
drop policy if exists activities_owner on public.activities;
create policy activities_owner on public.activities
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists activities_friends_read on public.activities;
create policy activities_friends_read on public.activities
  for select to authenticated
  using (public.is_friend(auth.uid(), user_id));

-- REACTIONS: visible to anyone who can see the underlying activity; you add/remove your own.
drop policy if exists reactions_read on public.reactions;
create policy reactions_read on public.reactions
  for select to authenticated
  using (exists (
    select 1 from public.activities a
    where a.id = activity_id
      and (a.user_id = auth.uid() or public.is_friend(auth.uid(), a.user_id))
  ));
drop policy if exists reactions_insert on public.reactions;
create policy reactions_insert on public.reactions
  for insert to authenticated
  with check (user_id = auth.uid() and exists (
    select 1 from public.activities a
    where a.id = activity_id
      and (a.user_id = auth.uid() or public.is_friend(auth.uid(), a.user_id))
  ));
drop policy if exists reactions_delete on public.reactions;
create policy reactions_delete on public.reactions
  for delete to authenticated using (user_id = auth.uid());

-- ============================================================
-- AUTO-CREATE A PROFILE WHEN SOMEONE SIGNS UP
-- ============================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)),
    new.raw_user_meta_data->>'display_name'
  )
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- SELF-SERVE ACCOUNT DELETION (Apple App Store requirement)
-- ============================================================
create or replace function public.delete_own_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
