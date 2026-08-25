# Kim's Cheat Sheet — the commands I keep asking Claude for

> Three boxes to remember:
> - **Cloudways** (`master_newksxl@165.227.79.143`) — the reporting app + uvicorn
> - **dev-jan02** (`root@dev-jan02`) — pullers, crons, postfix mail relay, contacts drainer
> - **SQL-PROD** — via SSMS only
>
> ⚠ PowerShell gotcha: complex quoted commands (anything with parentheses or
> nested quotes) break when passed through `ssh "..."`. When in doubt, SSH in
> first, THEN run the command at the server's own prompt.

---

## Cloudways — deploy & babysit the app

```powershell
# Full deploy: pull latest code + restart uvicorn
ssh master_newksxl@165.227.79.143 "cd /home/master/applications/wpftndhcuj/public_html && git pull && cd backend && ./restart.sh"

# Frontend-only change (html files): pull, no restart — then Ctrl+Shift+R in browser
ssh master_newksxl@165.227.79.143 "cd /home/master/applications/wpftndhcuj/public_html && git pull"

# Restart only (app hung / OOM'd)
ssh master_newksxl@165.227.79.143 "cd /home/master/applications/wpftndhcuj/public_html/backend && ./restart.sh"

# Watch the uvicorn log LIVE (Ctrl+C to stop watching; harmless to the server)
ssh master_newksxl@165.227.79.143 "tail -f /home/master/applications/wpftndhcuj/public_html/backend/uvicorn.log"

# Last 30 log lines + is uvicorn even alive?
ssh master_newksxl@165.227.79.143 "ps -ef | grep uvicorn | grep -v grep; echo ---; tail -30 /home/master/applications/wpftndhcuj/public_html/backend/uvicorn.log"
```

**Reading the alive-check:** a `venv/bin/uvicorn main:app` process line = alive.
Nothing above the `---` = dead (probably OOM) → restart. A long-running report
job CANNOT be cancelled from the UI — only `./restart.sh` truly stops it.

---

## Mapping table — sync from Toast Web

After changing item tags / EE counts / adding items in Toast Web:

```bash
ssh master_newksxl@165.227.79.143
cd /home/master/applications/wpftndhcuj/public_html/backend
source venv/bin/activate
python sync_toast_config.py --step all
```

- ~5–10 min; no restart needed
- Preserves your hand-entered Aloha names/PLUs; refreshes everything Toast-sourced
- New Toast items land with blank Aloha columns → fill in via Mapping Table UI
- **Afterwards:** trivial save in Mapping Table UI (or Admin Panel → Clear Cache)
  so menu reports stop serving pre-sync cached results

---

## Menu performance report — when counts look wrong

Order of operations (learned the hard way, June 2026):

1. **Check coverage first**: Admin Panel → Menu Data Backfill → Check Coverage
   for the EXACT report date range (defaults can mask edge days). One missing
   day silently sends the report to the slow live-Toast path that can OOM the app.
2. **Backfill missing days** (Force re-fetches already-covered days).
3. **Clear the menu cache**: Admin Panel → Menu Report Precompute → Clear Cache.
4. Re-run the report.

Gold-standard validation: export Toast Web PMIX for ONE day (Items +
Modifiers sheets) and have Claude diff it per item vs the app export.

---

## dev-jan02 — pullers & repolls

```bash
ssh root@dev-jan02            # password in KeePass
```

```bash
# Sales repoll (date range) — auto-runs the DayPartID fix + rollup
cd /opt/toast_backfill/backend
python3 nightly_pull.py --start-date 2026-04-20 --end-date 2026-04-27

# Labor repoll
source /opt/toast_backfill/backend/venv/bin/activate
cd /opt/toast_backfill/backend
python3 nightly_labor_pull.py 2026-04-27            # one date
python3 nightly_labor_pull.py --days-back 7         # rolling catch-up

# Puller logs
tail -50 /var/log/toast_sales.log
tail -50 /var/log/toast_labor.log
```

⚠ After ANY hstItem repoll: DayPartID must get fixed + rollup rebuilt, or the
Flash Report channel breakdown silently loses that revenue. `nightly_pull.py`
now does this automatically (even with `--skip-rollup`), but standalone/older
scripts may not — see `fix_daypartid_may2026.sql` for the manual repair pattern.

---

## Payroll export — pre-flight + employee sync

The ADP export (`sp_rpt_Company_Payroll_Export_TOAST`) silently drops any
employee with shifts but no `toast.dbo.Employees` record, and blank-File#s
anyone whose `ExternalEmployeeId` isn't set in Toast. The employee master is
synced by `nightly_labor_pull.py` (runs nightly). If hours look short:

