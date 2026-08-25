# Session Handoff Notes — April 7-10, 2026

Complete documentation of everything accomplished, discovered, and still pending across this multi-day session with Kim Aylesworth at Newk's Eatery.

---

## Kim's Role & Context
- Kim replaced Don Wilson (dwilson@newks.com) as the database/reporting manager at Newk's Eatery
- Don left without documentation — Kim inherited SQL-PROD, SSRS, dev-jan02 (Linux), and the entire Toast data pipeline
- Kim is building a modern reporting app at `C:\Users\KimAylesworth\OneDrive - Newk's Eatery\Desktop\Kim\toast_net_sales_app` (FastAPI + vanilla HTML/JS)
- The SQL database documentation project lives at `C:\Users\KimAylesworth\OneDrive - Newk's Eatery\Desktop\Kim\SQL DATABSE DOCUMENTATION`

---

## Infrastructure Map (discovered during this session)

### Servers
- **SQL-PROD (newks-sql)** — SQL Server hosting: dev_aloha, toast, contacts, Logging, ReportServer, DOMO, paytronix, and ~20 other databases
- **dev-jan02.nfc.local** — Linux (RHEL/Rocky 8) hosting Don's PHP Toast puller scripts + PostgreSQL 18 staging database
  - SSH: `ssh root@dev-jan02.nfc.local` (KeePass: "2025 - Post - Linux Dev Root")
  - PostgreSQL: `dev-jan02.nfc.local:5432` (KeePass: "PostgreSQL 18", user: postgres)
- **Cloudways** — Kim's toast_net_sales_app is deployed here, already connected to SQL-PROD

### Toast Sales Data Pipeline (complete flow)
```
Toast POS API (/orders/v2/ordersBulk)
    ↓ (PHP puller on dev-jan02, runs nightly ~00:31 CDT)
    ↓ verb=poll, noun=sales, hoursBack=26, storeGrouping=9, storeGroup=243
PostgreSQL staging (dev-jan02:5432, db=toast)
    ↓ (sp_copy_from_psql_devjan02 via [psql] linked server)
toast.dbo.hstCheck / hstItem / hstOrder / hstPayment / hstServiceCharges
    ↓ (sp_Update_Sold_Items_From_Check — merges items from temp)
    ↓ (sp_toast_update_guest_counts_from_items_sold — slow, unfiltered UPDATE)
    ↓ (sp_Update_Check_Discounts)
    ↓ (sp_toast_SalesDataByDayPart — builds rollup)
dev_aloha.dbo.tbl_SalesDataByDayPart
    ↓ (sp_rpt_Daily_Sales_FLash_Report reads from here)
SSRS Reports → Emailed via data-driven subscriptions
```

### Key PHP Script Location
- `/home/dwilson@nfc.local/projects/toast/index.php` — main Toast puller
- Uses: `--verb`, `--noun`, `--sDate`, `--eDate`, `--storeGrouping`, `--storeGroup`, `--hoursBack`
- Defaults: verb=poll, noun=all (BUG: noun=all crashes — use noun=sales), hoursBack=25
- Logs to: `Logging.dbo.php_logs` (channel: `newks/toast_read_api`) — NOT to file

### Second Toast Pipeline (separate, FTP-based)
- `/home/dwilson@nfc.local/projects/toast_reports/` — downloads CSV reports from Toast
- Runs independently, feeds different downstream tables
- New stores picked up automatically (no config needed)

---

## What We Built

### 1. Python Toast Puller (replaces SSH + PHP for repolls)
**Location:** `toast_net_sales_app/backend/toast_puller.py` + `toast_puller_db.py`

**Usage:**
```bash
# Web UI
cd backend && python toast_puller.py --serve
# Opens http://localhost:8001 (puller) and http://localhost:8001/health (dashboard)

# CLI
python toast_puller.py --store 1040 --date 2026-04-06
python toast_puller.py --store 1040 --start-date 2026-04-01 --end-date 2026-04-06
```

