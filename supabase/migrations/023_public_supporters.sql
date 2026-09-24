-- Marketing-site Stripe supporters (no doctor login).
-- Source of truth is Stripe; public_supporters caches status for admin stats.

create table if not exists public.public_supporters (
  id uuid primary key default gen_random_uuid(),
  email text,
  full_name text,
  stripe_customer_id text not null,
  stripe_subscription_id text,
  supporter_product_id text,
  supporter_status text not null default 'none',
  supporter_store text not null default 'stripe',
  supporter_expires_at timestamptz,
  supporter_updated_at timestamptz,
  created_at timestamptz not null default now(),
  constraint public_supporters_stripe_customer_id_key unique (stripe_customer_id),
  constraint public_supporters_supporter_status_check check (
    supporter_status in (
      'none',
      'active',
      'grace',
      'expired',
      'canceled'
    )
  ),
  constraint public_supporters_supporter_store_check check (
    supporter_store = 'stripe'
  )
);

create unique index if not exists public_supporters_stripe_subscription_id_key
  on public.public_supporters (stripe_subscription_id)
  where stripe_subscription_id is not null;

comment on table public.public_supporters is
  'Stripe subscriptions from marketing-site /apoiar (no auth user)';
comment on column public.public_supporters.supporter_product_id is
  'Product key mirrored from Stripe, e.g. support_20';
comment on column public.public_supporters.supporter_status is
  'Mirrored from Stripe webhook: none|active|grace|expired|canceled';

alter table public.public_supporters enable row level security;
-- No client policies: writes via service role (webhook/backfill); reads via admin RPC.

create or replace function public.get_admin_donation_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  doctors_supporters jsonb;
  doctors_count int;
  doctors_monthly int;
  patients_supporters jsonb;
  patients_count int;
  patients_monthly int;
  website_supporters jsonb;
  website_count int;
  website_monthly int;
  result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'not authorized';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', d.id,
        'full_name', d.full_name,
        'product_id', d.supporter_product_id,
        'monthly_brl', public.supporter_monthly_brl(d.supporter_product_id),
        'status', d.supporter_status,
        'updated_at', d.supporter_updated_at
      )
      order by public.supporter_monthly_brl(d.supporter_product_id) desc,
               lower(d.full_name)
    ),
    '[]'::jsonb
  )
  into doctors_supporters
  from public.doctors d
  where d.supporter_status in ('active', 'grace')
    and (
      d.supporter_store = 'stripe'
      or (d.supporter_store is null and d.supporter_product_id is not null)
    );

  select
    coalesce(count(*)::int, 0),
    coalesce(sum(public.supporter_monthly_brl(d.supporter_product_id))::int, 0)
  into doctors_count, doctors_monthly
  from public.doctors d
  where d.supporter_status in ('active', 'grace')
    and (
      d.supporter_store = 'stripe'
      or (d.supporter_store is null and d.supporter_product_id is not null)
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'full_name', p.full_name,
        'product_id', p.supporter_product_id,
        'monthly_brl', public.supporter_monthly_brl(p.supporter_product_id),
        'status', p.supporter_status,
        'updated_at', p.supporter_updated_at
      )
      order by public.supporter_monthly_brl(p.supporter_product_id) desc,
               lower(coalesce(p.full_name, ''))
    ),
    '[]'::jsonb
  )
  into patients_supporters
  from public.profiles p
  where p.supporter_status in ('active', 'grace')
    and p.supporter_product_id is not null
    and not exists (select 1 from public.doctors d where d.id = p.id)
    and not exists (select 1 from public.admin_users a where a.id = p.id);

  select
    coalesce(count(*)::int, 0),
    coalesce(sum(public.supporter_monthly_brl(p.supporter_product_id))::int, 0)
  into patients_count, patients_monthly
  from public.profiles p
  where p.supporter_status in ('active', 'grace')
    and p.supporter_product_id is not null
    and not exists (select 1 from public.doctors d where d.id = p.id)
    and not exists (select 1 from public.admin_users a where a.id = p.id);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'full_name', coalesce(nullif(s.full_name, ''), nullif(s.email, ''), 'Apoiador do site'),
        'product_id', s.supporter_product_id,
        'monthly_brl', public.supporter_monthly_brl(s.supporter_product_id),
        'status', s.supporter_status,
        'updated_at', s.supporter_updated_at
      )
      order by public.supporter_monthly_brl(s.supporter_product_id) desc,
               lower(coalesce(s.full_name, s.email, ''))
    ),
    '[]'::jsonb
  )
  into website_supporters
  from public.public_supporters s
  where s.supporter_status in ('active', 'grace');

  select
    coalesce(count(*)::int, 0),
    coalesce(sum(public.supporter_monthly_brl(s.supporter_product_id))::int, 0)
  into website_count, website_monthly
  from public.public_supporters s
  where s.supporter_status in ('active', 'grace');

  select jsonb_build_object(
    'total', jsonb_build_object(
      'active_count', doctors_count + patients_count + website_count,
      'monthly_brl', doctors_monthly + patients_monthly + website_monthly
    ),
    'doctors', jsonb_build_object(
      'active_count', doctors_count,
      'monthly_brl', doctors_monthly,
      'supporters', doctors_supporters
    ),
    'patients', jsonb_build_object(
      'active_count', patients_count,
      'monthly_brl', patients_monthly,
      'supporters', patients_supporters
    ),
    'website', jsonb_build_object(
      'active_count', website_count,
      'monthly_brl', website_monthly,
      'supporters', website_supporters
    )
  )
  into result;

  return result;
end;
$$;

revoke all on function public.get_admin_donation_stats() from public;
grant execute on function public.get_admin_donation_stats() to authenticated;
