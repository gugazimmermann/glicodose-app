-- Patient share codes + doctor portal linking (read-only history)

-- ---------------------------------------------------------------------------
-- share_code on profiles
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists share_code text;

create unique index if not exists profiles_share_code_uidx
  on public.profiles (share_code)
  where share_code is not null;

create or replace function public.generate_share_code()
returns text
language plpgsql
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
  i int;
  attempts int := 0;
begin
  loop
    candidate := '';
    for i in 1..6 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;

    if not exists (
      select 1 from public.profiles where share_code = candidate
    ) then
      return candidate;
    end if;

    attempts := attempts + 1;
    if attempts > 50 then
      raise exception 'could not generate unique share_code';
    end if;
  end loop;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, share_code)
  values (new.id, public.generate_share_code())
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Backfill existing profiles
update public.profiles
set share_code = public.generate_share_code()
where share_code is null;

alter table public.profiles
  alter column share_code set not null;

create or replace function public.ensure_share_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  code text;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  select share_code into code
  from public.profiles
  where id = uid;

  if code is null then
    code := public.generate_share_code();
    update public.profiles
    set share_code = code, updated_at = now()
    where id = uid;
  end if;

  return code;
end;
$$;

revoke all on function public.ensure_share_code() from public;
grant execute on function public.ensure_share_code() to authenticated;

-- ---------------------------------------------------------------------------
-- doctors
-- ---------------------------------------------------------------------------

create table if not exists public.doctors (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.doctors enable row level security;

create policy "Doctors can view own row"
  on public.doctors for select
  using (auth.uid() = id);

create policy "Doctors can insert own row"
  on public.doctors for insert
  with check (auth.uid() = id);

create policy "Doctors can update own row"
  on public.doctors for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- doctor_patients
-- ---------------------------------------------------------------------------

create table if not exists public.doctor_patients (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors (id) on delete cascade,
  patient_id uuid not null references public.profiles (id) on delete cascade,
  linked_at timestamptz not null default now(),
  unique (doctor_id, patient_id)
);

create index if not exists doctor_patients_doctor_id_idx
  on public.doctor_patients (doctor_id);

create index if not exists doctor_patients_patient_id_idx
  on public.doctor_patients (patient_id);

alter table public.doctor_patients enable row level security;

create policy "Doctors can view own links"
  on public.doctor_patients for select
  using (auth.uid() = doctor_id);

create policy "Doctors can delete own links"
  on public.doctor_patients for delete
  using (auth.uid() = doctor_id);

-- Inserts only via SECURITY DEFINER RPC (no direct insert policy)

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

revoke all on function public.link_patient_by_code(text) from public;
grant execute on function public.link_patient_by_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: doctors can read linked patients' profiles and entries
-- ---------------------------------------------------------------------------

create policy "Doctors can view linked patient profiles"
  on public.profiles for select
  using (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = profiles.id
        and dp.doctor_id = auth.uid()
    )
  );

create policy "Doctors can view linked patient entries"
  on public.entries for select
  using (
    exists (
      select 1
      from public.doctor_patients dp
      where dp.patient_id = entries.user_id
        and dp.doctor_id = auth.uid()
    )
  );
