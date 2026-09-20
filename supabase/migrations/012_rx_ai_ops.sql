-- Expand doctor-editable Rx fields, AI persistence/usage logs, patient donations, admin AI stats

-- 1) Doctors may update dose_step, insulin duration, and night window
create or replace function public.restrict_doctor_profile_updates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is distinct from old.id then
    new.id := old.id;
    new.share_code := old.share_code;
    new.full_name := old.full_name;
    new.diabetes_type := old.diabetes_type;
    new.disclaimer_accepted_at := old.disclaimer_accepted_at;
    new.created_at := old.created_at;
    -- Keep billing fields doctor-immutable
    new.supporter_status := old.supporter_status;
    new.supporter_product_id := old.supporter_product_id;
    new.supporter_store := old.supporter_store;
    new.supporter_updated_at := old.supporter_updated_at;
  end if;
  return new;
end;
$$;

-- 2) Audit trail when a linked doctor changes prescription fields
create table if not exists public.prescription_change_log (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles (id) on delete cascade,
  doctor_id uuid not null references public.doctors (id) on delete cascade,
  changes jsonb not null default '{}'::jsonb,
  source text not null default 'manual'
    check (source in ('manual', 'ai_apply')),
  created_at timestamptz not null default now()
);

create index if not exists prescription_change_log_patient_idx
  on public.prescription_change_log (patient_id, created_at desc);

alter table public.prescription_change_log enable row level security;

create policy "Doctors can insert own prescription logs"
  on public.prescription_change_log for insert
  with check (
    doctor_id = auth.uid()
    and exists (
      select 1 from public.doctor_patients dp
      where dp.doctor_id = auth.uid()
        and dp.patient_id = prescription_change_log.patient_id
    )
  );

create policy "Doctors can view logs for linked patients"
  on public.prescription_change_log for select
  using (
    exists (
      select 1 from public.doctor_patients dp
      where dp.doctor_id = auth.uid()
        and dp.patient_id = prescription_change_log.patient_id
    )
  );

-- 3) Persisted AI history analyses
create table if not exists public.patient_ai_analyses (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors (id) on delete cascade,
  patient_id uuid not null references public.profiles (id) on delete cascade,
  period text not null,
  entry_count int not null default 0,
  stats jsonb not null default '{}'::jsonb,
  analysis jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists patient_ai_analyses_patient_idx
  on public.patient_ai_analyses (patient_id, created_at desc);

create index if not exists patient_ai_analyses_doctor_idx
  on public.patient_ai_analyses (doctor_id, created_at desc);

alter table public.patient_ai_analyses enable row level security;

create policy "Doctors can insert analyses for linked patients"
  on public.patient_ai_analyses for insert
  with check (
    doctor_id = auth.uid()
    and exists (
      select 1 from public.doctor_patients dp
      where dp.doctor_id = auth.uid()
        and dp.patient_id = patient_ai_analyses.patient_id
    )
  );

create policy "Doctors can view analyses for linked patients"
  on public.patient_ai_analyses for select
  using (
    exists (
      select 1 from public.doctor_patients dp
      where dp.doctor_id = auth.uid()
        and dp.patient_id = patient_ai_analyses.patient_id
    )
  );

-- 4) AI usage / cost observability
create table if not exists public.ai_usage_logs (
  id uuid primary key default gen_random_uuid(),
  function_name text not null,
  user_id uuid references auth.users (id) on delete set null,
  model text,
  prompt_tokens int not null default 0,
  completion_tokens int not null default 0,
  total_tokens int not null default 0,
  latency_ms int,
  success boolean not null default true,
  error_message text,
  estimated_cost_usd numeric(12, 6) not null default 0,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists ai_usage_logs_created_idx
  on public.ai_usage_logs (created_at desc);

create index if not exists ai_usage_logs_fn_idx
  on public.ai_usage_logs (function_name, created_at desc);

alter table public.ai_usage_logs enable row level security;
-- No client policies: inserts via service role from Edge Functions; reads via admin RPC.

-- 5) Patient RevenueCat donations in admin stats
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

  select jsonb_build_object(
    'total', jsonb_build_object(
      'active_count', doctors_count + patients_count,
      'monthly_brl', doctors_monthly + patients_monthly
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
    )
  )
  into result;

  return result;
end;
$$;

revoke all on function public.get_admin_donation_stats() from public;
grant execute on function public.get_admin_donation_stats() to authenticated;

-- 6) Admin AI usage metrics
create or replace function public.get_admin_ai_stats(days int default 30)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  since timestamptz;
  by_fn jsonb;
  totals jsonb;
  result jsonb;
  safe_days int;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'not authorized';
  end if;

  safe_days := greatest(1, least(coalesce(days, 30), 365));
  since := now() - make_interval(days => safe_days);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'function_name', s.function_name,
        'calls', s.calls,
        'errors', s.errors,
        'prompt_tokens', s.prompt_tokens,
        'completion_tokens', s.completion_tokens,
        'total_tokens', s.total_tokens,
        'estimated_cost_usd', s.estimated_cost_usd,
        'avg_latency_ms', s.avg_latency_ms
      )
      order by s.calls desc
    ),
    '[]'::jsonb
  )
  into by_fn
  from (
    select
      function_name,
      count(*)::int as calls,
      count(*) filter (where not success)::int as errors,
      coalesce(sum(prompt_tokens), 0)::int as prompt_tokens,
      coalesce(sum(completion_tokens), 0)::int as completion_tokens,
      coalesce(sum(total_tokens), 0)::int as total_tokens,
      round(coalesce(sum(estimated_cost_usd), 0)::numeric, 4) as estimated_cost_usd,
      round(avg(latency_ms) filter (where latency_ms is not null))::int as avg_latency_ms
    from public.ai_usage_logs
    where created_at >= since
    group by function_name
  ) s;

  select jsonb_build_object(
    'calls', coalesce(count(*)::int, 0),
    'errors', coalesce(count(*) filter (where not success)::int, 0),
    'prompt_tokens', coalesce(sum(prompt_tokens), 0)::int,
    'completion_tokens', coalesce(sum(completion_tokens), 0)::int,
    'total_tokens', coalesce(sum(total_tokens), 0)::int,
    'estimated_cost_usd', round(coalesce(sum(estimated_cost_usd), 0)::numeric, 4),
    'avg_latency_ms', round(avg(latency_ms) filter (where latency_ms is not null))::int
  )
  into totals
  from public.ai_usage_logs
  where created_at >= since;

  select jsonb_build_object(
    'days', safe_days,
    'since', since,
    'totals', totals,
    'by_function', by_fn
  )
  into result;

  return result;
end;
$$;

revoke all on function public.get_admin_ai_stats(int) from public;
grant execute on function public.get_admin_ai_stats(int) to authenticated;
