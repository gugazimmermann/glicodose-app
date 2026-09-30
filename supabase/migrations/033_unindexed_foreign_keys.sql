-- Covering indexes for foreign keys the linter flags.
-- A primary key or an index that starts with the foreign-key column
-- already covers the rest.

create index if not exists ai_usage_logs_user_id_idx
  on public.ai_usage_logs (user_id);

create index if not exists prescription_change_log_doctor_idx
  on public.prescription_change_log (doctor_id);

create index if not exists pet_family_links_owner_idx
  on public.pet_family_links (owner_id);
