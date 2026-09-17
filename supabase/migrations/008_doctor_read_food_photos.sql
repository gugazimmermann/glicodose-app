-- Allow linked doctors to read patient food photos (path: {patient_id}/...)

create policy "Doctors can view linked patient food photos"
  on storage.objects for select
  using (
    bucket_id = 'food-photos'
    and exists (
      select 1
      from public.doctor_patients dp
      where dp.doctor_id = auth.uid()
        and dp.patient_id::text = (storage.foldername(name))[1]
    )
  );
