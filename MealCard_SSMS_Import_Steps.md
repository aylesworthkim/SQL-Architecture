# Monthly Meal Card → SSMS Import Steps (for the SSRS Payroll Report)

How to get the monthly meal card reload data into SQL so the SSRS report
**"Monthly MealCard Adjustments for Payroll"** renders. Do this on/around the
**1st of each month**, after the Paytronix reload bot has run.

> **Important:** The `_with_names.xlsx` file is only your human-readable copy.
> It does NOT get imported. SQL stores card numbers + amounts; the SSRS report
> attaches employee names itself by joining card numbers to
> `dev_aloha.dbo.MealCardsToAllPay`. So you import the **raw report**, not the
> `_with_names` file.

---

## Where things live

| Thing | Location |
|---|---|
| Destination table | `paytronix.dbo.ManualAdjustment` (on **SQL-PROD**) |
| Report stored proc | `dev_aloha.dbo.sp_rpt_Monthly_MealCard_Adjustment_For_Payroll` |
| Employee name mapping | `dev_aloha.dbo.MealCardsToAllPay` |
| SSRS data source | `dscDevAloha` |
| Source data | The Stored Value report from Paytronix (e.g. `StoredValueSalesandAddedValueDetailReport-YYYYMMDD-...csv`) |

Expected volume: **~20 rows** per month (one per card reloaded).

---

## Step 1 — Look at last month's rows first (your template)

Before importing, see exactly how the prior month was loaded so you match the
shape. In SSMS run:

```sql
SELECT TOP 50 *
FROM paytronix.dbo.ManualAdjustment
WHERE TransactionDate >= '2026-05-01' AND TransactionDate < '2026-06-01'
ORDER BY TransactionDate;
```

Note which columns they actually fill in vs. leave NULL — copy that pattern.

---

## Step 2 — Map the report columns to the table

`paytronix.dbo.ManualAdjustment` columns and where they come from in the
Stored Value report CSV:

| Table column | Type | From CSV column | Notes |
|---|---|---|---|
| `CardNumber` | bigint | **Card Number** | |
| `CardTemplate` | varchar(18) | **Card Template** | e.g. "Gift Card" |
| `TransactionDate` | datetime | **Date** | e.g. 2026-06-01 09:40 |
| `TransactionType` | varchar(32) | **Transaction Type** | e.g. "Admin Adjustment" |
| `StoreName` | varchar(150) | **Store Name** | e.g. "Flowood MS" |
| `StoreNumber` | varchar(20) | **Store Number** | e.g. 1003 |
| `CheckNo` | varchar(50) | **Check No.** | e.g. "web" |
| `StoredValueAccrued` | real | **Dollars Added** | the amount reloaded — *verify against last month's rows* |
| `StoredValueBalance` | real | **Balance** | new balance after reload |
| `AccountCode` | int | (none) | leave NULL unless last month had it |
| `CustomerNo` | varchar(50) | (none) | leave NULL unless last month had it |
| `Username` | varchar(50) | (none) | leave NULL unless last month had it |
| `AccountStatus` | varchar(50) | (none) | leave NULL |
| `Promotion` | varchar(50) | (none) | leave NULL |
| `CSRComment` | varchar(500) | (none) | leave NULL |
| `StoredValueRedeemed` | real | (none) | leave NULL/0 |

CSV columns **not** used: Discount Added, Discount Balance, Net Amount,
Terminal ID, Cashier ID.

> Confirm `Dollars Added` → `StoredValueAccrued` matches how May was loaded
> (Step 1). If May put the amount somewhere else, follow May.

---

## Step 3 — Import (pick ONE method)

### Method C — Auto-generate the INSERT (RECOMMENDED — no manual mapping)
This replaces the hand-mapping in the wizard. It reads the raw Stored Value
report CSV and writes a ready-to-run `INSERT` script.

1. Make sure the reload bot has run and the report CSV is in your Downloads.
2. Run:
   ```
   python "C:\Users\KimAylesworth\OneDrive - Newk's Eatery\Desktop\Meal Card Reload Scripts\make_mealcard_insert.py"
   ```
   (No argument = it auto-picks the newest `StoredValue...csv`. Or pass a path.)
