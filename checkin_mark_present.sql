-- Replaces checkin_mark_present so that:
--   1. The date and time-of-day are taken from the SERVER's own clock only
--      (never from anything the phone/browser sends) — so no one can fake
--      the date or "backdate" a check-in.
--   2. Check-in is only accepted between 07:00 and 14:00 (school hours).
--      A scan at 5pm (or any other time outside this window) is rejected.
--   3. Each teacher can be marked present only ONCE per day. A second scan
--      the same day returns 'already' instead of overwriting anything.
--
-- Adjust 'Asia/Karachi' below if the school is in a different timezone.
-- Adjust the parameter types (uuid) if your existing function uses text —
-- check Database > Functions in Supabase to confirm the current types
-- before running this, so CREATE OR REPLACE actually replaces it instead
-- of creating a second, separate function.

create or replace function checkin_mark_present(p_token uuid, p_teacher_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
  v_local    timestamp;
  v_date     date;
  v_time     time;
  v_rows     int;
begin
  -- Which school does this QR token belong to?
  select owner_id into v_owner_id
  from checkin_tokens
  where token = p_token;

  if v_owner_id is null then
    return 'invalid';
  end if;

  -- Make sure this teacher actually belongs to that school.
  if not exists (
    select 1 from teachers
    where id = p_teacher_id and owner_id = v_owner_id
  ) then
    return 'invalid';
  end if;

  -- Server's own clock — this is the only source of truth for date/time.
  v_local := now() at time zone 'Asia/Karachi';
  v_date  := v_local::date;
  v_time  := v_local::time;

  if v_time < time '07:00' or v_time > time '14:00' then
    return 'closed';
  end if;

  insert into teacher_attendance (owner_id, teacher_id, date, status)
  values (v_owner_id, p_teacher_id, v_date, 'present')
  on conflict (teacher_id, date) do nothing;

  get diagnostics v_rows = row_count;

  if v_rows > 0 then
    return 'ok';
  else
    return 'already';
  end if;
end;
$$;

-- Keep the public check-in page (no login) able to call this:
grant execute on function checkin_mark_present(uuid, uuid) to anon;
