-- Basal insulin: profile defaults/reminders + separate dose log (never mixes with rapid IOB).

alter table public.profiles
  add column if not exists basal_insulin_name text;

alter table public.profiles
  add column if not exists basal_dose_u numeric;

alter table public.profiles
  add column if not exists basal_times_minutes integer[] not null default '{}';

alter table public.profiles
  add column if not exists basal_reminder_enabled boolean not null default false;

create table if not exists public.basal_doses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  recorded_at timestamptz not null default now(),
  units numeric not null check (units > 0),
  insulin_name text,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists basal_doses_user_recorded_idx
  on public.basal_doses (user_id, recorded_at desc);

alter table public.basal_doses enable row level security;

drop policy if exists "Users manage own basal doses" on public.basal_doses;
create policy "Users manage own basal doses"
  on public.basal_doses for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

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
    new.basal_insulin_name := old.basal_insulin_name;
    new.basal_dose_u := old.basal_dose_u;
    new.basal_times_minutes := old.basal_times_minutes;
    new.basal_reminder_enabled := old.basal_reminder_enabled;
    new.disclaimer_accepted_at := old.disclaimer_accepted_at;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;
