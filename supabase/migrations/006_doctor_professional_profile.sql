-- Professional profile fields for endocrinologists (filled after signup)

alter table public.doctors
  add column if not exists crm text,
  add column if not exists crm_uf text,
  add column if not exists rqe text,
  add column if not exists specialty text default 'Endocrinologia',
  add column if not exists phone text,
  add column if not exists clinic_name text,
  add column if not exists address_cep text,
  add column if not exists address_street text,
  add column if not exists address_number text,
  add column if not exists address_complement text,
  add column if not exists address_neighborhood text,
  add column if not exists address_city text,
  add column if not exists address_state text,
  add column if not exists profile_completed_at timestamptz;
