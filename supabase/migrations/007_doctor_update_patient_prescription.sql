-- Allow linked doctors to update patient prescription fields on profiles

create policy "Doctors can update linked patient profiles"
  on public.profiles for update
  using (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = profiles.id
        and dp.doctor_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = profiles.id
        and dp.doctor_id = auth.uid()
    )
  );

-- Non-owners (doctors) may only change prescription-related columns
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
    new.disclaimer_accepted_at := old.disclaimer_accepted_at;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

drop trigger if exists restrict_doctor_profile_updates on public.profiles;
create trigger restrict_doctor_profile_updates
  before update on public.profiles
  for each row
  execute function public.restrict_doctor_profile_updates();
