-- Emergency undo for setup_server_password.sql: puts the dashboard tables back to open access
-- (the dashboard then falls back to its old on-page password screen). Run in the Supabase SQL Editor.
do $$
declare t text; pol record;
begin
  foreach t in array array['expansion_pairs','km_actuals','expansion_2027','crm_leads','crm_stage_history','crm_repurposing'] loop
    if to_regclass('public.' || t) is null then continue; end if;
    for pol in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', pol.policyname, t);
    end loop;
    execute format('create policy "open read"   on public.%I for select to anon using (true)', t);
    execute format('create policy "open insert" on public.%I for insert to anon with check (true)', t);
    execute format('create policy "open update" on public.%I for update to anon using (true) with check (true)', t);
    execute format('create policy "open delete" on public.%I for delete to anon using (true)', t);
  end loop;
end $$;
-- turn server-side checking off so the page uses its old password screen again
update public.dash_auth set pw_hash = null where id = 1;
