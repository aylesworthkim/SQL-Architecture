# SQL Database Documentation

Documentation and investigation notes for the Newk's SQL-PROD environment, plus the
source files behind the **SQL Server Documentation** app hosted on Cloudways.

## The documentation site

The deployed Cloudways app is generated from these files:

| File | Purpose |
|---|---|
| `SQL-PROD_Database_Documentation.html` | The generated documentation site |
| `dependencies_generated.js` | Object dependency graph powering the site |
| `*.rpt` | Raw SSMS dependency + query exports the site is built from |
| `convert_rpt_to_csvs.py` | Converts the `.rpt` exports into CSV |
| `create_jobs_doc.py` | Builds `SQL-PROD_Agent_Jobs_Documentation.xlsx` |

## Reference notes

- `KIM_CHEAT_SHEET.md` — day-to-day commands and box/server reference
- `SESSION_HANDOFF_NOTES.md` — environment + architecture handoff notes
- `how_to_repoll_labor.md` — labor repoll runbook
- `MealCard_SSMS_Import_Steps.md` — meal card import procedure
- `NEWKS-SAGE_discovery.ps1`, `vDC01_discovery.ps1` — VM/AD discovery scripts

## Investigation folders

Dated folders are self-contained investigations, each with its own SQL scripts and a
`SUMMARY.md`, `NOTES.md`, or `POSTMORTEM.md` writing up what was found. For example:

- `ssrs_outage_2026-04-30/` — SSRS outage postmortem
- `system_comp_pct_by_year_2026-08-17/` — system comp % history, incl. a broken
  `FN_GetCompingDate` and comp-flag history recovery
- `payroll_export_snowflake_handoff_2026-08-20/` — payroll export port to Snowflake

## Excluded from this repo

Deliberately kept out via `.gitignore` — see that file for the full list:

- `ovation_sample/` — raw Ovation guest survey export containing **customer PII**
  (names, phone numbers, email addresses)
- `list_freshconcepts.ps1` — contains a live SFTP password

Both still exist in the local working folder; they are just never committed.
Secrets elsewhere in these notes are redacted; real values live in the password manager.
