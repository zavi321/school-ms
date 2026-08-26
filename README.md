# School Finance & Records

A single-page web app for school fee, salary, and finance management —
built with vanilla HTML/JS + [Supabase](https://supabase.com) (auth + database).
Designed as a multi-tenant SaaS: each school signs up and only sees its own data.

## Features
- Student records (name, father's name, class, fee type, contact)
- Fee collection with auto WhatsApp receipt to parents
- Teacher salary tracking
- Income/expense (other transactions) tracking
- Dashboard, reports, printable fee cards & receipts
- Excel backup export (`.xlsx`)
- English / Urdu language toggle
- PWA-ready (installable, offline shell via `manifest.json` + `sw.js`)

## Setup

1. Create a [Supabase](https://supabase.com) project.
2. Run `setup_rls_multi_tenant.sql` in the Supabase SQL Editor — this enables
   Row Level Security so each school's data stays isolated from every other
   school. **Do not skip this step before onboarding real schools.**
3. In `index.html`, set:
   ```js
   const SUPABASE_URL = "...";
   const SUPABASE_ANON_KEY = "...";
   ```
   The anon/publishable key is safe to expose in client-side code — it's
   protected by the RLS policies from step 2.
4. (Optional) SMS gateway — set `SENDPK_API_KEY` / `SENDPK_SENDER` if using
   SendPK bulk SMS. Leave as placeholders to skip; the app still opens
   WhatsApp with a pre-filled message on payment (no key required).
5. Serve `index.html` from any static host (Netlify, Vercel, GitHub Pages, etc).

## Database tables expected
`profiles`, `students`, `fee_payments`, `teachers`, `salary_payments`, `transactions`
— each row-level-scoped by `owner_id` (except `profiles`, keyed by `id = auth.uid()`).

## Security note
This app relies entirely on Supabase RLS for data isolation between schools.
Always verify `setup_rls_multi_tenant.sql` has been run and test with two
separate accounts before going live.

## License
© 2026 Zavi Software. All rights reserved. This is proprietary software —
see [LICENSE](./LICENSE). It is licensed for use by subscribing schools
through their own hosted account only. It may not be copied, resold,
redistributed, or transferred to any other party. **Do not make this
repository public and do not share the raw source files with customers**
— schools should only ever access the app through your hosted URL/login,
never receive the `.html` file itself.
