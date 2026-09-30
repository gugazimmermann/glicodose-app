-- Current wording must be accepted again. Doctors cannot reset that choice.

alter table public.profiles
  add column if not exists disclaimer_version integer not null default 0;

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
    new.timezone := old.timezone;
    new.theme := old.theme;
    new.gamification_mode := old.gamification_mode;
    new.libre_alerts_enabled := old.libre_alerts_enabled;
    new.libre_alert_hypo_mgdl := old.libre_alert_hypo_mgdl;
    new.libre_alert_hyper_mgdl := old.libre_alert_hyper_mgdl;
    new.libre_alert_stale_minutes := old.libre_alert_stale_minutes;
    new.glucose_context_alerts_enabled := old.glucose_context_alerts_enabled;
    new.glucose_context_computed_at := old.glucose_context_computed_at;
    new.health_sync_enabled := old.health_sync_enabled;
    new.basal_reminder_enabled := old.basal_reminder_enabled;
    new.disclaimer_accepted_at := old.disclaimer_accepted_at;
    new.disclaimer_version := old.disclaimer_version;
    new.created_at := old.created_at;
    new.supporter_status := old.supporter_status;
    new.supporter_product_id := old.supporter_product_id;
    new.supporter_store := old.supporter_store;
    new.supporter_expires_at := old.supporter_expires_at;
    new.supporter_updated_at := old.supporter_updated_at;
  end if;
  return new;
end;
$$;
