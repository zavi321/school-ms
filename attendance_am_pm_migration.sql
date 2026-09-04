-- ============================================================================
-- Teacher Attendance Register — Morning/Afternoon (2-scan) migration
-- Run this once in your Supabase project's SQL Editor.
-- Back up your `teacher_attendance` table first (Table Editor -> export CSV)
-- since this changes a live table and replaces a live function.
-- ============================================================================

-- 1) New columns: separate status + scan time for each session, per day.
--    Existing `status` / `checked_in_at` columns are kept as-is for backward
--    compatibility (the app keeps writing a combined `status` automatically).
alter table teacher_attendance
  add column if not exists status_am text,
  add column if not exists status_pm text,
  add column if not exists checked_in_at_am timestamptz,
  add column if not exists checked_in_at_pm timestamptz;

-- Best-effort: treat any existing single check-in as the morning scan.
update teacher_attendance
set checked_in_at_am = checked_in_at,
    status_am = status
where checked_in_at_am is null and checked_in_at is not null;

-- 2) Replace the check-in function so a scan is recorded into the correct
--    session (Morning until 12:00, Afternoon 12:00–2:00 PM), and a second
--    scan does not overwrite the first.
--
--    Window: 7:00 AM – 2:00 PM (matches the existing "checkinOutsideWindow"
--    message already in the app). Adjust the two `time '...'` literals below
--    if your school's actual timing is different.
--
--    NOTE: This is a from-scratch reconstruction that matches what the app
--    already expects back ('ok' | 'already' | 'closed' | 'invalid') — I could
--    not read your existing function's source from here. Please review it
--    (especially the timezone) before relying on it, and test with one
--    teacher first.
create or replace function checkin_mark_present(p_token text, p_teacher_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_school_tz text := 'Asia/Karachi';   -- change if your school is in a different timezone
  v_today date := (now() at time zone v_school_tz)::date;
  v_time time := (now() at time zone v_school_tz)::time;
  v_session text;
  v_existing record;
  v_new_status_am text;
  v_new_status_pm text;
  v_combined text;
begin
  select owner_id into v_owner from checkin_tokens where token = p_token;
  if v_owner is null then
    return 'invalid';
  end if;

  -- make sure the teacher actually belongs to this school
  if not exists (select 1 from teachers where id = p_teacher_id and owner_id = v_owner) then
    return 'invalid';
  end if;

  if v_time < time '07:00' then
    return 'closed';
  elsif v_time < time '12:00' then
    v_session := 'am';
  elsif v_time <= time '14:00' then
    v_session := 'pm';
  else
    return 'closed';
  end if;

  select * into v_existing from teacher_attendance
    where teacher_id = p_teacher_id and date = v_today and owner_id = v_owner;

  if v_session = 'am' then
    if v_existing.status_am is not null then
      return 'already';
    end if;
  else
    if v_existing.status_pm is not null then
      return 'already';
    end if;
  end if;

  v_new_status_am := case when v_session = 'am' then 'present' else v_existing.status_am end;
  v_new_status_pm := case when v_session = 'pm' then 'present' else v_existing.status_pm end;

  -- combined day status: leave beats everything, both-present -> present,
  -- both-known-but-not-both-present -> absent, otherwise still open (null)
  v_combined := case
    when v_new_status_am = 'leave' or v_new_status_pm = 'leave' then 'leave'
    when v_new_status_am is not null and v_new_status_pm is not null then
      case when v_new_status_am = 'present' and v_new_status_pm = 'present' then 'present' else 'absent' end
    else null
  end;

  insert into teacher_attendance (owner_id, teacher_id, date, status_am, status_pm, status, checked_in_at_am, checked_in_at_pm, checked_in_at)
  values (
    v_owner, p_teacher_id, v_today,
    v_new_status_am, v_new_status_pm, v_combined,
    case when v_session = 'am' then now() else v_existing.checked_in_at_am end,
    case when v_session = 'pm' then now() else v_existing.checked_in_at_pm end,
    coalesce(v_existing.checked_in_at, now())
  )
  on conflict (teacher_id, date) do update set
    status_am = excluded.status_am,
    status_pm = excluded.status_pm,
    status = excluded.status,
    checked_in_at_am = excluded.checked_in_at_am,
    checked_in_at_pm = excluded.checked_in_at_pm,
    checked_in_at = coalesce(teacher_attendance.checked_in_at, excluded.checked_in_at);

  return 'ok';
end;
$$;

-- checkin_get_teachers and checkin_tokens are unaffected by this change and
-- do not need to be modified.
