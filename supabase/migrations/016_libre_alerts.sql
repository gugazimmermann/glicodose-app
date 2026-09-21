-- Libre alert thresholds (patient-owned) + FCM device tokens + server debounce.

alter table public.profiles
  add column if not exists libre_alerts_enabled boolean not null default false;

alter table public.profiles
  add column if not exists libre_alert_hypo_mgdl integer not null default 70;

alter table public.profiles
  add column if not exists libre_alert_hyper_mgdl integer not null default 180;

alter table public.profiles
  add column if not exists libre_alert_stale_minutes integer not null default 20;

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "Users manage own device tokens" on public.device_tokens;
create policy "Users manage own device tokens"
  on public.device_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.libre_alert_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  zone text not null default 'ok' check (zone in ('ok', 'hypo', 'hyper')),
  last_pushed_at timestamptz,
  last_stale_pushed_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.libre_alert_state enable row level security;

-- Only service role writes alert state (no user policies).

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
    new.dose_step := old.dose_step;
    new.insulin_duration_hours := old.insulin_duration_hours;
    new.night_start_minute := old.night_start_minute;
    new.night_end_minute := old.night_end_minute;
    new.timezone := old.timezone;
    new.theme := old.theme;
    new.libre_alerts_enabled := old.libre_alerts_enabled;
    new.libre_alert_hypo_mgdl := old.libre_alert_hypo_mgdl;
    new.libre_alert_hyper_mgdl := old.libre_alert_hyper_mgdl;
    new.libre_alert_stale_minutes := old.libre_alert_stale_minutes;
    new.disclaimer_accepted_at := old.disclaimer_accepted_at;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;
