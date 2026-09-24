-- Time-of-day schedules for FSI and I:C (pump-style segments).
-- Each segment: { "start_minute": 0..1439, "value": number > 0 }
-- Scalars isf_mgdl_per_u / ic_ratio remain as midnight (start 0) mirrors.

alter table public.profiles
  add column if not exists isf_schedule jsonb not null default '[]'::jsonb;

alter table public.profiles
  add column if not exists ic_schedule jsonb not null default '[]'::jsonb;

-- Backfill single-band schedules from existing scalars.
update public.profiles
set isf_schedule = jsonb_build_array(
  jsonb_build_object('start_minute', 0, 'value', isf_mgdl_per_u)
)
where isf_mgdl_per_u is not null
  and (
    isf_schedule is null
    or isf_schedule = '[]'::jsonb
    or jsonb_typeof(isf_schedule) <> 'array'
    or jsonb_array_length(isf_schedule) = 0
  );

update public.profiles
set ic_schedule = jsonb_build_array(
  jsonb_build_object('start_minute', 0, 'value', ic_ratio)
)
where ic_ratio is not null
  and (
    ic_schedule is null
    or ic_schedule = '[]'::jsonb
    or jsonb_typeof(ic_schedule) <> 'array'
    or jsonb_array_length(ic_schedule) = 0
  );
