-- Migration: Upgrade fee_payments to a full fee-card ledger
-- (Last Balance / School Fee / Sports Fund / Admission Fee / Annual Exam Fee /
--  Total Dues / Total Paid / Balance / Receipt No / Date — like the paper fee card)
--
-- Run this in Supabase SQL Editor. Safe to run even if some columns already exist.

alter table fee_payments add column if not exists school_fee numeric not null default 0;
alter table fee_payments add column if not exists sports_fund numeric not null default 0;
alter table fee_payments add column if not exists admission_fee numeric not null default 0;
alter table fee_payments add column if not exists exam_fee numeric not null default 0;
alter table fee_payments add column if not exists receipt_no text;

-- Note: the existing "amount" column now represents "Total Paid" for that month's row.
-- "Last Balance" and "Total Dues" are calculated automatically by the app from the
-- running history of each student's rows, so no extra column is needed for those.
