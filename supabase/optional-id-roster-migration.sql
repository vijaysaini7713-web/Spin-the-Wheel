-- Employee directory / optional Employee ID migration for BOTH games.
-- Prerequisite: run supabase/install-both-games.sql once, then this migration,
-- then the PRIVATE staff-roster import file. Roster is NOT committed to GitHub.
-- Never expose employee_directory to anon users via table SELECT.
begin;
create table if not exists public.employee_directory (
 email text primary key,
 full_name text not null,
 job_title text,
 department text,
 office_location text,
 active boolean not null default true,
 updated_at timestamptz not null default now(),
 constraint directory_email_lower check(email=lower(btrim(email)))
);
alter table public.employee_directory enable row level security;
drop policy if exists "admins can read roster" on public.employee_directory;
create policy "admins can read roster" on public.employee_directory
 for select to authenticated using (public.is_admin());
revoke all on public.employee_directory from anon,authenticated;
grant select on public.employee_directory to authenticated;
alter table public.employees add column if not exists email text;
alter table public.employees add column if not exists staff_code text;
create unique index if not exists employees_email_unique on public.employees(lower(email)) where email is not null;
create unique index if not exists employees_staff_code_unique on public.employees(staff_code) where staff_code is not null;

create or replace function public.roster_identity(p_name text,p_email text,p_employee_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 nm text:=btrim(coalesce(p_name,''));
 mail text:=lower(btrim(coalesce(p_email,'')));
 code text:=nullif(upper(btrim(coalesce(p_employee_id,''))),'');
 canonical_name text;
 person public.employees%rowtype;
 eid text;
begin
 if char_length(nm) not between 2 and 100 or mail !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
  raise exception 'Enter your full name and a valid work email';
 end if;
 if code is not null and code !~ '^[A-Z0-9_-]{2,40}$' then
  raise exception 'Optional Employee ID must contain 2-40 letters, digits, _ or -';
 end if;
 select full_name into canonical_name from public.employee_directory
 where email=mail and active=true;
 if canonical_name is null then raise exception 'Email not found in authorized employee list';end if;
 if regexp_replace(lower(btrim(canonical_name)),'[[:space:]]+',' ','g') <>
    regexp_replace(lower(nm),'[[:space:]]+',' ','g') then
  raise exception 'Name and work email do not match the employee directory';
 end if;
 eid:='E-'||upper(md5(mail));
 perform pg_advisory_xact_lock(hashtext('employee:'||mail));
 insert into public.employees(employee_id,name,email,staff_code)
 values(eid,canonical_name,mail,code)
 on conflict(employee_id) do nothing;
 select * into person from public.employees where employee_id=eid;
 if person.email is distinct from mail then raise exception 'Employee identity conflict';end if;
 if code is not null then
   if person.staff_code is not null and person.staff_code<>code then
     raise exception 'Employee ID differs from previously registered value';
   end if;
   update public.employees set staff_code=coalesce(staff_code,code)
   where employee_id=eid;
 end if;
 return jsonb_build_object('id',eid,'name',canonical_name,'email',mail,'staff_code',code);
end$$;
revoke all on function public.roster_identity(text,text,text) from public,anon,authenticated;

create or replace function public.wheel_join_roster(p_name text,p_email text,p_employee_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare employee jsonb; previous public.wheel_plays%rowtype;
begin
 employee:=public.roster_identity(p_name,p_email,p_employee_id);
 select * into previous from public.wheel_plays where employee_id=employee->>'id';
 return employee||jsonb_build_object(
  'played',previous.employee_id is not null,
  'prize',previous.prize_label
 );
end$$;

create or replace function public.housie_join_roster(p_name text,p_email text,p_employee_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare employee jsonb;ticket int[];row1 int[];row2 int[];row3 int[];
begin
 employee:=public.roster_identity(p_name,p_email,p_employee_id);
 perform pg_advisory_xact_lock(hashtext('ticket:'||(employee->>'id')));
 select numbers into ticket from public.housie_tickets where employee_id=employee->>'id';
 if ticket is null then
  if not(select housie_enabled from public.housie_settings where id=1) then
   raise exception 'Housie registration is closed';
  end if;
  select array_agg(n order by n) into row1 from
    (select n from generate_series(1,30) n order by random() limit 5) t;
  select array_agg(n order by n) into row2 from
    (select n from generate_series(31,60) n order by random() limit 5) t;
  select array_agg(n order by n) into row3 from
    (select n from generate_series(61,90) n order by random() limit 5) t;
  ticket:=row1||row2||row3;
  insert into public.housie_tickets(employee_id,employee_name,numbers)
  values(employee->>'id',employee->>'name',ticket);
 end if;
 return employee||jsonb_build_object('numbers',ticket);
end$$;

-- Disable the old unrestricted enrollment RPCs to prevent bypassing roster checks.
revoke execute on function public.wheel_join(text,text) from public,anon,authenticated;
revoke execute on function public.housie_join(text,text) from public,anon,authenticated;
revoke all on function public.wheel_join_roster(text,text,text) from public;
revoke all on function public.housie_join_roster(text,text,text) from public;
grant execute on function public.wheel_join_roster(text,text,text) to anon,authenticated;
grant execute on function public.housie_join_roster(text,text,text) to anon,authenticated;
commit;
notify pgrst,'reload schema';
-- Diagnostic:
select routine_name from information_schema.routines
where routine_schema='public' and routine_name in
('wheel_join_roster','housie_join_roster','wheel_spin','housie_claim');
