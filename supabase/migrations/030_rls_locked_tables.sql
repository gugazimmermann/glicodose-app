-- RLS with no policy is already a lock, but the linter treats the
-- missing policy as a mistake. These tables stay closed to the Data API.
-- service_role bypasses RLS, so Edge Functions and admin RPCs still work.

drop policy if exists "No direct API access" on public.ai_usage_logs;
create policy "No direct API access"
  on public.ai_usage_logs
  for all
  to anon, authenticated
  using (false)
  with check (false);

drop policy if exists "No direct API access" on public.public_supporters;
create policy "No direct API access"
  on public.public_supporters
  for all
  to anon, authenticated
  using (false)
  with check (false);

drop policy if exists "No direct API access" on public.libre_alert_state;
create policy "No direct API access"
  on public.libre_alert_state
  for all
  to anon, authenticated
  using (false)
  with check (false);

drop policy if exists "No direct API access" on public.glucose_context_alert_state;
create policy "No direct API access"
  on public.glucose_context_alert_state
  for all
  to anon, authenticated
  using (false)
  with check (false);
