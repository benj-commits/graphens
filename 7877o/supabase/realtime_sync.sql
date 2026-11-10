-- Run this once in Supabase SQL Editor on an existing project to ensure the
-- admin website and customer app receive the same live changes. Safe to rerun.
-- This changes only Realtime publication membership; it does not change RLS.
do $$
declare
  table_name text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'Supabase Realtime publication supabase_realtime was not found';
  end if;

  foreach table_name in array array['profiles', 'products', 'projects', 'orders', 'messages', 'feedback'] loop
    if to_regclass(format('public.%I', table_name)) is not null
       and not exists (
         select 1
         from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = table_name
       ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end $$;
