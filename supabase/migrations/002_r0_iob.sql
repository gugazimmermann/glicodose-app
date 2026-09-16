-- R0: IOB duration + disclaimer acceptance

alter table public.profiles
  add column if not exists insulin_duration_hours numeric not null default 4;

alter table public.profiles
  drop constraint if exists profiles_insulin_duration_hours_check;

alter table public.profiles
  add constraint profiles_insulin_duration_hours_check
  check (insulin_duration_hours > 0 and insulin_duration_hours <= 8);

alter table public.profiles
  add column if not exists disclaimer_accepted_at timestamptz;
