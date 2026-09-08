-- Run this once in Supabase → SQL Editor.
--
-- Updates class_add_student to also accept and store the student's
-- father_name, and return it so the class portal's local session can
-- show it immediately without a re-login.
--
-- The return type is changing (an extra father_name column), so the
-- old function must be dropped first — Postgres won't let CREATE OR
-- REPLACE change a function's OUT columns in place.

drop function if exists class_add_student(text, text, text, text);

create or replace function class_add_student(
  p_school_code text,
  p_login_id text,
  p_password text,
  p_name text,
  p_father_name text default null
)
returns table (
  id uuid,
  name text,
  father_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_class text;
  v_new_id uuid;
begin
  select cl.owner_id, cl.class_name
    into v_owner, v_class
  from class_logins cl
  join profiles p on p.id = cl.owner_id
  where upper(p.school_code) = upper(p_school_code)
    and cl.login_id = p_login_id
    and cl.password = p_password;

  if v_owner is null then return; end if;
  if coalesce(trim(p_name), '') = '' then return; end if;

  insert into students (owner_id, name, father_name, class_name, student_type, monthly_fee, admission_date, status)
  values (v_owner, trim(p_name), nullif(trim(p_father_name), ''), v_class, 'paying', 0, current_date, 'active')
  returning students.id into v_new_id;

  return query select v_new_id, trim(p_name), nullif(trim(p_father_name), '');
end;
$$;

grant execute on function class_add_student(text, text, text, text, text) to anon;