3. It writes `MealCard_Insert_<YYYY-MM-DD>.sql` next to the CSV and prints it.
4. Open that `.sql` in **SSMS connected to SQL-PROD** and hit **Execute (F5)**.
   The statement is fully qualified (`paytronix.dbo.ManualAdjustment`), so it
   works from any database context — you just need to be on the SQL-PROD server.
5. Go to Step 4 to verify. Done — skip Methods A and B.

*Validated: regenerating the 2026-06-01 report produces byte-identical SQL to
the load that worked that month.*

### Method A — Import wizard (point & click)
1. Open **SSMS**, connect to **SQL-PROD**.
2. Object Explorer → expand **Databases → paytronix**.
3. Right-click **paytronix** → **Tasks → Import Flat File...** (or **Import Data...** for the older wizard).
4. Source = the Stored Value report CSV in your Downloads folder.
5. Destination = existing table **`dbo.ManualAdjustment`** (do NOT create a new table).
6. On the column-mapping screen, line up columns per the table in Step 2; skip the unused CSV columns.
7. Finish, then go to Step 4 to verify.

### Method B — Direct INSERT (copy/paste template)
Paste one VALUES line per row (fill from the report). Format the date as shown.

```sql
INSERT INTO paytronix.dbo.ManualAdjustment
    (CardNumber, CardTemplate, TransactionDate, TransactionType,
     StoreName, StoreNumber, CheckNo, StoredValueAccrued, StoredValueBalance)
VALUES
    (35303000175190, 'Gift Card', '2026-06-01 09:40', 'Admin Adjustment',
     'Flowood MS', '1003', 'web', 102.00, 160.00),
    (35303000649586, 'Gift Card', '2026-06-01 09:40', 'Admin Adjustment',
     'Flowood MS', '1003', 'web', 114.25, 160.00);
-- ...one row per card from the report...
```

---

## Step 4 — Verify the import

```sql
SELECT COUNT(*) AS RowsThisMonth
FROM paytronix.dbo.ManualAdjustment
WHERE TransactionDate >= '2026-06-01' AND TransactionDate < '2026-07-01';
-- Expect ~20 (this month: 21)
```

Spot-check a couple of rows match the report (amounts + balances).

---

## Step 5 — Check the employee name mapping

The SSRS report drops any card whose employee isn't mapped. Make sure every
card number is present in the mapping:

```sql
-- Cards imported this month that are NOT in the employee mapping:
SELECT DISTINCT m.CardNumber
FROM paytronix.dbo.ManualAdjustment m
LEFT JOIN dev_aloha.dbo.MealCardsToAllPay map
       ON map.CardNumber = m.CardNumber   -- confirm join column name in the table
WHERE m.TransactionDate >= '2026-06-01' AND m.TransactionDate < '2026-07-01'
  AND map.CardNumber IS NULL;
```

If any rows come back, add the employee to `dev_aloha.dbo.MealCardsToAllPay`.
*(Known pending: Klara Smith still needs an employee ID from payroll.)*

---

## Step 6 — Run the SSRS report

Open **"Monthly MealCard Adjustments for Payroll"** in Report Manager / the
SSRS portal and run it for the current month.

### If the report is blank — known gotchas
- **Data source `dscDevAloha` broke once** (a shared data source got moved/
  renamed). If everything's blank, check/repoint `dscDevAloha`.
- **Missing employee mapping** — see Step 5; unmapped cards silently drop.
- **No data imported** — re-check Step 4 row count.

---

## Quick monthly checklist
- [ ] Reload bot run in Paytronix (desktop shortcut)
- [ ] Names added to report (`add_names_to_storedvalue.py`) — your reference copy
- [ ] Looked at last month's rows as a template (Step 1)
- [ ] Imported raw report into `paytronix.dbo.ManualAdjustment` (Step 3)
- [ ] Verified row count ~20 (Step 4)
- [ ] All cards mapped in `MealCardsToAllPay` (Step 5)
- [ ] SSRS report renders (Step 6)
