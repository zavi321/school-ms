-- ============================================================================
-- Locks teacher_attendance.date to the SERVER's own current date, no matter
-- what date value any client sends — the manual "Mark Attendance" screen,
-- the QR check-in RPC, or even someone calling the table's API directly
-- (e.g. via browser dev tools) with a hand-crafted request.
--
-- This is a trigger, not a client-side check, so it can't be bypassed by
-- editing the app's code or skipping the UI.
--
-- Adjust 'Asia/Karachi' if the school is in a different timezone (use the
-- SAME timezone as in checkin_mark_present.sql, so both paths agree on what
-- "today" means).
-- ============================================================================
create or replace function enforce_attendance_today_date()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Ignore whatever date the client sent — always use the server's own
  -- clock for what "today" is.
  NEW.date := (now() at time zone 'Asia/Karachi')::date;
  return NEW;
end;
$$;

drop trigger if exists trg_enforce_attendance_today_date on teacher_attendance;
create trigger trg_enforce_attendance_today_date
before insert or update on teacher_attendance
for each row
execute function enforce_attendance_today_date();
