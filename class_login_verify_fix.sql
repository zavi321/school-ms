-- ============================================================================
-- FIX: class_login_verify referenced students.student_name and
-- students.class_admitted, but this app's actual `students` table uses
-- `name` and `class_name` (student_name/class_admitted belong to the
-- separate admission_register table). Re-run this to replace the function.
-- Also now excludes inactive students from the roster returned to the class
-- device, matching how the rest of the app treats status='inactive'.
-- ============================================================================

create or replace function class_login_verify(
  p_school_code text, p_login_id text, p_password text
) returns table (owner_id uuid, class_name text, students jsonb)
language plpgsql security definer as $$
declare v_owner uuid;
begin
  select p.id into v_owner from profiles p where p.school_code = p_school_code;
  if v_owner is null then return; end if;

  return query
  select cl.owner_id, cl.class_name,
    coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'roll_no', s.roll_no)
      order by s.roll_no) filter (where s.id is not null), '[]'::jsonb)
  from class_logins cl
  left join students s on s.owner_id = cl.owner_id and s.class_name = cl.class_name
    and coalesce(s.status, '') <> 'inactive'
  where cl.owner_id = v_owner and cl.login_id = p_login_id and cl.password = p_password
  group by cl.owner_id, cl.class_name;
end; $$;
