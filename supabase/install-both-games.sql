-- SHARED SUPABASE INSTALLER: Execute ONCE in Supabase Dashboard > SQL Editor.
-- This installs BOTH games using shared employees/admins and separate settings.
-- Do not insert any secret passwords or service_role keys here.

-- Run in Supabase SQL Editor for Spin the Wheel.
create extension if not exists pgcrypto;
create table if not exists public.admins(user_id uuid primary key references auth.users(id) on delete cascade);
create table if not exists public.settings(id int primary key default 1 check(id=1),event_name text not null default 'Spin the Wheel',wheel_enabled boolean not null default true);
insert into public.settings(id) values(1) on conflict do nothing;
create table if not exists public.prizes(id uuid primary key default gen_random_uuid(),label text not null check(length(trim(label))>0),color text not null default '#8b5cf6',weight int not null default 1 check(weight>=0),enabled boolean not null default true,position int not null default 0);
insert into public.prizes(label,color,weight,position) select v.* from(values('Coffee Voucher','#f59e0b',25,0),('Gift Hamper','#8b5cf6',15,1),('Better Luck Next Time','#ec4899',35,2),('Movie Ticket','#06b6d4',15,3),('Surprise Gift','#10b981',10,4)) v where not exists(select 1 from public.prizes);
create table if not exists public.employees(employee_id text primary key,name text not null,created_at timestamptz default now());
create table if not exists public.wheel_plays(employee_id text primary key references public.employees(employee_id),employee_name text not null,prize_id uuid references public.prizes(id) on delete set null,prize_label text not null,played_at timestamptz not null default now());
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.admins where user_id=auth.uid())$$;
alter table public.admins enable row level security;
alter table public.settings enable row level security;
alter table public.prizes enable row level security;
alter table public.employees enable row level security;
alter table public.wheel_plays enable row level security;
drop policy if exists "admin select" on public.admins;
create policy "admin select" on public.admins for select to authenticated using(user_id=auth.uid());
drop policy if exists "public settings" on public.settings;
create policy "public settings" on public.settings for select to anon,authenticated using(true);
drop policy if exists "admin settings" on public.settings;
create policy "admin settings" on public.settings for update to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "public prizes" on public.prizes;
create policy "public prizes" on public.prizes for select to anon,authenticated using(true);
drop policy if exists "admin prizes" on public.prizes;
create policy "admin prizes" on public.prizes for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "admin employees" on public.employees;
create policy "admin employees" on public.employees for select to authenticated using(public.is_admin());
drop policy if exists "admin wheel plays" on public.wheel_plays;
create policy "admin wheel plays" on public.wheel_plays for select to authenticated using(public.is_admin());
create or replace function public.wheel_join(p_id text,p_name text) returns jsonb language plpgsql security definer set search_path=public as $$
declare eid text:=upper(trim(p_id)); nm text:=trim(p_name); emp public.employees%rowtype; old public.wheel_plays%rowtype;
begin
 if eid !~ '^[A-Z0-9_-]{2,40}$' or length(nm) not between 2 and 100 then raise exception 'Enter a valid name and Employee ID (letters/digits/_/-)';end if;
 perform pg_advisory_xact_lock(hashtext('employee:'||eid));
 insert into public.employees(employee_id,name) values(eid,nm) on conflict do nothing;
 select * into emp from public.employees where employee_id=eid;
 if lower(emp.name)<>lower(nm) then raise exception 'This Employee ID belongs to a different name';end if;
 select * into old from public.wheel_plays where employee_id=eid;
 return jsonb_build_object('id',eid,'name',emp.name,'played',old.employee_id is not null,'prize',old.prize_label);
