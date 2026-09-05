-- ============================================================================
-- Holidays table — for the Teacher Attendance Register
-- Run this once in your Supabase project's SQL Editor (separate from, and in
-- addition to, the earlier attendance_am_pm_migration.sql).
-- ============================================================================

create table if not exists holidays (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  date date not null,
  created_at timestamptz not null default now(),
  unique (owner_id, date)
);

alter table holidays enable row level security;

-- NOTE: this assumes the same "owner_id = auth.uid()" pattern your other
-- tables (teachers, students, etc.) already use. If your existing policies
-- use a different pattern, match that instead.
create policy "holidays_select_own" on holidays
  for select using (owner_id = auth.uid());
create policy "holidays_insert_own" on holidays
  for insert with check (owner_id = auth.uid());
create policy "holidays_delete_own" on holidays
  for delete using (owner_id = auth.uid());
