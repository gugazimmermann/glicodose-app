-- Evaluate auth.uid() once per statement instead of once per row.
-- Access rules are unchanged.

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
  on public.profiles for select
  using ((select auth.uid()) = id);

drop policy if exists "Users can insert own profile" on public.profiles;
create policy "Users can insert own profile"
  on public.profiles for insert
  with check ((select auth.uid()) = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "Users can view own entries" on public.entries;
create policy "Users can view own entries"
  on public.entries for select
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own entries" on public.entries;
create policy "Users can insert own entries"
  on public.entries for insert
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update own entries" on public.entries;
create policy "Users can update own entries"
  on public.entries for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete own entries" on public.entries;
create policy "Users can delete own entries"
  on public.entries for delete
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can upload own food photos" on storage.objects;
create policy "Users can upload own food photos"
  on storage.objects for insert
  with check (
    bucket_id = 'food-photos'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

drop policy if exists "Users can update own food photos" on storage.objects;
create policy "Users can update own food photos"
  on storage.objects for update
  using (
    bucket_id = 'food-photos'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

drop policy if exists "Users can read own food photos" on storage.objects;
create policy "Users can read own food photos"
  on storage.objects for select
  using (
    bucket_id = 'food-photos'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

drop policy if exists "Users can delete own food photos" on storage.objects;
create policy "Users can delete own food photos"
  on storage.objects for delete
  using (
    bucket_id = 'food-photos'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

drop policy if exists "Doctors can view own row" on public.doctors;
create policy "Doctors can view own row"
  on public.doctors for select
  using ((select auth.uid()) = id);

drop policy if exists "Doctors can insert own row" on public.doctors;
create policy "Doctors can insert own row"
  on public.doctors for insert
  with check ((select auth.uid()) = id);

drop policy if exists "Doctors can update own row" on public.doctors;
create policy "Doctors can update own row"
  on public.doctors for update
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "Doctors can view own links" on public.doctor_patients;
create policy "Doctors can view own links"
  on public.doctor_patients for select
  using ((select auth.uid()) = doctor_id);

drop policy if exists "Doctors can delete own links" on public.doctor_patients;
create policy "Doctors can delete own links"
  on public.doctor_patients for delete
  using ((select auth.uid()) = doctor_id);

drop policy if exists "Doctors can view linked patient profiles" on public.profiles;
create policy "Doctors can view linked patient profiles"
  on public.profiles for select
  using (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = profiles.id
        and dp.doctor_id = (select auth.uid())
    )
  );

drop policy if exists "Doctors can view linked patient entries" on public.entries;
create policy "Doctors can view linked patient entries"
  on public.entries for select
  using (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = entries.user_id
        and dp.doctor_id = (select auth.uid())
    )
  );

drop policy if exists "Doctors can update linked patient profiles" on public.profiles;
create policy "Doctors can update linked patient profiles"
  on public.profiles for update
  using (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = profiles.id
        and dp.doctor_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = profiles.id
        and dp.doctor_id = (select auth.uid())
    )
  );

drop policy if exists "Doctors can view linked patient food photos" on storage.objects;
create policy "Doctors can view linked patient food photos"
  on storage.objects for select
  using (
    bucket_id = 'food-photos'
    and exists (
      select 1
      from public.doctor_patients dp
      where dp.doctor_id = (select auth.uid())
        and dp.patient_id::text = (storage.foldername(name))[1]
    )
  );

drop policy if exists "Admins can read own row" on public.admin_users;
create policy "Admins can read own row"
  on public.admin_users
  for select
  to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "Doctors can insert own prescription logs" on public.prescription_change_log;
create policy "Doctors can insert own prescription logs"
  on public.prescription_change_log for insert
  with check (
    doctor_id = (select auth.uid())
    and exists (
      select 1 from public.doctor_patients dp
      where dp.doctor_id = (select auth.uid())
        and dp.patient_id = prescription_change_log.patient_id
    )
  );

drop policy if exists "Doctors can view logs for linked patients" on public.prescription_change_log;
create policy "Doctors can view logs for linked patients"
  on public.prescription_change_log for select
  using (
    exists (
      select 1 from public.doctor_patients dp
      where dp.doctor_id = (select auth.uid())
        and dp.patient_id = prescription_change_log.patient_id
    )
  );

drop policy if exists "Doctors can insert analyses for linked patients" on public.patient_ai_analyses;
create policy "Doctors can insert analyses for linked patients"
  on public.patient_ai_analyses for insert
  with check (
    doctor_id = (select auth.uid())
    and exists (
      select 1 from public.doctor_patients dp
      where dp.doctor_id = (select auth.uid())
        and dp.patient_id = patient_ai_analyses.patient_id
    )
  );

drop policy if exists "Doctors can view analyses for linked patients" on public.patient_ai_analyses;
create policy "Doctors can view analyses for linked patients"
  on public.patient_ai_analyses for select
  using (
    exists (
      select 1 from public.doctor_patients dp
      where dp.doctor_id = (select auth.uid())
        and dp.patient_id = patient_ai_analyses.patient_id
    )
  );

drop policy if exists "Users manage own Libre credentials" on public.librelinkup_credentials;
create policy "Users manage own Libre credentials"
  on public.librelinkup_credentials for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can view own glicemias" on public.glicemias;
create policy "Users can view own glicemias"
  on public.glicemias for select
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own glicemias" on public.glicemias;
create policy "Users can insert own glicemias"
  on public.glicemias for insert
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete own glicemias" on public.glicemias;
create policy "Users can delete own glicemias"
  on public.glicemias for delete
  using ((select auth.uid()) = user_id);

drop policy if exists "Doctors can view linked patient glicemias" on public.glicemias;
create policy "Doctors can view linked patient glicemias"
  on public.glicemias for select
  using (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = glicemias.user_id
        and dp.doctor_id = (select auth.uid())
    )
  );

drop policy if exists "Users can update own glicemias" on public.glicemias;
create policy "Users can update own glicemias"
  on public.glicemias for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users manage own device tokens" on public.device_tokens;
create policy "Users manage own device tokens"
  on public.device_tokens for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users manage own basal doses" on public.basal_doses;
create policy "Users manage own basal doses"
  on public.basal_doses for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users read own glucose context patterns"
  on public.glucose_context_patterns;
create policy "Users read own glucose context patterns"
  on public.glucose_context_patterns for select
  using ((select auth.uid()) = user_id);

drop policy if exists "Users manage own food recipes" on public.food_recipes;
create policy "Users manage own food recipes"
  on public.food_recipes for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Owners manage own pet progress" on public.pet_progress;
create policy "Owners manage own pet progress"
  on public.pet_progress for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Family can view linked pet progress" on public.pet_progress;
create policy "Family can view linked pet progress"
  on public.pet_progress for select
  using (
    exists (
      select 1
      from public.pet_family_links l
      where l.owner_id = pet_progress.user_id
        and l.viewer_id = (select auth.uid())
    )
  );

drop policy if exists "Participants can view pet links" on public.pet_family_links;
create policy "Participants can view pet links"
  on public.pet_family_links for select
  using ((select auth.uid()) = viewer_id or (select auth.uid()) = owner_id);

drop policy if exists "Participants can remove pet links" on public.pet_family_links;
create policy "Participants can remove pet links"
  on public.pet_family_links for delete
  using ((select auth.uid()) = viewer_id or (select auth.uid()) = owner_id);
