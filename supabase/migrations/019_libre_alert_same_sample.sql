-- Same-sample dedupe for Libre FCM alerts (parity with Dart LibreAlertLogic).

alter table public.libre_alert_state
  add column if not exists last_alerted_recorded_at timestamptz;
