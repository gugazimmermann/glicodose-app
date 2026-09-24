-- Backfill ai_usage_logs for recommend-insulin calls that happened before
-- observability was deployed (entries with source=ai but no nearby log).

insert into public.ai_usage_logs (
  function_name,
  user_id,
  model,
  prompt_tokens,
  completion_tokens,
  total_tokens,
  latency_ms,
  success,
  error_message,
  estimated_cost_usd,
  meta,
  created_at
)
select
  'recommend-insulin',
  e.user_id,
  null,
  0,
  0,
  0,
  null,
  true,
  null,
  0,
  jsonb_build_object(
    'backfilled', true,
    'entry_id', e.id
  ),
  e.created_at
from public.entries e
where e.gpt_raw_response is not null
  and e.gpt_raw_response->>'source' = 'ai'
  and not exists (
    select 1
    from public.ai_usage_logs l
    where l.function_name = 'recommend-insulin'
      and l.user_id = e.user_id
      and l.created_at between e.created_at - interval '2 minutes'
                          and e.created_at + interval '2 minutes'
  )
  and not exists (
    select 1
    from public.ai_usage_logs l
    where l.meta->>'entry_id' = e.id::text
      and l.meta->>'backfilled' = 'true'
  );
