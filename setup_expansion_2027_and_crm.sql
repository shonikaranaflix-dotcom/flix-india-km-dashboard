-- Flix India KM Dashboard — Supabase setup for "Expansion 2027" + "Leads CRM"
-- Run in Supabase: project rjuxnusaoqlpxcgchdnf -> SQL Editor -> New query -> paste -> Run.
-- Safe to run more than once (idempotent). Covers both tabs, so it replaces setup_expansion_2027.sql.

-- ============ 1. EXPANSION 2027 ============
create table if not exists public.expansion_2027 (
  id             bigint generated always as identity primary key,
  route          text not null default '',
  lc             text not null default '',
  pair           text not null default '',
  variation      text not null default '',
  go_live        text not null default '2027-03-15',
  status         text not null default 'Execution Phase',
  bp             text not null default '',
  bd_golive_time text not null default '',
  volvo          text not null default '',
  product        text not null default '',
  last_mile      text not null default '',
  bdm            text not null default '',
  remarks        text not null default '',
  updated_at     timestamptz not null default now(),
  updated_by     text
);
-- commercials filled in automatically when a CRM lead is Signed
alter table public.expansion_2027 add column if not exists rt_amount    numeric;
alter table public.expansion_2027 add column if not exists rt_km        numeric;
alter table public.expansion_2027 add column if not exists rate_per_km  numeric;
alter table public.expansion_2027 add column if not exists crm_lead_id  bigint;

-- ============ 2. LEADS CRM ============
create table if not exists public.crm_leads (
  id            bigint generated always as identity primary key,
  bp_name       text not null default '',
  routes        text not null default '',          -- route name (pick from the 2027 list so it can match)
  rt_amount     numeric,                           -- proposed round trip amount (Rs)
  rt_km         numeric,                           -- round trip KM
  rate_per_km   numeric generated always as (case when rt_km > 0 and rt_amount > 0 then rt_amount / rt_km end) stored,
  pairs         integer not null default 1,
  stage         text not null default 'Connected'
                check (stage in ('Connected','Business Model Discussion','Commercial Negotiation','Ops Due Diligence','Signed','Dropped')),
  bdm           text not null default '',
  contact_name  text not null default '',
  contact_phone text not null default '',
  next_followup text not null default '',
  remarks       text not null default '',
  signed_at     timestamptz,
  handoff_note  text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    text
);
-- fields added in v2 (safe to re-run)
alter table public.crm_leads add column if not exists partner_type    text not null default ''
  check (partner_type in ('','New','Existing'));
alter table public.crm_leads add column if not exists lead_source     text not null default ''
  check (lead_source in ('','Redbus','OEM Referral','BP Referral','Inbound Lead','Others'));
alter table public.crm_leads add column if not exists operator_type   text not null default ''
  check (operator_type in ('','Intercity','Trucking Operators','ETS'));
alter table public.crm_leads add column if not exists aggregator      text not null default ''
  check (aggregator in ('','Yes','No'));
alter table public.crm_leads add column if not exists aggregator_name text not null default '';
alter table public.crm_leads add column if not exists meta_rating     numeric check (meta_rating between 0 and 5);
alter table public.crm_leads add column if not exists fleet_size      integer check (fleet_size >= 0);
alter table public.crm_leads add column if not exists line_code       text not null default '';   -- maps to expansion_2027.lc

create table if not exists public.crm_stage_history (
  id          bigint generated always as identity primary key,
  lead_id     bigint not null references public.crm_leads(id) on delete cascade,
  from_stage  text,
  to_stage    text not null,
  changed_at  timestamptz not null default now()
);

-- ============ 3. ACCESS (same open anon model as the 2026 expansion_pairs table) ============
do $$
declare t text;
begin
  foreach t in array array['expansion_2027','crm_leads','crm_stage_history'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "%1$s anon read" on public.%1$I',   t);
    execute format('drop policy if exists "%1$s anon insert" on public.%1$I', t);
    execute format('drop policy if exists "%1$s anon update" on public.%1$I', t);
    execute format('drop policy if exists "%1$s anon delete" on public.%1$I', t);
    execute format('create policy "%1$s anon read"   on public.%1$I for select to anon using (true)', t);
    execute format('create policy "%1$s anon insert" on public.%1$I for insert to anon with check (true)', t);
    execute format('create policy "%1$s anon update" on public.%1$I for update to anon using (true) with check (true)', t);
    execute format('create policy "%1$s anon delete" on public.%1$I for delete to anon using (true)', t);
    execute format('grant select, insert, update, delete on public.%I to anon', t);
  end loop;
end $$;
