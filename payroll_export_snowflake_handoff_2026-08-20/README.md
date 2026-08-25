# Company Store Payroll Export – Toast → Snowflake / Power BI handoff

Everything needed to rebuild the **Company Store Payroll Export - Toast** SSRS report
outside of SQL Server: what each column means, where it comes from, the tip math, and
CSV extracts of every layer.

Verified: the extract in `csv/01_export_rows_*.csv` reproduces the 2026-08-20 SSRS
Excel file **exactly** — 3,445 rows, same keys, same values
(112,117.21 reg hrs / 1,476.11 OT hrs / $441,187.01 tips).

- **Report:** `/Reports for Review and Naming/Reviewed and deployed/Company Store Payroll Export - Toast`
- **Stored procedure:** `dev_aloha.dbo.sp_rpt_Company_Payroll_Export_TOAST` (Don Wilson, 2020-01-22)
- **Reference run:** PayPeriodStart `8/3/2026`, PayPeriodEnd `8/16/2026`, StoreGrouping `2`, StoreGroup `0`, Output `1`

---

## 1. The ten columns

Grain of one row: **Co Code × Batch ID × File # × Temp Dept × Temp Rate**.
An employee gets several rows if they worked more than one job, or got a raise mid-period.

| # | Column | ADP meaning | SQL source | Derivation |
|---|--------|-------------|-----------|------------|
| 1 | Co Code | Payroll company the batch posts to | `contacts.dbo.companysetup.ADPCompanyCode` | Constant `new01`; single-row table joined `ON 1=1` |
| 2 | Batch ID | ADP paydata batch — one per restaurant | `dev_aloha.dbo.gblstore.ADPBatchID` | Store lookup on `StoreId`. `nvarchar`, not int |
| 3 | File # | Employee's ADP file number | `toast.dbo.employees.ExternalEmployeeId` | Set by HR **inside Toast**. Only employee identifier in the file |
| 4 | Batch Description | Free-text batch label | `dev_aloha.dbo.gblstore.ADPBatchDescription` | Cosmetic; populated for only 41 of the 95 stores in the reference run |
| 5 | Reg Hours | Regular hours | `toast.dbo.hstShift.RegularHours` | `SUM`, `Deleted = 0` only |
| 6 | OT Hours | Overtime hours | `toast.dbo.hstShift.OvertimeHOurs` | `SUM` (yes, the column is spelled `OvertimeHOurs`) |
| 7 | Earnings 3 Code | ADP earnings code for tip income | literal `'tip01'` in the proc | Hard-coded, *not* read from `companysetup.ADPTippedEarningsCode` |
| 8 | Earnings 3 Amount | Tip-share dollars | `toast.dbo.hstPayment.TipAmount` ÷ hours | See §2 — pooled, **not** the employee's own tips |
| 9 | Temp Dept | ADP temp-department override = job worked | `toast.dbo.JobCodeToastToAlohaMap.ExportID` | Join `JobCodes.Code = ToastJC` |
| 10 | Temp Rate | Pay rate for those hours | `toast.dbo.hstShift.HourlyWage` | Grouping key, not aggregated |

Machine-readable version with the same content: `csv/00_field_dictionary.csv`.

There is **no store number and no employee name** in the export. Batch ID is the only
store key; File # is the only employee key.

## 2. The tip math (the part nobody guesses right)

`Earnings 3 Amount` is a **pooled redistribution of the store's credit-card tips**, not the
tips the employee personally recorded. Per store, per pay period:

```
TotalTips   = SUM(hstPayment.TipAmount)  where PaymentType <> 'cash'
                                           and PaymentStatus in ('CAPTURED','AUTHORIZED')
TotalHours  = SUM(hstShift.RegularHours + hstShift.OvertimeHOurs)  for non-salary job codes
TipsPerHour = TotalTips / TotalHours

Earnings 3 Amount = SUM over shifts of ROUND((RegularHours + OvertimeHOurs) * TipsPerHour, 2)
```

Consequences worth telling the boss up front:

- Every non-salary employee at a store earns the **same dollars per hour** of tip share —
  dish, prep, expo and utility included. That is why a `81Dish` row carries tips.
- `hstShift.NonCashTips` exists per employee and is **ignored** by this report.
- `TipsPerHour` varies wildly by store ($0.00 → $7.01 in the reference period) because it
  depends on that store's tip volume relative to total labour hours — see `csv/03_store_tip_pool.csv`.

## 3. Store set — which parameter combination matters

`dev_aloha.dbo.get_StoresIncluded(@StoreGrouping, @StoreGroup, @EDate)` resolves the store list:

| Grouping / Group | Meaning | Stores (Aug 2026) |
|---|---|---|
| `2` / `0` | All stores (what the reference file used) | 102 resolved, 95 with data |
| `9` / `79` | `* All - Company Restaurants` | 28 |
| `9` / `244` | Corporate Toast stores (proc default) | 28 |
| `8` / `<store>` | A single store | 1 |

