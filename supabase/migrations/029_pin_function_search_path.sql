-- Pin search_path on functions the linter still flags as mutable.
-- Existing databases only pick this up when this migration is applied.

alter function public.generate_share_code()
  set search_path = public;

alter function public.supporter_monthly_brl(text)
  set search_path = public;
