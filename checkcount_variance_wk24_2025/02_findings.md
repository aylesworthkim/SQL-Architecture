# Week 24 2025 Check-Count Variance — Findings (RESOLVED)

**Date investigated:** 2026-06-15
**Stores:** 1003 Flowood, 1008 Birmingham (Downtown), 1014 Ridgeland (Lake
Harbour), 1042 Hot Springs, 1197 Pascagoula
**Week 24 2025:** 2025-06-09 .. 2025-06-15

## Answer

**Not a bug, not a repoll, not data loss — a metric mismatch: GUESTS vs CHECKS.**
The colleague's manually-tracked "traffic" is a GUEST count; the Flash Report's
"Check Count" line is a CHECK/ORDER count. Both are correct and both come from
Toast; they were never the same measure.

Proven against Toast's own SalesSummary export for Flowood (the authoritative
source, pulled from Toast Web outside the SQL/dev_aloha pipeline):

| Toast SalesSummary (Flowood, wk24 2025) | Value | Matches |
|---|---:|---|
| **Total guests** | **3,952** | colleague "Initially Reported" 3,952 — exact |
| **Total orders** | **3,473** | Flash "Now Reporting" 3,473 — exact |

Reconciliation from raw Toast OrderDetails: 3,504 order rows − 30 voided
orders = 3,474 ≈ 3,473 orders; guests sum to 3,983 raw / 3,952 net of voids.
Guests ÷ orders = 1.14 (some orders seat multiple guests) — that 14% is the
entire "variance."

## Why it surfaced on transition stores

Pre-Toast, the daily traffic figure captured for these stores was guest-based;
after Toast cutover the Flash Report column being compared against is the
check/order count. Apples-to-oranges, so the gap only showed on the stores
that switched.

## What was RULED OUT (and the false trails)

- **Count-drop bug** (the hstItem DayPartID-NULL twin): NO. §3 showed the Toast
  rollup's INNER joins drop ~0 checks (`raw_checks == counted_checks`).
- **dev_aloha "corroborates" Toast:** FALSE LEAD. dev_aloha.checkdata is FED
  FROM Toast (confirmed by Kim) and the stores did NOT run dual POS — so
  checkdata ≈ hstCheck is circular (a source vs its own downstream copy), not
  independent corroboration. Do not use that as evidence.
- **Repoll lost checks:** NO. Toast's own SalesSummary (independent of the
  repoll pipeline) shows 3,473 orders — the current number — so nothing was
  lost.

## How it was actually resolved

The only trustworthy arbiter was Toast itself, pulled OUTSIDE the SQL Server /
dev_aloha pipeline: the Toast Web SalesSummary + OrderDetails exports. Those
showed guests=3,952 and orders=3,473, matching the two figures exactly.

## For the colleague

Confirm whether the weekly traffic log records guests or checks. The data
proves 3,952 = Toast guests, so the log is guest-based. To compare like-for-
like going forward, either (a) compare the log's guests to a Toast/Flash GUEST
metric, or (b) switch the log to checks/orders. Nothing in the historical data
needs correcting — both numbers were always right, just different measures.
Other 4 stores: same guests-vs-checks distinction; pull each store's Toast
SalesSummary "Total guests" to confirm it matches that store's "Initially
Reported" (the two mid-week-cutover stores, Birmingham 6/12 and Hot Springs
6/10, also have an Aloha/Toast day-split so their arithmetic is less clean).

## Files

- `01_discovery.sql` — read-only SQL diagnostics (ToastLive, Flash current,
  Toast raw-vs-counted, Aloha).
- Toast exports used as the arbiter: `OrderDetails_2025_06_09-2025_06_15.csv`,
  `SalesSummary_2025-06-09_2025-06-15.xlsx` (Flowood).
