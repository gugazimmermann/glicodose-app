-- Fix ambiguous patient_id: PL/pgSQL variable collided with doctor_patients.patient_id

create or replace function public.link_patient_by_code(p_code text)
returns table (id uuid, full_name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  normalized text;
  v_patient_id uuid;
  v_patient_name text;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  if not exists (select 1 from public.doctors d where d.id = uid) then
    raise exception 'doctor profile required';
  end if;

  normalized := upper(trim(p_code));
  if normalized is null or length(normalized) <> 6 or normalized !~ '^[A-Z0-9]{6}$' then
    raise exception 'invalid share code';
  end if;

  select p.id, p.full_name
  into v_patient_id, v_patient_name
  from public.profiles p
  where p.share_code = normalized;

  if v_patient_id is null then
    raise exception 'patient not found';
  end if;

  if v_patient_id = uid then
    raise exception 'cannot link to yourself';
  end if;

  insert into public.doctor_patients (doctor_id, patient_id)
  values (uid, v_patient_id)
  on conflict (doctor_id, patient_id) do nothing;

  id := v_patient_id;
  full_name := v_patient_name;
  return next;
end;
$$;
