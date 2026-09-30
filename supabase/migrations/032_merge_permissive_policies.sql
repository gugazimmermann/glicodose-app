-- One permissive policy per role and action. The OR keeps the same access.

drop policy if exists "Users can view own entries" on public.entries;
drop policy if exists "Doctors can view linked patient entries" on public.entries;
create policy "Users and linked doctors can view entries"
  on public.entries for select
  using (
    (select auth.uid()) = user_id
    or exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = entries.user_id
        and dp.doctor_id = (select auth.uid())
    )
  );

drop policy if exists "Users can view own profile" on public.profiles;
drop policy if exists "Doctors can view linked patient profiles" on public.profiles;
create policy "Users and linked doctors can view profiles"
  on public.profiles for select
  using (
    (select auth.uid()) = id
    or exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = profiles.id
        and dp.doctor_id = (select auth.uid())
    )
  );

drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Doctors can update linked patient profiles" on public.profiles;
create policy "Users and linked doctors can update profiles"
  on public.profiles for update
  using (
    (select auth.uid()) = id
    or exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = profiles.id
        and dp.doctor_id = (select auth.uid())
    )
  )
  with check (
    (select auth.uid()) = id
    or exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = profiles.id
        and dp.doctor_id = (select auth.uid())
    )
  );

drop policy if exists "Users can view own glicemias" on public.glicemias;
drop policy if exists "Doctors can view linked patient glicemias" on public.glicemias;
create policy "Users and linked doctors can view glicemias"
  on public.glicemias for select
  using (
    (select auth.uid()) = user_id
    or exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = glicemias.user_id
        and dp.doctor_id = (select auth.uid())
    )
  );

drop policy if exists "Owners manage own pet progress" on public.pet_progress;
drop policy if exists "Family can view linked pet progress" on public.pet_progress;
create policy "Owners and family can view pet progress"
  on public.pet_progress for select
  using (
    (select auth.uid()) = user_id
    or exists (
      select 1
      from public.pet_family_links l
      where l.owner_id = pet_progress.user_id
        and l.viewer_id = (select auth.uid())
    )
  );

create policy "Owners insert pet progress"
  on public.pet_progress for insert
  with check ((select auth.uid()) = user_id);

create policy "Owners update pet progress"
  on public.pet_progress for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Owners delete pet progress"
  on public.pet_progress for delete
  using ((select auth.uid()) = user_id);