**Features:**
- Page size 100 (vs Don's 10) — 10x fewer API round trips
- Exponential backoff retry on 504 errors (2s, 4s, 8s, 16s, 32s — 5 attempts)
- Token refresh on 401
- Writes directly to SQL Server (skips PostgreSQL middle layer)
- DELETE + INSERT pattern (not MERGE — avoids duplicate issues)
- Deletes existing hstItem rows before merge to prevent field-mapping duplicates
- Auto-runs sp_toast_SalesDataByDayPart rollup at the end
- Store dropdown loads from vw_live_toast_stores
- Date range support

**Known issues still to fix:**
- Datetime overflow on some item VoidDate/SystemTime fields (partially fixed — needs more testing)
- String truncation on some order fields (partially fixed with _trunc() helper)
- Should NOT be run in parallel (same staging table race condition as PHP — serial only)

**Env vars needed in .env:**
```
TOAST_STANDARD_API_CLIENT_ID=...
TOAST_STANDARD_API_CLIENT_SECRET=...
ALOHA_SQL_SERVER=sql-prod
ALOHA_SQL_USERNAME=kaylesworth
ALOHA_SQL_PASSWORD=...
TOAST_SQL_DATABASE=toast
```

### 2. Pipeline Health Dashboard
**Location:** Built into toast_puller.py, accessible at http://localhost:8001/health

**Monitors:**
- SQL Agent job status (last 24h, configurable)
- Failed Table Builds (from Logging.dbo.Table_Builds)
- Toast poll errors (from Logging.dbo.php_logs, 400/500 level)
- Truncated polls — stores whose latest_close is suspiciously early (504 fingerprint)
- Aloha→Toast transition gaps — stores missing pre-Toast Aloha data in rollup
- Re-run buttons for common procs

### 3. Database Indexes (added April 9)
```sql
CREATE NONCLUSTERED INDEX IX_hstCheck_StoreDate ON toast.dbo.hstCheck (StoreNum, DateOfBusiness) WITH (ONLINE = ON);
CREATE NONCLUSTERED INDEX IX_hstOrder_StoreDate ON toast.dbo.hstOrder (StoreNum, DateOfBusiness) WITH (ONLINE = ON);
CREATE NONCLUSTERED INDEX IX_hstItem_StoreDate ON toast.dbo.hstItem (StoreNum, DateOfBusiness) WITH (ONLINE = ON);
```
Impact: Queries that took 5-10 minutes now take seconds.

### 4. SQL Agent Jobs Documentation
**File:** `SQL DATABSE DOCUMENTATION/SQL-PROD_Agent_Jobs_Documentation.xlsx`
5 sheets: Active Jobs, SSRS Subscriptions, Disabled Jobs, Maintenance Gaps, Failed Jobs

---

## What We Fixed

### New Store Onboarding — Rockwall TX (store 5002, Virtual Kitchen)
**Problem:** New Toast location not showing in SSRS reports
**Root causes found (6 config tables needed):**
1. `dev_aloha.dbo.gblstore` — INSERT new store row
2. `contacts.dbo.store.ToastLive` — UPDATE from 9999-01-31 to actual go-live date (2026-03-31)
3. `contacts.dbo.storetechnical` — INSERT with fkPOSTypeID=3 (Toast)
4. `contacts.dbo.internal_StoreGroupMembers` — Add to groups 243 (Toast puller), 192 (All Open), 8 (Franchise)
5. `toast.dbo.cfg_RestaurantService` — Add daypart mappings (Dinner=3, Off Hours=11)
6. `toast.dbo.hstItem.DayPartID` — UPDATE from NULL using cfg_RestaurantService mapping

**Additional findings:**
- SSRS dropdown populated by shared dataset `dsGroup` which queries `contacts.dbo.store JOIN storetechnical JOIN POSType`
- SSRS email subscriptions use DIFFERENT store groups than the Toast puller (192, 8, 79 vs 243)
- The SSRS report proc `sp_rpt_Daily_Sales_FLash_Report` requires labor data (INNER JOIN to #Labor) — stores without labor rows have blank R-Net

**Runbook saved to:** Memory file `new_toast_store_runbook.md`

### Toast API 504 Truncation Issue
**Problem:** Nightly cron hits Toast API 504 Gateway Timeouts mid-pagination, silently drops remaining pages for affected stores
**Root cause:** `lib/checks.php` line 72 catches the 504, logs error, returns — no retry logic
**Stores affected (found via log analysis):**
- 4/6/2026: stores 1011, 1040, 1148, 1187, 1197 (confirmed from Logging.dbo.php_logs errors)
- 4/6/2026: stores 1004 (Jan 2-3, Mar 14-21 — 10 dates)
- 4/6/2026: store 1094 (Jan 25, Jan 31)
**All repolled and fixed.**

**Detection query (fingerprint for truncated polls):**
```sql
SELECT DateOfBusiness, StoreNum, COUNT(*) AS checks,
    DATEADD(HOUR, -5, MAX(ClosedTime)) AS latest_close_cdt
FROM toast.dbo.hstCheck
WHERE DateOfBusiness = '<date>' AND Voided = 0 AND Deleted = 0
GROUP BY DateOfBusiness, StoreNum
HAVING CAST(DATEADD(HOUR, -5, MAX(ClosedTime)) AS DATE) = DateOfBusiness
    AND DATEPART(HOUR, DATEADD(HOUR, -5, MAX(ClosedTime))) < 19
    AND COUNT(*) > 20;
```

### Aloha→Toast Transition Data Gap
**Problem:** Stores 1017 (Huntsville) and 1069 (Little Rock) missing sales data from before their Toast go-live dates
**Root cause:** `sp_SalesDataByDayPart` (Aloha version) has an `EXCEPT` clause that removes ALL stores in storegroup 243 from the Aloha rollup — even for dates when they were still on Aloha
**Fix:** Temporarily removed from group 243, ran sp_SalesDataByDayPart for pre-Toast dates, re-added to group 243

### Parallel Repoll Race Condition
**Problem:** Running multiple PHP repolls in parallel causes silent data loss in hstItem
**Root cause:** All PHP processes share global staging tables (psql.public.hstitem_temp, toast.dbo.hstitem_temp). One process's trunc_temp_tables() call wipes another's in-progress data. Items are written to a temp table that gets truncated, but checks are written to a main table that survives.
**Symptom:** hstCheck.CheckCount updates correctly but hstItem.COUNT(DISTINCT CheckID) stays at old value → rollup NetSales is wrong
**Rule:** NEVER run repolls in parallel. Serial only. One at a time.

### MealCard Report
**Problem:** Monthly MealCard Adjustments for Payroll report showing blank
**Root causes:**
1. Data source `dscDevAloha` was broken (shared data source moved/renamed)
2. April data not imported into `paytronix.dbo.ManualAdjustment` (manual monthly process — ~20 rows imported on 1st of each month)
3. Two employees missing from `dev_aloha.dbo.MealCardsToAllPay` mapping (Reanne Burnett added with AllPayID 8309, Klara Smith still needs employee ID)
**No automated Paytronix import exists** — this is a manual CSV import process

### H: Drive Full / Backup Failures
**Problem:** T-Log backups failing every 15 minutes starting 4/10
**Root cause:** H: drive had only 20 MB free. `Backup Logging clean up.Subplan_1` job was DISABLED — old backup files accumulated.
**Fix:** Moved orphaned 54 GB `chabi` file (old database file, chabi DB no longer exists) from H: to D: drive
**Still pending:** Re-enable the cleanup job (Kim wants to discuss with boss first)

---

## Critical Gotchas Discovered

### hstCheck.OpenedTime / ClosedTime are UTC, not local
- Newk's stores are mostly Central (CDT = UTC-5, CST = UTC-6)
- A store opening at 10 AM CDT shows as 15:00 in OpenedTime
- A store closing at 9 PM CDT shows as 02:00 NEXT DAY in ClosedTime
- Red flag for incomplete poll: latest_close is on the SAME day as DateOfBusiness in UTC (= before 7 PM CDT)

### Don's PHP script noun=all bug
- `noun=all` in index.php causes `$storesTable` to be undefined → PHP fatal error at line 165
- The nightly cron uses explicit `noun=sales` and `noun=labor` separately
- Always use `--noun=sales` or `--noun=labor`, never `--noun=all`

### Store groups used by different systems
| Group ID | Name | Used by |
|---|---|---|
| 8 | All Franchise Restaurants (69 stores) | Daily Flash - Franchise email subscription |
| 79 | All Company Restaurants (28 stores) | Daily Flash - Corporate email subscription |
| 192 | All OPEN Restaurants (97 stores) | Daily Flash - All Open Stores email subscriptions |
| 243 | TR Historical (97 stores) | Toast PHP puller (dev-jan02 index.php) |

New stores need to be added to 243 + 192 + (8 OR 79 depending on franchise/corporate).

### sp_SalesDataByDayPart vs sp_toast_SalesDataByDayPart
- `sp_SalesDataByDayPart` — reads from `tbl_HstSalesByInterval` (ALOHA source). Has EXCEPT clause that removes Toast stores.
- `sp_toast_SalesDataByDayPart` — reads from `hstCheck`/`hstItem` (TOAST source). Takes @StartDate, @EndDate, @StoreGrouping, @StoreGroup.
- Both write to `tbl_SalesDataByDayPart` (the rollup table SSRS reads from).

### sp_rpt_Daily_Sales_FLash_Report R-Net requires labor data
- The "Net" tab INNER JOINs to #Labor table
- Stores without labor data in `tbl_LaborDataByDayPart` are silently excluded from R-Net
- Workaround for new stores: insert placeholder zero-labor rows with a valid JobCodeId (not in exclusion list: 1, 10, 11, 13, 55, 105, 900, 901, 902, 950, 975, 977, 998, 999)

---

## Pending Items

### High Priority
1. **Python puller datetime overflow fix** — needs testing on a store to verify VoidDate/SystemTime handling
2. **Repoll store 1129 on 2026-01-04** — confirmed 504 truncation (98 checks, closes 1 PM)
3. **Scan Feb-Mar for remaining 504 truncations** — only January was fully scanned
4. **Deploy puller + health dashboard to Cloudways** — confirmed Cloudways can reach SQL-PROD

### Medium Priority
5. **Fort Collins (1190) variance** — colleague flagged it, never investigated
6. **Klara Smith employee ID** — need from payroll for MealCard report
7. **Database maintenance jobs** — create index rebuild + statistics update jobs (documented in SQL-PROD_Agent_Jobs_Documentation.xlsx, "Maintenance Gaps" sheet)
8. **Re-enable backup cleanup job** — discuss with Kim's boss first
9. **Disable legacy CC56FA54 SSRS validation job** — references non-existent aloha database

### Low Priority / Future
10. **Test Python puller as nightly replacement** for Don's PHP cron (shadow mode)
11. **SSRS subscription resend UI** — trigger report emails from puller UI
12. **Data archiving strategy** — hstItem/hstCheck/hstOrder have years of data
13. **Modify sp_SalesDataByDayPart** to make EXCEPT clause date-aware (prevents Aloha→Toast transition gaps)
14. **Add retry logic to Don's PHP** `lib/checks.php` (or just replace with Python puller)

---

## Memory Files Saved (persist across conversations)

All in: `C:\Users\KimAylesworth\.claude\projects\C--Users-KimAylesworth-OneDrive---Newk-s-Eatery-Desktop-Kim-SQL-DATABSE-DOCUMENTATION\memory\`

- `MEMORY.md` — index of all memory files
- `user_role.md` — Kim's role context
- `kim_long_term_goals.md` — modernization goals, toast_net_sales_app
- `kim_cheat_sheet.md` — SSH, repoll commands, SSMS queries, common ops. INCLUDES "never run repolls in parallel" warning and UTC timestamp gotcha.
- `new_toast_store_runbook.md` — 13-step checklist for onboarding new Toast stores
- `toast_pipeline_infra.md` — full pipeline architecture reference
- `python_toast_puller_design.md` — design doc for Python puller
- `db_performance_plan.md` — index + statistics + archiving plan

---

## Key Credentials & Access (from KeePass)

- **SQL-PROD:** `kaylesworth` / (in .env on Cloudways and local)
- **dev-jan02 SSH:** root / KeePass "2025 - Post - Linux Dev Root"
- **dev-jan02 PostgreSQL:** postgres / KeePass "PostgreSQL 18"
- **Toast API:** TOAST_STANDARD_API_CLIENT_ID/SECRET in .env
- **SSRS Portal:** http://newks-sql/Reports

---

## Files Created/Modified This Session

### New files:
- `toast_net_sales_app/backend/toast_puller.py` — Python Toast puller with web UI
- `toast_net_sales_app/backend/toast_puller_db.py` — SQL Server write helpers
- `SQL DATABSE DOCUMENTATION/SQL-PROD_Agent_Jobs_Documentation.xlsx` — Jobs documentation
- `SQL DATABSE DOCUMENTATION/create_jobs_doc.py` — Script that generated the xlsx
- `SQL DATABSE DOCUMENTATION/SESSION_HANDOFF_NOTES.md` — This file

### Modified files:
- `toast_net_sales_app/backend/.env.example` — Added TOAST_SQL_DATABASE
- Various memory files in .claude/projects/*/memory/
