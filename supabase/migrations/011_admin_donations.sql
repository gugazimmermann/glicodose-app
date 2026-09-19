-- Admin donation stats from Stripe doctor subscriptions (medicos portal)

create or replace function public.supporter_monthly_brl(product_id text)
returns int
language sql
immutable
as $$
  select case product_id
    when 'support_10' then 10
    when 'support_20' then 20
    when 'support_50' then 50
    when 'support_100' then 100
    else 0
  end;
$$;

revoke all on function public.supporter_monthly_brl(text) from public;
grant execute on function public.supporter_monthly_brl(text) to authenticated;

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

  select jsonb_build_object(
    'total', jsonb_build_object(
      'active_count', doctors_count,
      'monthly_brl', doctors_monthly
    ),
    'doctors', jsonb_build_object(
      'active_count', doctors_count,
      'monthly_brl', doctors_monthly,
      'supporters', doctors_supporters
    ),
    'patients', jsonb_build_object(
      'active_count', 0,
      'monthly_brl', 0,
      'supporters', '[]'::jsonb
    )
  )
  into result;

  return result;
end;
$$;

revoke all on function public.get_admin_donation_stats() from public;
grant execute on function public.get_admin_donation_stats() to authenticated;
