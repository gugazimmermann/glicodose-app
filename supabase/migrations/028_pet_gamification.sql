-- Pet fuel, achievements, and family view of the pet (not glucose).

alter table public.profiles
  add column if not exists gamification_mode text not null default 'off';

alter table public.profiles
  drop constraint if exists profiles_gamification_mode_check;

alter table public.profiles
  add constraint profiles_gamification_mode_check
  check (gamification_mode in ('off', 'pet', 'quiet'));

create table if not exists public.pet_progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  fuel_drops_today integer not null default 0,
  hours_in_range_today double precision not null default 0,
  mood text not null default 'sleeping',
  playful_line text not null default '',
  quiet_line text not null default '',
  suggestion text,
  lifetime_drops integer not null default 0,
  care_streak_days integer not null default 0,
  streak_paused boolean not null default false,
  streak_cursor date,
  unlocked_ids text[] not null default '{}',
  equipped_accessory text,
  fuel_day date,
  last_notice_on date,
  display_name text,
  updated_at timestamptz not null default now()
);

create table if not exists public.pet_family_links (
  viewer_id uuid not null references auth.users (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (viewer_id, owner_id),
  constraint pet_family_links_not_self check (viewer_id <> owner_id)
);

alter table public.pet_progress enable row level security;
alter table public.pet_family_links enable row level security;

drop policy if exists "Owners manage own pet progress" on public.pet_progress;
create policy "Owners manage own pet progress"
  on public.pet_progress for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Family can view linked pet progress" on public.pet_progress;
create policy "Family can view linked pet progress"
  on public.pet_progress for select
  using (
    exists (
      select 1
      from public.pet_family_links l
      where l.owner_id = pet_progress.user_id
        and l.viewer_id = auth.uid()
    )
  );

drop policy if exists "Participants can view pet links" on public.pet_family_links;
create policy "Participants can view pet links"
  on public.pet_family_links for select
  using (auth.uid() = viewer_id or auth.uid() = owner_id);

drop policy if exists "Participants can remove pet links" on public.pet_family_links;
create policy "Participants can remove pet links"
  on public.pet_family_links for delete
  using (auth.uid() = viewer_id or auth.uid() = owner_id);

create or replace function public.follow_family_pet(p_code text)
returns table (owner_id uuid, display_name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  normalized text;
  v_owner uuid;
  v_name text;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  normalized := upper(trim(p_code));
  if normalized is null or length(normalized) <> 6 or normalized !~ '^[A-Z0-9]{6}$' then
    raise exception 'invalid share code';
  end if;

  select p.id, p.full_name
  into v_owner, v_name
  from public.profiles p
  where p.share_code = normalized;

  if v_owner is null then
    raise exception 'profile not found';
  end if;

  if v_owner = uid then
    raise exception 'cannot follow yourself';
  end if;

  insert into public.pet_family_links (viewer_id, owner_id)
  values (uid, v_owner)
  on conflict (viewer_id, owner_id) do nothing;

  owner_id := v_owner;
  display_name := v_name;
  return next;
end;
$$;

revoke all on function public.follow_family_pet(text) from public;
grant execute on function public.follow_family_pet(text) to authenticated;

create or replace function public.restrict_doctor_profile_updates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is distinct from old.id then
    new.id := old.id;
    new.share_code := old.share_code;
    new.full_name := old.full_name;
    new.diabetes_type := old.diabetes_type;
    new.timezone := old.timezone;
    new.theme := old.theme;
    new.gamification_mode := old.gamification_mode;
    new.libre_alerts_enabled := old.libre_alerts_enabled;
    new.libre_alert_hypo_mgdl := old.libre_alert_hypo_mgdl;
    new.libre_alert_hyper_mgdl := old.libre_alert_hyper_mgdl;
    new.libre_alert_stale_minutes := old.libre_alert_stale_minutes;
    new.glucose_context_alerts_enabled := old.glucose_context_alerts_enabled;
    new.glucose_context_computed_at := old.glucose_context_computed_at;
    new.health_sync_enabled := old.health_sync_enabled;
    new.basal_reminder_enabled := old.basal_reminder_enabled;
    new.disclaimer_accepted_at := old.disclaimer_accepted_at;
    new.created_at := old.created_at;
    new.supporter_status := old.supporter_status;
    new.supporter_product_id := old.supporter_product_id;
    new.supporter_store := old.supporter_store;
    new.supporter_expires_at := old.supporter_expires_at;
    new.supporter_updated_at := old.supporter_updated_at;
  end if;
  return new;
end;
$$;