**Payroll only consumes the company stores.** The reference file was run for *all* stores,
which is why it contains 90 batches and why six franchise stores show `Batch ID = 0`
(1157, 1187, 1188, 1189, 1195, 1196 have no `ADPBatchID` configured in `gblstore`).
All 28 company stores have a valid Batch ID.

## 4. Known quirks to reproduce (or deliberately fix) in Snowflake

1. **Employees can vanish.** `hstShift → employees` is an INNER join on
   `Employee = GUID AND Store = StoreGUID`. An employee with shifts but no employee row at
   *that* store (new hire not yet synced, or someone covering at another store — Toast issues
   a per-location employee GUID) exports **nowhere**, while their hours still sit in the
   `TotalHours` denominator. Net effect: the tip pool distributed is less than tips collected.
2. **Blank File #.** 104 employees / 4,266.51 hrs in the reference period have no
   `ExternalEmployeeId` — see `csv/07_excluded_employees.csv`. Only one of them is at a
   company store (1104 Westgate, 33.98 hrs); the rest are franchise, so they never reach ADP.
   HR fixes this in Toast, then `nightly_labor_pull.py --employees-only` re-syncs.
3. **Names dropped from the final GROUP BY.** The last aggregation groups on File # but not
   on first/last name, so two employees sharing a File # (i.e. both blank) at the same job
   code and rate collapse into one row. That is the 3,475 → 3,445 row difference between
   `csv/02_employee_jobcode_detail.csv` and `csv/01_export_rows_*.csv`.
4. **Denominator vs numerator filters differ.** The `TotalHours` denominator has *no*
   `Deleted = 0` filter, while the employee-level detail does. Deleted shifts therefore inflate
   `TotalHours` and slightly under-state everyone's tip share.
5. **`WageFrequency <> 'salary'` drops NULLs.** Any job code with a NULL `WageFrequency` is
   excluded from both hours and pay, silently.
6. **Duplicate map key.** `JobCodeToastToAlohaMap` has two rows with `ToastJC = 0`
   (Admin, Accounting, both with a blank `ExportID`). Today all 37 `JobCodes` rows with
   `Code = 0` are SALARY so the wage-frequency filter removes them — but an hourly job code
   numbered 0 would fan out and **double-count** its hours.
7. **`NOREPORT` rows are dropped** (`320 Ghost Cashier`). `10MGRSalry` and `21CASHIER` never
   appear either — those job codes are salaried or unused.
8. **`hstPayment.StoreID` holds the restaurant GUID**, not a store number. The store number
   column on that table is `StoreNum`.

## 5. Files

| File | What it is | Rows |
|---|---|---|
| `10_extract_all_csvs.sql` | Read-only T-SQL that regenerates all seven CSVs. Change the four `DECLARE`s at the top for a different period or store set | — |
| `20_snowflake_port.sql` | ANSI/Snowflake rewrite of the whole thing, ready to point at landed tables | — |
| `30_sp_rpt_Company_Payroll_Export_TOAST.sql` | The original stored procedure, verbatim | 269 lines |
| `csv/00_field_dictionary.csv` | §1 as data | 10 |
| `csv/01_export_rows_2026-08-03_to_2026-08-16.csv` | The report output — matches the SSRS xlsx exactly | 3,445 |
| `csv/02_employee_jobcode_detail.csv` | Same math one level down: store, employee GUID, name, job code, rate, hours, store TipsPerHour | 3,475 |
| `csv/03_store_tip_pool.csv` | Per store: TotalHours, TotalTips, TipsPerHour | 97 |
| `csv/04_dim_store_adp.csv` | Store → Batch ID / Batch Description, flagged for whether it was in this run | 167 |
| `csv/05_dim_jobcode_map.csv` | Toast job code → Temp Dept, with wage frequency | 20 |
| `csv/06_dim_company_setup_adp.csv` | Co Code and the ADP earnings codes | 1 |
| `csv/07_excluded_employees.csv` | Hours that drop out or export with a blank File # | 104 |
| `csv/99_ssrs_output_reference_*.xlsx` | The SSRS Excel file the extract was validated against | 3,445 |

`csv/02` and `csv/07` contain employee names and ADP file numbers — treat them as payroll PII
and don't hand them out beyond whoever is building the model.

## 6. Re-running for another pay period

Edit the top of `10_extract_all_csvs.sql`:

```sql
DECLARE @SDate         date          = '2026-08-03';
DECLARE @EDate         date          = '2026-08-16';
DECLARE @StoreGrouping int           = 2;    -- 9 + '79' for company stores only
DECLARE @StoreGroup    varchar(1500) = '0';
```

Run it in SSMS against `dev_aloha`, then save each of the seven grids as CSV
(right-click the grid → *Save Results As*). Pay periods are biweekly, Sunday-anchored on
`contacts.dbo.companysetup.PayrollStartDate` = 2025-02-23.

Before any payroll period is submitted, run the pre-flight in
`../payroll_export_missing_emps_2026-06/02_preflight_check.sql` — it lists the employees
who will drop or export blank while there is still time to fix them in Toast.
