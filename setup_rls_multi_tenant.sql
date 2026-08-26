-- ============================================================================
-- Multi-Tenant Security Setup (Row Level Security)
-- Run this ONCE in Supabase Dashboard → SQL Editor → New Query → Run
-- ============================================================================
-- Why this matters:
-- The app's frontend code queries every table with `select('*')` and relies
-- entirely on RLS to filter results to the logged-in school's own data.
-- WITHOUT these policies, every school using the app can see and edit
-- every other school's students, fees, contacts, salaries, and finances.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. Auto-create a "profiles" row when a new school signs up
-- ---------------------------------------------------------------------------
-- When someone signs up, the app passes school_name as auth metadata.
-- This trigger copies that into the profiles table automatically.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, school_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'school_name', 'My School'))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ---------------------------------------------------------------------------
-- 2. Enable Row Level Security on every table
-- ---------------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.students        enable row level security;
alter table public.fee_payments    enable row level security;
alter table public.teachers        enable row level security;
alter table public.salary_payments enable row level security;
alter table public.transactions    enable row level security;


-- ---------------------------------------------------------------------------
-- 3. profiles: a school can only see/edit its own profile row
-- ---------------------------------------------------------------------------
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);


-- ---------------------------------------------------------------------------
-- 4. All owner_id tables: full access only to rows owned by the logged-in
--    user (school). One policy per table covers select/insert/update/delete.
-- ---------------------------------------------------------------------------
drop policy if exists "students_owner_all" on public.students;
create policy "students_owner_all" on public.students
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "fee_payments_owner_all" on public.fee_payments;
create policy "fee_payments_owner_all" on public.fee_payments
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "teachers_owner_all" on public.teachers;
create policy "teachers_owner_all" on public.teachers
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "salary_payments_owner_all" on public.salary_payments;
create policy "salary_payments_owner_all" on public.salary_payments
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "transactions_owner_all" on public.transactions;
create policy "transactions_owner_all" on public.transactions
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);


-- ---------------------------------------------------------------------------
-- 5. Indexes on owner_id — keeps queries fast as more schools sign up
-- ---------------------------------------------------------------------------
create index if not exists idx_students_owner        on public.students(owner_id);
create index if not exists idx_fee_payments_owner     on public.fee_payments(owner_id);
create index if not exists idx_teachers_owner         on public.teachers(owner_id);
create index if not exists idx_salary_payments_owner  on public.salary_payments(owner_id);
create index if not exists idx_transactions_owner     on public.transactions(owner_id);

-- ============================================================================
-- Done. After running this, test with TWO separate school accounts:
-- sign up as School A, add a student, log out, sign up as School B —
-- School B must NOT see School A's student.
-- ============================================================================
