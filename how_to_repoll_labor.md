# How to Repoll for Labor

## How to Trigger a Labor Repoll

**When to use this:** The labor / payroll / shift hours data is missing
or looks wrong for one or more stores on a specific date. Common signs:
a store shows zero hours in the labor report, a manager says "I clocked
employees in but they're not showing up", or the labor side of the
weekly P&L is off.

Open PowerShell, SSH in (command below) will prompt for password — get
password from KeePass for root user:

```
ssh root@dev-jan02
```

Activate and run:

```
source /opt/toast_backfill/backend/venv/bin/activate
cd /opt/toast_backfill/backend
python nightly_labor_pull.py 2026-04-27
```

Replace the date with whichever date needs repolling. Runtime ~5–15 min
for a single date across all stores. When you see `0 failed` and
`Rollup: OK` it's done — refresh the labor report.

---

## Common Variations

### Repoll a date range (backfill)

```
python nightly_labor_pull.py --start-date 2026-04-20 --end-date 2026-04-27
```

Pulls every date in the range, in one run. Useful after an extended
outage. Runtime ~5–15 min per date.

### Rolling catch-up (last N days)

```
python nightly_labor_pull.py --days-back 7
```

Repolls yesterday plus N prior days (here, 8 dates total). The default
nightly cron already runs `--days-back 3`, so use this when you suspect
adjustments older than 3 days got missed.

### Single store only (fast sanity check)

```
python nightly_labor_pull.py 2026-04-27 --store 1051
```

Pulls one store for one date. Useful for testing or when only one
store's data is bad. Other stores' data for that date is left untouched.

### Skip the rollup (hstShift only — fastest)

```
python nightly_labor_pull.py 2026-04-27 --skip-rollup
```

Populates `toast.dbo.hstShift` but does NOT call
`sp_process_pulled_labor`. Use when you're backfilling many dates and
want to run the rollup just once at the end:

```
python nightly_labor_pull.py --start-date 2026-04-01 --end-date 2026-04-15 --skip-rollup
# then ONCE, in SSMS:
EXEC toast.dbo.sp_process_pulled_labor
```

### Dry run (verify before writing)

```
python nightly_labor_pull.py 2026-04-27 --dry-run
```

Fetches from Toast and shows what WOULD be written, but doesn't touch
SQL Server. Good safety check if you're not sure what you're about to do.

---

## Notes

- This script is **safe to run alongside `nightly_pull.py`** (the sales
  poll) — different tables, no shared staging. Both can run at the
  same time without conflict.

- **Do not run two labor instances at the same time for overlapping
  store/date combos** — the per-store DELETE+INSERT could race. Two
  instances for completely different stores is fine, but easier to
  just run sequentially.

- The labor puller uses Toast's Standard API (`/labor/v1/timeEntries`),
  which has a 30-day chunk cap per request. The script handles
  chunking automatically — you can pass a date range of any length.

- After successful repoll, `sp_process_pulled_labor` merges new
  `hstShift` rows into `tbl_LaborDataByDayPart`. The merge re-runs from
  2025-03-24 onward every time (hard-coded in the proc) — wasteful but
  safe for backfill.

---

## If something goes wrong

Check the log on dev-jan02:

```
tail -50 /var/log/toast_labor.log
```

Or the script's own output if you ran it interactively. Common errors:

- **Standard API auth failed** — credentials in `.env` may be stale or
  rotated. Check `TOAST_STANDARD_API_CLIENT_ID` / `_CLIENT_SECRET`.
- **No matching stores in vw_live_toast_stores** — the store filter you
  passed isn't in the live-stores view. Verify the store_num.
- **Rollup proc failed** — usually a SQL Server-side issue. Re-running
  `EXEC toast.dbo.sp_process_pulled_labor` in SSMS often resolves it.
