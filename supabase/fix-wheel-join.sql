-- Wheel registration error repair.
-- Run from your Supabase project's SQL Editor, not GitHub.
-- If public.employees or public.wheel_plays is missing, first run
-- supabase/install-both-games.sql (full database installer).
begin;
create or replace function public.wheel_join(p_id text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  eid text := upper(btrim(p_id));
  nm text := btrim(p_name);
  existing_name text;
  previous_prize text;
begin
  if eid is null or eid !~ '^[A-Z0-9_-]{2,40}$'
     or nm is null or char_length(nm) not between 2 and 100 then
    raise exception 'Enter a valid full name and Employee ID';
  end if;
  perform pg_advisory_xact_lock(hashtext('employee:' || eid));
  insert into public.employees(employee_id, name)
    values(eid,nm) on conflict(employee_id) do nothing;
  select name into existing_name from public.employees where employee_id=eid;
  if lower(existing_name) <> lower(nm) then
    raise exception 'Employee ID belongs to another name';
  end if;
  select prize_label into previous_prize
    from public.wheel_plays where employee_id=eid;
  return jsonb_build_object(
    'id',eid,'name',existing_name,
    'played',found,'prize',previous_prize
  );
end;
$function$;
revoke all on function public.wheel_join(text,text) from public;
grant execute on function public.wheel_join(text,text) to anon,authenticated;
commit;
notify pgrst, 'reload schema';
-- Verify function exists and the argument names match:
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='wheel_join';
