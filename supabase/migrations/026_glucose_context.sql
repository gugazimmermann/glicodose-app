-- Recurring CGM drop patterns (weekday + local hour) and opt-in push.

alter table public.profiles
  add column if not exists glucose_context_alerts_enabled boolean not null default false;

alter table public.profiles
  add column if not exists glucose_context_computed_at timestamptz;

create table if not exists public.glucose_context_patterns (
  user_id uuid not null references auth.users (id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  hour smallint not null check (hour between 0 and 23),
  median_mgdl integer not null,
  median_drop_mgdl integer not null,
  occurrences integer not null check (occurrences >= 3),
  drop_rate numeric(4, 3) not null check (drop_rate >= 0 and drop_rate <= 1),
  suggest_carbs_g integer check (suggest_carbs_g is null or suggest_carbs_g = 15),
  computed_at timestamptz not null default now(),
  primary key (user_id, weekday, hour)
);

alter table public.glucose_context_patterns enable row level security;

drop policy if exists "Users read own glucose context patterns"
  on public.glucose_context_patterns;
create policy "Users read own glucose context patterns"
  on public.glucose_context_patterns for select
  using (auth.uid() = user_id);

create table if not exists public.glucose_context_alert_state (
  user_id uuid not null references auth.users (id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  hour smallint not null check (hour between 0 and 23),
  last_notified_on date not null,
  primary key (user_id, weekday, hour)
);

alter table public.glucose_context_alert_state enable row level security;

-- Service role writes patterns and alert state (no user policies).

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
    -- Keep billing fields doctor-immutable
    new.supporter_status := old.supporter_status;
    new.supporter_product_id := old.supporter_product_id;
    new.supporter_store := old.supporter_store;
    new.supporter_expires_at := old.supporter_expires_at;
    new.supporter_updated_at := old.supporter_updated_at;
  end if;
  return new;
end;
$$;
