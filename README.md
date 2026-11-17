# Audit Tracker — SFRS(I) & SSA

A single-page audit testing app for financial statements prepared under **SFRS(I)** and audited under **Singapore Standards on Auditing (SSA)**. Upload Excel workbooks, run automated audit tests, and track the resulting issues — ranked by risk and linked to the relevant SSA and SFRS(I) paragraphs.

Excel files are parsed in the browser. Users sign in with Supabase Auth, and engagements, workbooks and issues are stored in Supabase so the whole team works on the same data.

## Features

- **Issue tracker** — each exception gets an amount, a likelihood (1–5) and an impact (1–5, scaled to materiality per SSA 320), giving a risk level (Significant / High / Medium / Low) and priority (P1–P4). Risk matrix and exposure-by-category on the Overview page.
- **Location of each issue** — file › sheet › cell references, with a source view that highlights the exact cells.
- **SSA / SFRS(I) linkage** — every issue cites the relevant paragraphs, with the paragraph text highlighted; a Standards library shows which issues link to each paragraph.
- **Excel upload** — `.xlsx`, `.xls`, `.xlsm`, `.csv`. Detects trial balances, financial statements (current / prior year columns) and general ledgers.

### Tests performed

| Test | Main references |
|---|---|
| Trial balance agrees (Dr = Cr) | SSA 500 ¶9, SSA 330 ¶20 |
| Casting of total lines | SSA 500 ¶6, SSA 330 ¶20, SSA 450 ¶5 |
| Statement of financial position balances | SSA 330 ¶20, SSA 450 ¶11 |
| Journal entries balance by reference | SSA 330 ¶20, SSA 240 ¶32(a) |
| Duplicate postings | SSA 500 ¶9, SSA 240 ¶32(a) |
| Large round-sum entries (≥ PM) | SSA 240 ¶31, ¶32(a) |
| Weekend postings | SSA 240 ¶32(a) |
| Entries dated after year end | SSA 560 ¶6, SFRS(I) 1-10 |
| Large revenue entries near year end | SSA 240 ¶26, SFRS(I) 15 |
| Incomplete records | SSA 500 ¶9 |
| Related party indicators | SSA 550 ¶15, ¶23, SFRS(I) 1-24 |
| Material accounting estimates | SSA 540 ¶32, SSA 240 ¶32(b) |
| Abnormal balance signs | SSA 330 ¶18, SFRS(I) 1-1 ¶32, ¶66 |
| Year-on-year fluctuations | SSA 520 ¶5, ¶7 |

## Users and sign-in

- Users sign in with a **username** and password. Passwords are held only by Supabase Auth (`auth.users`); the app never stores them.
- Under the hood a username maps to the Auth email `<username>@audit-tracker.example.com` (a reserved domain — no mail is ever sent).
- **Admins** add users and set their initial password on the **Users** page, and can reset passwords, change roles, and deactivate or delete accounts. Users are prompted to choose their own password after signing in with an initial one.
- **Roles:** `admin` (everything, plus user management and deleting engagements) and `auditor` (upload, test and work on issues in every engagement).
- Seed users: `miki` (admin) and `wee` (auditor), both with the initial password given at setup.

## Supabase

Project: `https://lopnwzfwsncisulpdbuo.supabase.co`. The browser uses only the **publishable key**; all access is enforced by row-level security.

| Object | Purpose |
|---|---|
| `auth.users` | Supabase Auth accounts and passwords |
| `public.profiles` | One row per auth user: username, display name, role, active, must-change-password flag (created by trigger `on_auth_user_created`) |
| `public.engagements` | Engagement name, settings (materiality, FYE, currency) and issue-number sequence |
| `public.workbooks` | Uploaded workbooks: detected columns, test results and up to 3,000 rows per sheet for the source view |
| `public.issues` | Issues with amount, risk inputs, SSA / SFRS(I) references, location, status, owner and notes |
| `public.reserve_issue_refs()` | Hands out AT-### numbers atomically so two users never get the same number |
| Edge function `admin-users` | Admin-only user management (list / create / reset password / update / delete) using the service role on the server |

RLS summary: only **active** users can read or write engagements, workbooks and issues; only admins can delete engagements; users can change only their own display name and password flag; role and active status change only through the edge function. Self sign-ups (if left enabled) get an inactive profile and no data access.

Source for the schema and the function is in `supabase/migrations` and `supabase/functions/admin-users`.

**Recommended in the Supabase dashboard:** Authentication → Sign In / Providers → turn off *Allow new users to sign up*, and enable *Leaked password protection* (Authentication → Passwords).

## Deploying to Vercel

This is a static site — no build step.

1. In Vercel, choose **Add New → Project** and import `lohteekaya/audit_tracker`.
2. Framework preset: **Other**. Leave Build Command and Output Directory empty (Root Directory `./`).
3. Click **Deploy**.

`vercel.json` adds security headers, including a Content-Security-Policy that only allows the external sources the app uses:
- `cdnjs.cloudflare.com` — SheetJS (`xlsx` 0.18.5) for reading Excel files
- `cdn.jsdelivr.net` — `@supabase/supabase-js` 2.119.0
- `lopnwzfwsncisulpdbuo.supabase.co` — Supabase Auth, database and edge functions
- `fonts.googleapis.com` / `fonts.gstatic.com` — IBM Plex fonts

Run locally by opening `index.html` in a browser, or with any static server, e.g. `npx serve .`

## Notes

- **Reference text is paraphrased** for quick reference and is not the authoritative wording. Confirm paragraphs against the ISCA Handbook (SSAs) and ASC pronouncements (SFRS(I)) before relying on them. SFRS(I) 18 replaces SFRS(I) 1-1 for annual periods beginning on or after 1 January 2027.
- **Shared data.** Every active user sees every engagement. Edits save automatically (header shows *Saved*); if two people edit the same issue at once, the last save wins. *Reload data* in the account menu pulls the latest changes.
- **Earlier browser-only data** (from before sign-in was added) is offered for one-click import into a new engagement on the Overview page.
- Default materiality is S$250,000 (PM 75%, clearly trivial 5%) — set your own on the Engagement page and re-run tests.
