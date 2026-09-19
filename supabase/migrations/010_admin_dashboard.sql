-- Admin dashboard: allowlisted admins + aggregate stats RPC

-- ---------------------------------------------------------------------------
-- admin_users
-- ---------------------------------------------------------------------------

create table if not exists public.admin_users (
  id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;

drop policy if exists "Admins can read own row" on public.admin_users;
create policy "Admins can read own row"
  on public.admin_users
  for select
  to authenticated
  using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- is_admin()
-- ---------------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users where id = auth.uid()
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- get_admin_dashboard_stats()
-- ---------------------------------------------------------------------------

create or replace function public.get_admin_dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'not authorized';
  end if;

  select jsonb_build_object(
    'doctors_count', (select count(*)::int from public.doctors),
    'patients_count', (
      select count(*)::int
      from public.profiles p
      where not exists (select 1 from public.doctors d where d.id = p.id)
        and not exists (select 1 from public.admin_users a where a.id = p.id)
    ),
    'doctors', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', d.id,
          'full_name', d.full_name,
          'crm', d.crm,
          'crm_uf', d.crm_uf,
          'patient_count', (
            select count(*)::int
            from public.doctor_patients dp
            where dp.doctor_id = d.id
          )
        )
        order by lower(d.full_name)
      )
      from public.doctors d
    ), '[]'::jsonb)
  )
  into result;

  return result;
end;
$$;

revoke all on function public.get_admin_dashboard_stats() from public;
grant execute on function public.get_admin_dashboard_stats() to authenticated;
