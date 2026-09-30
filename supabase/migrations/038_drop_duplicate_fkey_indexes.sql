-- Duplicate *_fkey_idx indexes were added beside indexes that already start
-- with the same column, and those duplicates have never been scanned.
-- Drop an unused index when another index already covers that leading column.
-- If it is the only cover, order by that column so the index is actually used.

do $$
declare
  idx record;
  leading_att int2;
  leading_col text;
  dummy text;
begin
  perform set_config('enable_seqscan', 'off', true);
  perform set_config('enable_bitmapscan', 'off', true);

  for idx in
    select
      ns.nspname as schema_name,
      tc.relname as table_name,
      tc.oid as table_oid,
      ic.relname as index_name,
      i.indexrelid,
      i.indkey::text as indkey_text
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
    select trim(part)::int2
      into leading_att
    from unnest(string_to_array(idx.indkey_text, ' '))
      with ordinality as keys(part, key_ord)
    where trim(part) <> ''
    order by key_ord
    limit 1;

    if exists (
      select 1
      from pg_index other
      where other.indrelid = idx.table_oid
        and other.indexrelid <> idx.indexrelid
        and other.indisvalid
        and other.indpred is null
        and (
          select trim(part)::int2
          from unnest(string_to_array(other.indkey::text, ' '))
            with ordinality as keys(part, key_ord)
          where trim(part) <> ''
          order by key_ord
          limit 1
        ) = leading_att
    ) then
      execute format(
        'drop index if exists %I.%I',
        idx.schema_name,
        idx.index_name
      );
      continue;
    end if;

    select a.attname
      into leading_col
    from pg_attribute a
    where a.attrelid = idx.table_oid
      and a.attnum = leading_att
      and not a.attisdropped;

    execute format(
      'select %I::text from %I.%I order by %I limit 1',
      leading_col,
      idx.schema_name,
      idx.table_name,
      leading_col
    )
    into dummy;
  end loop;
end;
$$;
