-- ============================================================================
-- 1. New table: every scan attempt gets logged here — successful or not —
--    so the principal can see the full activity, not just who ended up present.
-- ============================================================================
create table if not exists checkin_attempts (
  id           bigint generated always as identity primary key,
  owner_id     uuid not null,
  teacher_id   uuid,
  teacher_name text,
  result       text not null,        -- 'ok' | 'already' | 'closed' | 'invalid'
  created_at   timestamptz not null default now()
);

alter table checkin_attempts enable row level security;

-- Principals can only ever see their OWN school's attempts.
drop policy if exists "owners can view own checkin attempts" on checkin_attempts;
create policy "owners can view own checkin attempts"
  on checkin_attempts for select
  using (owner_id = auth.uid());

grant select on checkin_attempts to authenticated;

-- ============================================================================
-- 2. Replaces checkin_mark_present so that:
--      1. Date and time-of-day come from the SERVER's own clock only —
--         never from anything the phone/browser sends — so no one can fake
--         the date or "backdate" a check-in.
--      2. Check-in is only accepted between 07:00 and 14:00 (school hours).
--         A scan at 5pm (or any other time outside this window) is rejected.
--      3. Each teacher can be marked present only ONCE per day. A second scan
--         the same day returns 'already' instead of overwriting anything.
--      4. Every attempt (successful or not) is logged to checkin_attempts.
--
--    Adjust 'Asia/Karachi' below if the school is in a different timezone.
--    Adjust the parameter types (uuid) if your existing function uses text —
--    check Database > Functions in Supabase to confirm the current types
--    before running this, so CREATE OR REPLACE actually replaces it instead
--    of creating a second, separate function.
-- ============================================================================
create or replace function checkin_mark_present(p_token uuid, p_teacher_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id     uuid;
  v_teacher_name text;
  v_local        timestamp;
  v_date         date;
  v_time         time;
  v_rows         int;
  v_result       text;
begin
  -- Which school does this QR token belong to?
  select owner_id into v_owner_id
  from checkin_tokens
  where token = p_token;

  if v_owner_id is null then
    -- Unknown token — not tied to any school, so there's nowhere to log this.
    return 'invalid';
  end if;

  -- Make sure this teacher actually belongs to that school.
  select name into v_teacher_name
  from teachers
  where id = p_teacher_id and owner_id = v_owner_id;

  if v_teacher_name is null then
    insert into checkin_attempts (owner_id, teacher_id, teacher_name, result)
    values (v_owner_id, p_teacher_id, null, 'invalid');
    return 'invalid';
  end if;

  -- Server's own clock — the only source of truth for date/time.
  v_local := now() at time zone 'Asia/Karachi';
  v_date  := v_local::date;
  v_time  := v_local::time;

  if v_time < time '07:00' or v_time > time '14:00' then
    insert into checkin_attempts (owner_id, teacher_id, teacher_name, result)
    values (v_owner_id, p_teacher_id, v_teacher_name, 'closed');
    return 'closed';
  end if;

  insert into teacher_attendance (owner_id, teacher_id, date, status, checked_in_at)
  values (v_owner_id, p_teacher_id, v_date, 'present', now())
  on conflict (teacher_id, date) do nothing;

  get diagnostics v_rows = row_count;

  if v_rows > 0 then
    v_result := 'ok';
  else
    v_result := 'already';
  end if;

  insert into checkin_attempts (owner_id, teacher_id, teacher_name, result)
  values (v_owner_id, p_teacher_id, v_teacher_name, v_result);

  return v_result;
end;
$$;

-- Keep the public check-in page (no login) able to call this:
grant execute on function checkin_mark_present(uuid, uuid) to anon;
