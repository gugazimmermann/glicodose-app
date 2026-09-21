-- LibreLinkUp CGM credentials + glucose time-series (R4)

create table if not exists public.librelinkup_credentials (
  user_id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  region text not null default 'global',
  access_token text not null,
  account_id text not null,
  token_expires_at timestamptz,
  patient_id text,
  last_sync_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.glicemias (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  recorded_at timestamptz not null,
  glucose_mgdl integer not null,
  trend integer,
  is_high boolean not null default false,
  is_low boolean not null default false,
  source text not null default 'librelinkup'
    check (source in ('librelinkup', 'manual', 'health')),
  external_id text,
  raw jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, external_id)
);

create index if not exists glicemias_user_recorded_idx
  on public.glicemias (user_id, recorded_at desc);

alter table public.librelinkup_credentials enable row level security;
alter table public.glicemias enable row level security;

create policy "Users manage own Libre credentials"
  on public.librelinkup_credentials for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can view own glicemias"
  on public.glicemias for select
  using (auth.uid() = user_id);

create policy "Users can insert own glicemias"
  on public.glicemias for insert
  with check (auth.uid() = user_id);

create policy "Users can delete own glicemias"
  on public.glicemias for delete
  using (auth.uid() = user_id);

create policy "Doctors can view linked patient glicemias"
  on public.glicemias for select
  using (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = glicemias.user_id
        and dp.doctor_id = auth.uid()
    )
  );

-- Realtime: Dose screen listens for new CGM samples from cron/sync.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'glicemias'
  ) then
    alter publication supabase_realtime add table public.glicemias;
  end if;
end $$;

-- Cron (run in SQL Editor after deploying librelinkup-cron + setting secret):
-- select cron.schedule(
--   'librelinkup-sync-every-5-min',
--   '*/5 * * * *',
--   $$
--   select net.http_post(
--     url := 'https://<PROJECT_REF>.supabase.co/functions/v1/librelinkup-cron',
--     headers := jsonb_build_object(
--       'Content-Type', 'application/json',
--       'Authorization', 'Bearer ' || '<LIBRELINKUP_CRON_SECRET>'
--     ),
--     body := '{}'::jsonb
--   );
--   $$
-- );
