-- 034 drops unused indexes, including the only index on a foreign key.
-- Recreate a covering index for every public foreign key that no longer has one.
-- Primary keys and indexes that already start with the foreign-key columns are left alone.

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
      ) as column_slug
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where con.contype = 'f'
      and n.nspname = 'public'
      and not exists (
        select 1
        from pg_index i
        where i.indrelid = con.conrelid
          and i.indisvalid
          and i.indpred is null
          and (i.indkey::smallint[])[1:array_length(con.conkey, 1)] = con.conkey
      )
  loop
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