end$$;
create or replace function public.wheel_spin(p_id text,p_name text) returns jsonb language plpgsql security definer set search_path=public as $$
declare eid text:=upper(trim(p_id)); nm text:=trim(p_name); picked public.prizes%rowtype; total int; n double precision; running int:=0;
begin
 perform pg_advisory_xact_lock(hashtext('wheel:'||eid));
 if not exists(select 1 from public.employees where employee_id=eid and lower(name)=lower(nm)) then raise exception 'Employee details not registered';end if;
 if not (select wheel_enabled from public.settings where id=1) then raise exception 'Game is closed';end if;
 if exists(select 1 from public.wheel_plays where employee_id=eid) then raise exception 'Already played. One spin per Employee ID';end if;
 select sum(weight) into total from public.prizes where enabled and weight>0;
 if coalesce(total,0)=0 then raise exception 'No active prizes';end if;
 n:=random()*total;
 for picked in select * from public.prizes where enabled and weight>0 order by position,id loop
 running:=running+picked.weight;
 if n<running then exit;end if;
 end loop;
 insert into public.wheel_plays(employee_id,employee_name,prize_id,prize_label) values(eid,nm,picked.id,picked.label);
 return jsonb_build_object('prize',picked.label,'prize_id',picked.id);
end$$;
create or replace function public.wheel_reset() returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admins only';end if;
 delete from public.wheel_plays;
end$$;
revoke all on function public.wheel_join(text,text),public.wheel_spin(text,text),public.wheel_reset(),public.is_admin() from public;
grant execute on function public.wheel_join(text,text),public.wheel_spin(text,text) to anon,authenticated;
grant execute on function public.wheel_reset(),public.is_admin() to authenticated;
-- After adding an admin in Supabase Authentication > Users, run:
-- insert into public.admins(user_id) values ('ADMIN_AUTH_UUID');

-- -------------- HOUSIE -----------------
-- Run in Supabase SQL Editor for Housie / Tambola.
create extension if not exists pgcrypto;
create table if not exists public.admins(user_id uuid primary key references auth.users(id) on delete cascade);
create table if not exists public.housie_settings(id int primary key default 1 check(id=1),event_name text not null default 'Housie / Tambola',housie_enabled boolean not null default true);
insert into public.housie_settings(id) values(1) on conflict do nothing;
create table if not exists public.employees(employee_id text primary key,name text not null,created_at timestamptz default now());
create table if not exists public.housie_tickets(employee_id text primary key references public.employees(employee_id),employee_name text not null,numbers int[] not null,created_at timestamptz default now());
create table if not exists public.housie_draws(number int primary key check(number between 1 and 90),drawn_at timestamptz default now());
create table if not exists public.housie_claims(category text primary key check(category in ('early5','top','middle','bottom','full')),employee_id text not null references public.employees(employee_id),employee_name text not null,claimed_at timestamptz default now());
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.admins where user_id=auth.uid())$$;
alter table public.admins enable row level security;
alter table public.housie_settings enable row level security;
alter table public.employees enable row level security;
alter table public.housie_tickets enable row level security;
alter table public.housie_draws enable row level security;
alter table public.housie_claims enable row level security;
drop policy if exists "admins view" on public.admins;
create policy "admins view" on public.admins for select to authenticated using(user_id=auth.uid());
drop policy if exists "public settings" on public.housie_settings;
create policy "public settings" on public.housie_settings for select to anon,authenticated using(true);
drop policy if exists "admin settings" on public.housie_settings;
create policy "admin settings" on public.housie_settings for update to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "admin employees" on public.employees;
create policy "admin employees" on public.employees for select to authenticated using(public.is_admin());
drop policy if exists "admin tickets" on public.housie_tickets;
create policy "admin tickets" on public.housie_tickets for select to authenticated using(public.is_admin());
drop policy if exists "public draws" on public.housie_draws;
create policy "public draws" on public.housie_draws for select to anon,authenticated using(true);
drop policy if exists "admin draws" on public.housie_draws;
create policy "admin draws" on public.housie_draws for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "public claims" on public.housie_claims;
create policy "public claims" on public.housie_claims for select to anon,authenticated using(true);
drop policy if exists "admin claims" on public.housie_claims;
create policy "admin claims" on public.housie_claims for all to authenticated using(public.is_admin()) with check(public.is_admin());
create or replace function public.housie_join(p_id text,p_name text) returns jsonb language plpgsql security definer set search_path=public as $$
declare eid text:=upper(trim(p_id));nm text:=trim(p_name);emp public.employees%rowtype;ticket int[];row1 int[];row2 int[];row3 int[];
begin
 if eid !~ '^[A-Z0-9_-]{2,40}$' or length(nm) not between 2 and 100 then raise exception 'Enter valid Employee ID and full name';end if;
 perform pg_advisory_xact_lock(hashtext('employee:'||eid));
 insert into public.employees(employee_id,name) values(eid,nm) on conflict do nothing;
 select * into emp from public.employees where employee_id=eid;
 if lower(emp.name)<>lower(nm) then raise exception 'Employee ID belongs to another name';end if;
 select numbers into ticket from public.housie_tickets where employee_id=eid;
 if ticket is null then
  if not(select housie_enabled from public.housie_settings where id=1) then raise exception 'New tickets are closed';end if;
  select array_agg(n order by n) into row1 from (select n from generate_series(1,30) n order by random() limit 5) a;
  select array_agg(n order by n) into row2 from (select n from generate_series(31,60) n order by random() limit 5) a;
  select array_agg(n order by n) into row3 from (select n from generate_series(61,90) n order by random() limit 5) a;
  ticket:=row1||row2||row3;
  insert into public.housie_tickets(employee_id,employee_name,numbers) values(eid,emp.name,ticket);
 end if;
 return jsonb_build_object('id',eid,'name',emp.name,'numbers',ticket);
