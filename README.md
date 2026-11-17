# Audit Tracker — SFRS(I) & SSA

A single-page audit testing app for financial statements prepared under **SFRS(I)** and audited under **Singapore Standards on Auditing (SSA)**. Upload Excel workbooks, run automated audit tests, and track the resulting issues — ranked by risk and linked to the relevant SSA and SFRS(I) paragraphs.

Everything runs in the browser. Uploaded files are parsed locally and are never sent to a server; data is saved in the browser's `localStorage`.

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

## Deploying to Vercel

This is a static site — no build step.

1. In Vercel, choose **Add New → Project** and import `lohteekaya/audit_tracker`.
2. Framework preset: **Other**. Leave Build Command and Output Directory empty (Root Directory `./`).
3. Click **Deploy**.

`vercel.json` adds security headers, including a Content-Security-Policy that only allows the two external sources the app uses:
- `cdnjs.cloudflare.com` — SheetJS (`xlsx` 0.18.5) for reading Excel files
- `fonts.googleapis.com` / `fonts.gstatic.com` — IBM Plex fonts

Run locally by opening `index.html` in a browser, or with any static server, e.g. `npx serve .`

## Notes

- **Reference text is paraphrased** for quick reference and is not the authoritative wording. Confirm paragraphs against the ISCA Handbook (SSAs) and ASC pronouncements (SFRS(I)) before relying on them. SFRS(I) 18 replaces SFRS(I) 1-1 for annual periods beginning on or after 1 January 2027.
- **Data is per browser.** `localStorage` is not shared across devices or users. Use *Engagement → Copy backup (JSON)* to move data, and *Copy issues as CSV* to export.
- Default materiality is S$250,000 (PM 75%, clearly trivial 5%) — set your own on the Engagement page and re-run tests.
