-- Patient-owned IANA timezone for day/night targets, AI bolus, and UI clocks.

alter table public.profiles
  add column if not exists timezone text not null default 'America/Sao_Paulo';

-- Doctors may update prescription fields but must not change patient timezone.
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
    new.disclaimer_accepted_at := old.disclaimer_accepted_at;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;
