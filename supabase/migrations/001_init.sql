-- Profiles, entries, RLS and storage for diabetes app

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  target_glucose_mgdl integer,
  isf_mgdl_per_u numeric,
  ic_ratio numeric,
  rapid_insulin_name text,
  dose_step numeric not null default 0.5,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  recorded_at timestamptz not null default now(),
  glucose_mgdl integer not null,
  food_text text,
  food_image_path text,
  recommended_insulin numeric,
  applied_insulin numeric,
  gpt_raw_response jsonb,
  created_at timestamptz not null default now()
);

create index if not exists entries_user_id_recorded_at_idx
  on public.entries (user_id, recorded_at desc);

alter table public.profiles enable row level security;
alter table public.entries enable row level security;

create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

create policy "Users can view own entries"
  on public.entries for select
  using (auth.uid() = user_id);

create policy "Users can insert own entries"
  on public.entries for insert
  with check (auth.uid() = user_id);

create policy "Users can update own entries"
  on public.entries for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own entries"
  on public.entries for delete
  using (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
values ('food-photos', 'food-photos', false)
on conflict (id) do nothing;

create policy "Users can upload own food photos"
  on storage.objects for insert
  with check (
    bucket_id = 'food-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Users can update own food photos"
  on storage.objects for update
  using (
    bucket_id = 'food-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Users can read own food photos"
  on storage.objects for select
  using (
    bucket_id = 'food-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Users can delete own food photos"
  on storage.objects for delete
  using (
    bucket_id = 'food-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Auto-create empty profile row on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
