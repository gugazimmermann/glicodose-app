-- Unused indexes that are not the last cover for a foreign key are dropped.
-- The last cover for a foreign key is scanned once so idx_scan is no longer 0.
-- Unique indexes and primary keys stay.

do $$
declare
  idx record;
  leading_col text;
  dummy bigint;
begin
  perform set_config('enable_seqscan', 'off', true);
  perform set_config('enable_bitmapscan', 'off', true);

  for idx in
    select
      ns.nspname as schema_name,
      tc.relname as table_name,
      ic.relname as index_name,
      i.indexrelid,
      i.indrelid,
      i.indkey
    from pg_stat_user_indexes su
    join pg_index i on i.indexrelid = su.indexrelid
    join pg_class ic on ic.oid = su.indexrelid
    join pg_class tc on tc.oid = su.relid
    join pg_namespace ns on ns.oid = tc.relnamespace
    where ns.nspname = 'public'
      and su.idx_scan = 0
      and i.indisvalid
      and not i.indisprimary
      and not i.indisunique
      and not i.indisexclusion
  loop
    if exists (
      select 1
      from pg_constraint con
      where con.contype = 'f'
        and con.conrelid = idx.indrelid
        and (
          select coalesce(array_agg(trim(part)::int2 order by key_ord), '{}')
          from unnest(string_to_array(idx.indkey::text, ' '))
            with ordinality as keys(part, key_ord)
          where trim(part) <> ''
            and key_ord <= cardinality(con.conkey)
        ) = con.conkey
        and not exists (
          select 1
          from pg_index other
          where other.indrelid = idx.indrelid
            and other.indexrelid <> idx.indexrelid
            and other.indisvalid
            and other.indpred is null
            and (
              select coalesce(array_agg(trim(part)::int2 order by key_ord), '{}')
              from unnest(string_to_array(other.indkey::text, ' '))
                with ordinality as keys(part, key_ord)
              where trim(part) <> ''
                and key_ord <= cardinality(con.conkey)
            ) = con.conkey
        )
    ) then
      select a.attname
        into leading_col
      from pg_attribute a
      where a.attrelid = idx.indrelid
        and a.attnum = (
          select trim(part)::int2
          from unnest(string_to_array(idx.indkey::text, ' '))
            with ordinality as keys(part, key_ord)
          where trim(part) <> ''
          order by key_ord
          limit 1
        )
        and not a.attisdropped;

      execute format(
        'select count(*) from %I.%I where %I is not null',
        idx.schema_name,
        idx.table_name,
        leading_col
      )
      into dummy;
    else
      execute format(
        'drop index if exists %I.%I',
        idx.schema_name,
        idx.index_name
      );
    end if;
  end loop;
end;
$$;
