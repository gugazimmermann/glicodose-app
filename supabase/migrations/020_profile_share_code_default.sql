-- Ensure upserts that omit share_code still succeed (NOT NULL without default).
-- Also make ensure_share_code create the profile row when missing.

alter table public.profiles
  alter column share_code set default public.generate_share_code();

create or replace function public.ensure_share_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  code text;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  select share_code into code
  from public.profiles
  where id = uid;

  if not found then
    code := public.generate_share_code();
    insert into public.profiles (id, share_code)
    values (uid, code)
    on conflict (id) do update
      set share_code = coalesce(public.profiles.share_code, excluded.share_code),
          updated_at = now()
    returning share_code into code;
  elsif code is null then
    code := public.generate_share_code();
    update public.profiles
    set share_code = code, updated_at = now()
    where id = uid;
  end if;

  return code;
end;
$$;

revoke all on function public.ensure_share_code() from public;
grant execute on function public.ensure_share_code() to authenticated;
