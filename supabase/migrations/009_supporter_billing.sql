-- Supporter / tip subscription status mirrored from RevenueCat webhooks.
-- Source of truth for billing is the store + RevenueCat; profiles only cache.

alter table public.profiles
  add column if not exists supporter_product_id text,
  add column if not exists supporter_status text not null default 'none',
  add column if not exists supporter_store text,
  add column if not exists supporter_expires_at timestamptz,
  add column if not exists supporter_updated_at timestamptz;

alter table public.profiles
  drop constraint if exists profiles_supporter_status_check;

alter table public.profiles
  add constraint profiles_supporter_status_check
  check (
    supporter_status in (
      'none',
      'active',
      'grace',
      'expired',
      'canceled'
    )
  );

alter table public.profiles
  drop constraint if exists profiles_supporter_store_check;

alter table public.profiles
  add constraint profiles_supporter_store_check
  check (
    supporter_store is null
    or supporter_store in ('apple', 'google', 'amazon', 'stripe', 'promotional', 'unknown')
  );

comment on column public.profiles.supporter_product_id is
  'Store/RevenueCat product id, e.g. support_20';
comment on column public.profiles.supporter_status is
  'Mirrored from RevenueCat webhook: none|active|grace|expired|canceled';
comment on column public.profiles.supporter_store is
  'apple|google|… from RevenueCat event.store';

-- Users may read their own supporter fields (already covered by select policy).
-- Writes to supporter_* come from the revenuecat-webhook Edge Function (service role).
