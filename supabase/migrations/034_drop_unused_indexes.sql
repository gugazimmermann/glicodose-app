-- Drop non-unique indexes the advisor marks as unused (idx_scan = 0).
-- Keep indexes whose leading columns cover a foreign key, or the
-- unindexed-foreign-key warning comes back. Unique indexes and primary keys stay.

do $$
declare
  idx record;
begin
  for idx in
    select ns.nspname as schema_name, ic.relname as index_name
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
      and not exists (
        select 1
        from pg_constraint con
        where con.contype = 'f'
          and con.conrelid = tc.oid
          and (
            select coalesce(array_agg(trim(part)::int2 order by key_ord), '{}')
            from unnest(string_to_array(i.indkey::text, ' '))
              with ordinality as keys(part, key_ord)
            where trim(part) <> ''
              and key_ord <= cardinality(con.conkey)
          ) = con.conkey
      )
  loop
    execute format('drop index if exists %I.%I', idx.schema_name, idx.index_name);
  end loop;
end;
$$;
