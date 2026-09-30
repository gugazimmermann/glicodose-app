-- Monthly equivalent of the annual support plan (R$100/year ≈ R$8/month).

create or replace function public.supporter_monthly_brl(product_id text)
returns int
language sql
immutable
set search_path = public
as $$
  select case product_id
    when 'support_10' then 10
    when 'support_20' then 20
    when 'support_50' then 50
    when 'support_100' then 100
    when 'support_10_annual' then 8
    else 0
  end;
$$;

revoke all on function public.supporter_monthly_brl(text) from public;
grant execute on function public.supporter_monthly_brl(text) to authenticated;