```bash
# 1. On-demand employee roster refresh (dev-jan02) — run BEFORE payroll
ssh root@dev-jan02
source /opt/toast_backfill/backend/venv/bin/activate
cd /opt/toast_backfill/backend
python3 nightly_labor_pull.py --employees-only                 # all stores
python3 nightly_labor_pull.py --employees-only --store 1003    # one store
#   add --dry-run --debug-first to inspect the Toast employee JSON w/o writing
```

```sql
-- 2. PRE-FLIGHT: who will drop/blank from the export this pay period
--    (set dates; defaults 9/244 = corporate Toast stores)
--    SQL DATABSE DOCUMENTATION/payroll_export_missing_emps_2026-06/02_preflight_check.sql
```

- **WILL DROP** in pre-flight → no employee record → run `--employees-only`, re-check.
- **BLANK FILE#** → Toast has no payroll ID → **HR sets ExternalEmployeeId in Toast**,
  then `--employees-only` again (the sync can't invent a number).
- Then regenerate the export; Flowood validated to match Toast to the penny.
- Diagnosis/queries: `SQL DATABSE DOCUMENTATION/payroll_export_missing_emps_2026-06/`.

---

## Contacts sync (app ↔ SQL-PROD)

```bash
# Manual drain (dev-jan02) — applies queued app edits to SQL Server
ssh root@dev-jan02
source ~/.contacts_drainer.env
cd /opt/toast_net_sales_app/backend
python3 contacts_outbox_drainer.py            # add --batch-size 1000 for big backlogs

# Drainer log / cron
tail -30 ~/contacts_drainer.log
crontab -l | grep -i contacts
```

- Drainer logs itself in each run (APP_ADMIN_EMAIL/PASSWORD in the env file) —
  no more 30-day token babysitting
- **Sync FROM SQL → app**: click "⟳ Sync from SQL" on the Contacts page; the
  drainer fulfills it on its next cron cycle (queue must be empty first)
- Status: `/contacts-outbox.html` in the app

```powershell
# Copy an updated script from laptop → dev-jan02 (no git there; SCP deploys)
cd "C:\Users\KimAylesworth\OneDrive - Newk's Eatery\Desktop\Kim\toast_net_sales_app\backend"
scp SCRIPTNAME.py root@dev-jan02:/opt/toast_net_sales_app/backend/
```

---

## App auth token (for curl against the app's API)

- **Browser**: log into the app → F12 → Console → `localStorage.getItem('auth_token')`
- **curl**:
  ```bash
  curl -s -X POST "https://phpstack-1474989-6237770.cloudwaysapps.com/api/auth/login" -H "Content-Type: application/json" -d '{"email":"admin@newks.com","password":"PASSWORD"}'
  ```
- Tokens expire (~days) — "Could not validate credentials" = grab a fresh one

---

## Query the app's SQLite DBs on Cloudways (no sqlite3 CLI there!)

```bash
ssh master_newksxl@165.227.79.143
cd /home/master/applications/wpftndhcuj/public_html/backend
venv/bin/python -c "
import sqlite3
db = sqlite3.connect('data/toast_menu_raw.db')   # or data/contacts/contacts.db, data/toast_config/toast_config.db
for r in db.execute('SELECT ... '):
    print(r)
"
```

Raw menu rows gotcha: MODIFIER-kind rows have BLANK names — query by GUID.

---

## SSRS / SQL-PROD quickies (SSMS)

```sql
-- Why did a subscription stop emailing? Find its Agent job + enabled flag
USE ReportServer;
SELECT c.Name, s.Description, sch.ScheduleID, j.name AS AgentJob, j.enabled
FROM dbo.Subscriptions s
JOIN dbo.Catalog c          ON c.ItemID = s.Report_OID
JOIN dbo.ReportSchedule rs  ON rs.SubscriptionID = s.SubscriptionID
JOIN dbo.Schedule sch       ON sch.ScheduleID = rs.ScheduleID
LEFT JOIN msdb.dbo.sysjobs j ON j.name = CONVERT(varchar(36), sch.ScheduleID)
WHERE c.Name LIKE '%REPORT NAME%';
-- re-enable: EXEC msdb.dbo.sp_update_job @job_name = N'<GUID>', @enabled = 1;

-- Subscriptions still owned by Don (the expired-account time bomb)
SELECT c.Name, u.UserName, s.LastRunTime, s.LastStatus
FROM ReportServer.dbo.Subscriptions s
JOIN ReportServer.dbo.Catalog c ON c.ItemID = s.Report_OID
JOIN ReportServer.dbo.Users u   ON u.UserID = s.OwnerID
WHERE u.UserName = 'NFC\dwilson';

-- Rebuild the Flash Report rollup for a date range
EXEC dev_aloha.dbo.sp_toast_SalesDataByDayPart
    @StartDate = '2026-05-01', @EndDate = '2026-05-31',
    @StoreGrouping = 9, @StoreGroup = 243;
```

---

*Maintained by Kim + Claude. Started 2026-06-13. When Claude gives you a
command for the third time, it goes in here.*