end$$;
create or replace function public.housie_draw() returns jsonb language plpgsql security definer set search_path=public as $$
declare pick int;
begin
 if not public.is_admin() then raise exception 'Admin only';end if;
 perform pg_advisory_xact_lock(7890345);
 select n into pick from generate_series(1,90)n where not exists(select 1 from public.housie_draws d where d.number=n) order by random() limit 1;
 if pick is null then raise exception 'All 90 numbers called';end if;
 insert into public.housie_draws(number) values(pick);
 return jsonb_build_object('number',pick);
end$$;
create or replace function public.housie_claim(p_id text,p_name text,p_category text) returns jsonb language plpgsql security definer set search_path=public as $$
declare eid text:=upper(trim(p_id));t public.housie_tickets%rowtype;required int[];matched int;target int;
begin
 if p_category not in ('early5','top','middle','bottom','full') then raise exception 'Invalid claim';end if;
 perform pg_advisory_xact_lock(hashtext('claim:'||p_category));
 select * into t from public.housie_tickets where employee_id=eid and lower(employee_name)=lower(trim(p_name));
 if not found then raise exception 'Ticket not found';end if;
 if exists(select 1 from public.housie_claims where category=p_category) then raise exception 'Prize category already claimed';end if;
 if p_category='top' then required:=t.numbers[1:5];target:=5;
 elsif p_category='middle' then required:=t.numbers[6:10];target:=5;
 elsif p_category='bottom' then required:=t.numbers[11:15];target:=5;
 elsif p_category='full' then required:=t.numbers;target:=15;
 else required:=t.numbers;target:=5;
 end if;
 select count(*) into matched from unnest(required)n where exists(select 1 from public.housie_draws where number=n);
 if matched<target then raise exception 'Not eligible yet. Matched % of %',matched,target;end if;
 insert into public.housie_claims(category,employee_id,employee_name) values(p_category,eid,t.employee_name);
 return jsonb_build_object('message','Claim accepted! Admin will verify your identity.');
end$$;
create or replace function public.housie_reset() returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin only';end if;
 delete from public.housie_claims;
 delete from public.housie_draws;
 delete from public.housie_tickets;
end$$;
revoke all on function public.is_admin(),public.housie_join(text,text),public.housie_draw(),public.housie_claim(text,text,text),public.housie_reset() from public;
grant execute on function public.housie_join(text,text),public.housie_claim(text,text,text) to anon,authenticated;
grant execute on function public.housie_draw(),public.housie_reset(),public.is_admin() to authenticated;
-- Create admin in Authentication > Users, then:
-- insert into public.admins(user_id) values ('ADMIN_AUTH_UUID');
