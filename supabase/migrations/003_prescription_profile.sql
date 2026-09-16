-- Prescription-aligned profile: diabetes type + day/night targets

alter table public.profiles
  add column if not exists diabetes_type text;

alter table public.profiles
  add column if not exists target_night_mgdl integer;

alter table public.profiles
  add column if not exists night_start_minute integer not null default 1200;

alter table public.profiles
  add column if not exists night_end_minute integer not null default 359;

comment on column public.profiles.diabetes_type is 'type_1 | type_2 | other';
comment on column public.profiles.night_start_minute is 'Minutes from midnight, default 1200 = 20:00';
comment on column public.profiles.night_end_minute is 'Minutes from midnight, default 359 = 05:59';
