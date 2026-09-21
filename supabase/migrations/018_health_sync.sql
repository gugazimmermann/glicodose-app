-- Health Connect / HealthKit sync metadata + glicemias update for upsert.

alter table public.profiles
  add column if not exists health_sync_enabled boolean not null default false;

alter table public.entries
  add column if not exists glucose_source text
    check (glucose_source is null or glucose_source in ('manual', 'health', 'libre'));

alter table public.entries
  add column if not exists health_glucose_uuid text;

alter table public.entries
  add column if not exists health_insulin_uuid text;

alter table public.entries
  add column if not exists health_meal_client_id text;

create unique index if not exists entries_user_health_glucose_uuid_uidx
  on public.entries (user_id, health_glucose_uuid)
  where health_glucose_uuid is not null;

-- Upsert into glicemias (onConflict user_id,external_id) needs UPDATE.
drop policy if exists "Users can update own glicemias" on public.glicemias;
create policy "Users can update own glicemias"
  on public.glicemias for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
