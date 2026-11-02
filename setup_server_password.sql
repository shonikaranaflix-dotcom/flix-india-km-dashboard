-- =====================================================================================
-- Flix India KM Dashboard — SERVER-SIDE shared password
-- Run ONCE in Supabase: project rjuxnusaoqlpxcgchdnf -> SQL Editor -> New query -> paste -> Run.
-- BEFORE RUNNING: change the password on the line marked  <<< CHANGE THIS >>>  (step 3).
--
-- What it does
--   * The dashboard's public key can no longer read or write ANY table by itself.
--   * People enter the shared password on the dashboard; Supabase checks it on the server and
--     hands back a pass that is valid for 12 hours. Only requests carrying a valid pass can
--     read / write the tables.
--   * Wrong passwords are throttled (8 failures per IP per 10 minutes).
-- To undo everything:  run  rollback_open_access.sql
-- To change the password later (this also logs everybody out):
--     select public.dash_set_password('NEW PASSWORD');
-- =====================================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- 1. storage (not reachable with the public key) ----------
create table if not exists public.dash_auth (
  id            int primary key default 1 check (id = 1),
  pw_hash       text,
  token_secret  text not null default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  updated_at    timestamptz not null default now()
);
insert into public.dash_auth (id) values (1) on conflict (id) do nothing;

create table if not exists public.dash_login_attempts (
  id  bigint generated always as identity primary key,
  ip  text,
  ok  boolean not null,
  at  timestamptz not null default now()
);
alter table public.dash_auth           enable row level security;
alter table public.dash_login_attempts enable row level security;
revoke all on public.dash_auth, public.dash_login_attempts from anon, authenticated;

-- ---------- 2. functions ----------
-- sets / changes the password and invalidates every existing pass (only callable from the SQL editor)
create or replace function public.dash_set_password(new_pw text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new_pw is null or length(new_pw) < 8 then raise exception 'Password must be at least 8 characters'; end if;
  if new_pw = 'PUT-YOUR-PASSWORD-HERE' then raise exception 'Please replace the placeholder with your own password'; end if;
  update public.dash_auth
     set pw_hash = crypt(new_pw, gen_salt('bf', 10)),
         token_secret = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
         updated_at = now()
   where id = 1;
end $$;
revoke all on function public.dash_set_password(text) from public, anon, authenticated;

-- is a password configured? (lets the dashboard know whether to use server-side checking)
create or replace function public.dash_ready() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select pw_hash is not null from public.dash_auth where id = 1), false)
$$;

-- login: returns {ok:true, token, exp} or {ok:false[, locked:true]}
create or replace function public.dash_login(pw text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  hdr json; v_ip text; v_hash text; v_sec text; v_exp bigint; v_fail int; v_fail_all int;
begin
  begin hdr := nullif(current_setting('request.headers', true), '')::json; exception when others then hdr := null; end;
  v_ip := coalesce(hdr->>'cf-connecting-ip', trim(split_part(coalesce(hdr->>'x-forwarded-for',''), ',', 1)), '?');

  delete from public.dash_login_attempts where at < now() - interval '1 day';
  select count(*) into v_fail     from public.dash_login_attempts where not ok and ip = v_ip and at > now() - interval '10 minutes';
  select count(*) into v_fail_all from public.dash_login_attempts where not ok and at > now() - interval '10 minutes';
  if v_fail >= 8 or v_fail_all >= 200 then
    return jsonb_build_object('ok', false, 'locked', true);
  end if;

  select pw_hash, token_secret into v_hash, v_sec from public.dash_auth where id = 1;
  if v_hash is null or pw is null or crypt(pw, v_hash) <> v_hash then
    insert into public.dash_login_attempts (ip, ok) values (v_ip, false);
    perform pg_sleep(0.6);                                   -- slow down guessing
    return jsonb_build_object('ok', false);
  end if;

  insert into public.dash_login_attempts (ip, ok) values (v_ip, true);
  v_exp := extract(epoch from (now() + interval '12 hours'))::bigint;
  return jsonb_build_object('ok', true, 'exp', v_exp,
           'token', v_exp::text || '.' || encode(hmac(v_exp::text, v_sec, 'sha256'), 'hex'));
end $$;

-- used by the table policies: does this request carry a valid, unexpired pass?
create or replace function public.dash_ok() returns boolean
language plpgsql stable security definer set search_path = public, extensions as $$
declare hdr json; t text; v_sec text; v_exp bigint;
begin
  hdr := nullif(current_setting('request.headers', true), '')::json;
  t := hdr->>'x-flix-token';
  if t is null or position('.' in t) = 0 then return false; end if;
  v_exp := split_part(t, '.', 1)::bigint;
  if v_exp < extract(epoch from now()) then return false; end if;
  select token_secret into v_sec from public.dash_auth where id = 1;
  return v_sec is not null and split_part(t, '.', 2) = encode(hmac(split_part(t, '.', 1), v_sec, 'sha256'), 'hex');
exception when others then
  return false;
end $$;

grant execute on function public.dash_ready()          to anon, authenticated;
grant execute on function public.dash_login(text)      to anon, authenticated;
grant execute on function public.dash_ok()             to anon, authenticated;

-- ---------- 3. SET THE PASSWORD  <<< CHANGE THIS >>> ----------
select public.dash_set_password('PUT-YOUR-PASSWORD-HERE');

-- ---------- 4. lock the dashboard tables: a valid pass is required ----------
do $$
declare t text; pol record;
begin
  foreach t in array array['expansion_pairs','km_actuals','expansion_2027','crm_leads','crm_stage_history','crm_repurposing'] loop
    if to_regclass('public.' || t) is null then
      raise notice 'skipping % (table does not exist)', t; continue;
    end if;
    execute format('alter table public.%I enable row level security', t);
    for pol in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', pol.policyname, t);
    end loop;
    execute format('create policy "pass read"   on public.%I for select to anon using ((select public.dash_ok()))', t);
    execute format('create policy "pass insert" on public.%I for insert to anon with check ((select public.dash_ok()))', t);
    execute format('create policy "pass update" on public.%I for update to anon using ((select public.dash_ok())) with check ((select public.dash_ok()))', t);
    execute format('create policy "pass delete" on public.%I for delete to anon using ((select public.dash_ok()))', t);
    execute format('grant select, insert, update, delete on public.%I to anon', t);
  end loop;
end $$;
