# Sysco Market mass-update 2026-05-26 — Session Summary

## The task

> Update the "Sysco Market" column on the SSRS Restaurant Contact Information
> Sheet so that every location reads what is in the "DC Name" column of
> `Restaurant by Sysco Center (1).xlsx`.

Source files Kim provided:
- `Restaurant by Sysco Center (1).xlsx` — 109 rows, 97 with a parseable store number, mapping NEWKS storeid → Sysco DC Name. Saved as `dc_mapping.csv` in this folder.
- `Restaurant Contact Information Sheet (1).xlsx` — the SSRS export (the report we're fixing). Column **Z** is "Sysco Market".

## Where "Sysco Market" actually lives

Confirmed via `01_discovery.sql` (run 2026-05-26):

- `contacts.dbo.SyscoMarket` — 76-row lookup, PK `SyscoID`. The column the SSRS report displays is **`SyscoMarket`** (varchar(16), the same name as the table — confusing).
- `contacts.dbo.Store.StoreSyscoID` (int) — the per-store FK to `SyscoMarket.SyscoID`.
- `contacts.dbo.StoreSysco` — separate junction table (163 rows) that exists but the SSRS report does NOT read it. The current SSRS join is just `Store.StoreSyscoID → SyscoMarket.SyscoID`. We leave `StoreSysco` alone.

No formal FK constraint binds `Store.StoreSyscoID` to `SyscoMarket.SyscoID` (sys.foreign_keys returned 0 rows for SyscoMarket / StoreSysco). The join still works because the IDs match.

## Mapping analysis

The 15 distinct DC Names from the xlsx and how they line up against existing `SyscoMarket.Company_Name`:

| DC Name from xlsx | Existing SyscoMarket row | Action |
|---|---|---|
| Arkansas         | SyscoID=2, Company_Name=ARKANSAS, SyscoMarket="SYSCO - ARK" | rename SyscoMarket |
| Atlanta          | SyscoID=9, Company_Name=ATLANTA, SyscoMarket="SYSCO - ATL" | rename SyscoMarket |
| Baltimore        | SyscoID=12, "SYSCO - BAL" | rename SyscoMarket |
| Central Alabama  | SyscoID=7, "SYSCO - CAL" | rename SyscoMarket |
| Central Texas    | SyscoID=4, "SYSCO - SAT" | rename SyscoMarket |
| Charlotte        | SyscoID=11, "SYSCO - CHR" | rename SyscoMarket |
| Denver           | SyscoID=14, "SYSCO - DEN" | rename SyscoMarket |
| East Texas       | SyscoID=3, "SYSCO - ETX" | rename SyscoMarket |
| Gulf Coast       | SyscoID=34, "SYSCO - GFC" | rename SyscoMarket |
| Jackson          | SyscoID=5, "SYSCO - JAC" | rename SyscoMarket |
| Kansas City      | SyscoID=46, "SYSCO - KCY" | rename SyscoMarket |
| Memphis          | SyscoID=6, "SYSCO - MEM" | rename SyscoMarket |
| Nashville        | SyscoID=58, "SYSCO - NSV" | rename SyscoMarket |
| Tampa Bay        | **no Company_Name match.** 4 affected stores all sit at SyscoID=10 (WEST COAST FLORIDA / SYSCO - WCF). Kim's call: treat as Sysco renaming the WCF DC. | rename SyscoMarket on SyscoID=10 from "SYSCO - WCF" to "Tampa Bay" |
| West Texas       | SyscoID=76, "SYSCO - WTX" | rename SyscoMarket |

Kim's call on Company_Name: leave Company_Name as-is (ALL CAPS). Only the `SyscoMarket` column gets renamed, since that's the one the SSRS report displays. Minimizes blast radius if anything else joins on Company_Name.

## Stores whose `Store.StoreSyscoID` also has to change

Of the 97 stores in the xlsx:
- **83** already point to a SyscoID whose Company_Name matches the xlsx DC Name — they'll inherit the new label automatically from the SyscoMarket rename.
- **13** are pointing at the wrong SyscoID and need their `Store.StoreSyscoID` updated:

| StoreID | StoreName | Current SyscoID | Current label | New SyscoID | New label |
|---|---|---|---|---|---|
| 1019 | Murfreesboro TN (Avenues) | 8 | KNOXVILLE | 58 | Nashville |
| 1023 | Panama City FL | 7 | CENTRAL ALABAMA | 34 | Gulf Coast |
| 1034 | Franklin TN (Cool Springs) | 8 | KNOXVILLE | 58 | Nashville |
| 1037 | Tallahassee FL | 7 | CENTRAL ALABAMA | 34 | Gulf Coast |
| 1053 | Knoxville TN (Cedar Bluff) | 8 | KNOXVILLE | 58 | Nashville |
| 1097 | Spanish Fort AL | 7 | CENTRAL ALABAMA | 34 | Gulf Coast |
| 1099 | Mobile AL (McGowin Park) | 7 | CENTRAL ALABAMA | 34 | Gulf Coast |
| 1104 | Mobile AL (Westgate Pavilion) | 7 | CENTRAL ALABAMA | 34 | Gulf Coast |
| 1118 | Murfreesboro TN (Northgate) | 8 | KNOXVILLE | 58 | Nashville |
| 1176 | Chattanooga TN | 8 | KNOXVILLE | 58 | Nashville |
| 1180 | San Angelo TX | 4 | CENTRAL TEXAS | 76 | West Texas |
| 1188 | Lubbock TX (Broadway) | 1 | ** Choose | 76 | West Texas |
| 1199 | Wichita KS (Waterfront) | 1 | ** Choose | 46 | Kansas City |

The Knoxville-to-Nashville block tells me Sysco probably consolidated their Knoxville and Nashville DCs into one Nashville DC (no Knoxville stores remain in the xlsx). Worth noting; the SyscoMarket row for Knoxville (SyscoID=8) is being left alone with no stores pointing at it after this update.

## Skipped / open follow-ups

| # | item | rough effort |
|---|------|--------------|
| 1 | **Store 1096 (zClosed - Little Rock AR Pleasant Ridge)** — in xlsx as "Gulf Coast" but currently SyscoID=2 (Arkansas) and store is closed. Skipped in this update. Confirm with boss whether the xlsx assignment matters for a closed store. | 1 question |
| 2 | The 3 OTHER closed stores currently at SyscoID=10 (1102 Clearwater, 1103 Bradenton, 1123 Palm Beach Gardens) will start showing "Tampa Bay" after this update, even though they were "WCF" when active. Likely fine but worth knowing. | informational |
| 3 | `contacts.dbo.SyscoMarket.Company_Name` values stay ALL CAPS. If you ever want them in proper case to match the new SyscoMarket column, that's a separate small UPDATE. | ~10 min |
| 4 | The Knoxville SyscoMarket row (SyscoID=8, "SYSCO - KNX") now has no stores pointing at it. Not a problem — leaving it for history. Could be soft-deleted later if you want. | optional |

## Files in this folder

- `01_discovery.sql` — read-only schema/data dump that informed everything below (already executed)
- `02_update.sql` — the transactional UPDATE (wrapped in BEGIN TRAN / COMMIT, run whole then commit or rollback)
- `dc_mapping.csv` — extracted 97-row storeid → DC Name table from the Sysco Center xlsx
- `SUMMARY.md` — this file
