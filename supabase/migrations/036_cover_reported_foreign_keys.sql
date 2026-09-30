-- 034 removed unused indexes that were the only cover for these foreign keys.
-- indkey is zero-based, so a 1-based slice does not count them as covering.
-- Create the indexes explicitly, then cover any other public foreign key
-- that is still missing one.

create index if not exists doctor_patients_patient_id_idx
  on public.doctor_patients (patient_id);

create index if not exists pet_family_links_owner_idx
  on public.pet_family_links (owner_id);

create index if not exists ai_usage_logs_user_id_idx
  on public.ai_usage_logs (user_id);

create index if not exists prescription_change_log_doctor_idx
  on public.prescription_change_log (doctor_id);

do $$
declare
  fk record;
  idx_name text;
begin
  for fk in
    select
      n.nspname as schema_name,
      c.relname as table_name,
      (
        select string_agg(quote_ident(a.attname), ', ' order by cols.ord)
        from unnest(con.conkey) with ordinality as cols(attnum, ord)
        join pg_attribute a
          on a.attrelid = con.conrelid
         and a.attnum = cols.attnum
         and not a.attisdropped
      ) as columns,
      (
        select string_agg(a.attname, '_' order by cols.ord)
        from unnest(con.conkey) with ordinality as cols(attnum, ord)
        join pg_attribute a
          on a.attrelid = con.conrelid
         and a.attnum = cols.attnum
         and not a.attisdropped
      ) as column_slug,
      con.conkey,
      con.conrelid
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where con.contype = 'f'
      and n.nspname = 'public'
  loop
    if exists (
      select 1
      from pg_index i
      where i.indrelid = fk.conrelid
        and i.indisvalid
        and i.indpred is null
        and (
          select coalesce(array_agg(trim(part)::int2 order by key_ord), '{}')
          from unnest(string_to_array(i.indkey::text, ' '))
            with ordinality as keys(part, key_ord)
          where trim(part) <> ''
            and key_ord <= cardinality(fk.conkey)
        ) = fk.conkey
    ) then
      continue;
    end if;

    idx_name := left(fk.table_name || '_' || fk.column_slug || '_fkey_idx', 63);
    execute format(
      'create index if not exists %I on %I.%I (%s)',
      idx_name,
      fk.schema_name,
      fk.table_name,
      fk.columns
    );
  end loop;
end;
$$;
