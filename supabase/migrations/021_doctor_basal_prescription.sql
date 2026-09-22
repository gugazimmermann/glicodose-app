-- Allow linked doctors to update basal prescription fields.
-- Also restore dose_step / insulin_duration / night window edits (intent of 012)
-- that were accidentally re-locked when 014–017 rewrote this trigger.

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
    new.libre_alerts_enabled := old.libre_alerts_enabled;
    new.libre_alert_hypo_mgdl := old.libre_alert_hypo_mgdl;
    new.libre_alert_hyper_mgdl := old.libre_alert_hyper_mgdl;
    new.libre_alert_stale_minutes := old.libre_alert_stale_minutes;
    new.health_sync_enabled := old.health_sync_enabled;
    new.basal_reminder_enabled := old.basal_reminder_enabled;
    new.disclaimer_accepted_at := old.disclaimer_accepted_at;
    new.created_at := old.created_at;
    -- Keep billing fields doctor-immutable
    new.supporter_status := old.supporter_status;
    new.supporter_product_id := old.supporter_product_id;
    new.supporter_store := old.supporter_store;
    new.supporter_expires_at := old.supporter_expires_at;
    new.supporter_updated_at := old.supporter_updated_at;
  end if;
  return new;
end;
$$;
