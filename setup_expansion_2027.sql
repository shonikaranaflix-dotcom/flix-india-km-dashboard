-- Flix India KM Dashboard — Expansion 2027 table
-- Run ONCE in Supabase: project rjuxnusaoqlpxcgchdnf -> SQL Editor -> New query -> paste -> Run.
-- Then open the dashboard > "Expansion 2027" tab and click "Load starter list (53 pairs)".

create table if not exists public.expansion_2027 (
  id             bigint generated always as identity primary key,
  route          text not null default '',
  lc             text not null default '',          -- line code
  pair           text not null default '',
  variation      text not null default '',          -- route variation
  go_live        text not null default '2027-03-15',
  status         text not null default 'Execution Phase',
  bp             text not null default '',          -- bus partner
  bd_golive_time text not null default '',          -- BD go-live time
  volvo          text not null default '',          -- 'Yes' / 'No' / ''
  product        text not null default '',          -- Hybrid / Sleeper
  last_mile      text not null default '',          -- last mile / van pickup requirement
  bdm            text not null default '',          -- Aakash / Syed
  remarks        text not null default '',
  updated_at     timestamptz not null default now(),
  updated_by     text
);

alter table public.expansion_2027 enable row level security;

-- Same open access model as the existing 2026 expansion_pairs table (dashboard uses the public anon key).
drop policy if exists "expansion_2027 anon read"   on public.expansion_2027;
drop policy if exists "expansion_2027 anon insert" on public.expansion_2027;
drop policy if exists "expansion_2027 anon update" on public.expansion_2027;
drop policy if exists "expansion_2027 anon delete" on public.expansion_2027;
create policy "expansion_2027 anon read"   on public.expansion_2027 for select to anon using (true);
create policy "expansion_2027 anon insert" on public.expansion_2027 for insert to anon with check (true);
create policy "expansion_2027 anon update" on public.expansion_2027 for update to anon using (true) with check (true);
create policy "expansion_2027 anon delete" on public.expansion_2027 for delete to anon using (true);

grant select, insert, update, delete on public.expansion_2027 to anon;
