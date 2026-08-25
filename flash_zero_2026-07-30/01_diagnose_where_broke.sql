/* ============================================================================
   01_diagnose_where_broke.sql   (2026-07-31)  -- READ-ONLY diagnostic

   SYMPTOM: Flash Report = $0 for DateOfBusiness 7/30/2026 (all/most stores).
   GOAL:    Pinpoint WHERE the overnight chain broke. Run all 4 blocks; read
            the verdict at the bottom.

   PIPELINE (each layer feeds the next):
     nightly_pull.py (dev-jan02)
        -> toast.dbo.hstCheck / hstItem        [LAYER A: raw pull landed?]
        -> fix_daypart_ids                     [LAYER C: DayPartID mapped?]
        -> dev_aloha.dbo.tbl_SalesDataByDayPart[LAYER B: rollup rebuilt?]
        -> Flash Report reads the rollup
   ============================================================================ */

------------------------------------------------------------------------------
-- LAYER A: did the raw Toast SALES pull land for 7/30?  (source of truth)
--   Compare 7/30 to 7/29 (known-good) and 7/28. If 7/30 = 0 rows or a tiny
--   fraction of 7/29 -> the PULL failed / didn't run. Fix = re-run nightly_pull.
------------------------------------------------------------------------------
SELECT
    Layer = 'A. toast.hstCheck (raw pull)',
    c.DateOfBusiness,
    Stores  = COUNT(DISTINCT c.StoreNum),
    Checks  = COUNT(*),
    NetAmt  = SUM(c.Amount),
    TotalAmt = SUM(c.TotalAmount)
FROM toast.dbo.hstCheck c WITH (NOLOCK)
WHERE c.DateOfBusiness BETWEEN '2026-07-28' AND '2026-07-30'
  AND c.Voided = 0 AND c.Deleted = 0
GROUP BY c.DateOfBusiness
ORDER BY c.DateOfBusiness;

------------------------------------------------------------------------------
-- LAYER B: did the ROLLUP rebuild for 7/30?  (what Flash actually reads)
--   If Layer A HAS rows for 7/30 but this is 0 -> the rollup step didn't run
--   (or failed). Fix = EXEC sp_toast_SalesDataByDayPart for 7/30 (block 03).
------------------------------------------------------------------------------
SELECT
    Layer = 'B. tbl_SalesDataByDayPart (rollup)',
    DateOfBusiness,
    Stores = COUNT(DISTINCT RestaurantID),
    Rows   = COUNT(*),
    RNet   = SUM(NetSales),
    Checks = SUM(CheckCount)
FROM dev_aloha.dbo.tbl_SalesDataByDayPart WITH (NOLOCK)
WHERE DateOfBusiness BETWEEN '2026-07-28' AND '2026-07-30'
GROUP BY DateOfBusiness
ORDER BY DateOfBusiness;

------------------------------------------------------------------------------
-- LAYER C: DayPartID NULL check for 7/30 (only meaningful if Layer B has rows)
--   NULL DayPartID rows silently drop out of the Flash channel breakdown even
--   when the rollup ran. If Layer B has rows but Flash still shows 0 by mode,
--   this is the culprit. Fix = fix_daypart_ids + rebuild rollup.
------------------------------------------------------------------------------
SELECT
    Layer = 'C. DayPartID NULLs',
    DateOfBusiness,
    TotalRows   = COUNT(*),
    NullDayPart = SUM(CASE WHEN DayPartID IS NULL THEN 1 ELSE 0 END),
    NullNet     = SUM(CASE WHEN DayPartID IS NULL THEN NetSales ELSE 0 END)
FROM dev_aloha.dbo.tbl_SalesDataByDayPart WITH (NOLOCK)
WHERE DateOfBusiness BETWEEN '2026-07-29' AND '2026-07-30'
GROUP BY DateOfBusiness
ORDER BY DateOfBusiness;

------------------------------------------------------------------------------
-- LAYER A': did the raw Toast ITEM pull land? (hstItem feeds daypart mapping)
--   A pull can land checks but not items, or vice-versa. Compare 7/30 vs 7/29.
------------------------------------------------------------------------------
SELECT
    Layer = 'A2. toast.hstItem (raw items)',
    i.DateOfBusiness,
    Stores = COUNT(DISTINCT i.StoreNum),
    Items  = COUNT(*),
    NullDP = SUM(CASE WHEN i.DayPartID IS NULL THEN 1 ELSE 0 END)
FROM toast.dbo.hstItem i WITH (NOLOCK)
WHERE i.DateOfBusiness BETWEEN '2026-07-28' AND '2026-07-30'
GROUP BY i.DateOfBusiness
ORDER BY i.DateOfBusiness;

/* ============================================================================
   VERDICT — read the four result sets top to bottom:

   * Layer A (hstCheck) 7/30 = 0 rows        -> PULL never ran / failed at the
       source. Root cause is on dev-jan02 (cron didn't fire, API auth expired,
       504 truncation, script error). Check /var/log/toast_sales.log, then
       re-run:  python nightly_pull.py 2026-07-30
       (self-contained: pull + daypart-fix + rollup). This is the usual cause.

   * Layer A HAS 7/30 rows, Layer B (rollup) = 0 -> pull landed but the rollup
       step didn't. Just rebuild the rollup for 7/30 (block 03) -- no re-pull.

   * Layer A & B both have 7/30 rows, but Layer C shows NullDayPart = all rows
       -> DayPart mapping hole (unmapped restaurantService GUID -> think 1188).
       Needs fix_daypart_ids + a cfg_RestaurantService INSERT if a new store.

   * Layer A rows but only a FEW stores / tiny counts vs 7/29 -> partial /
       truncated pull. Re-run nightly_pull.py 2026-07-30 to backfill.
   ============================================================================ */
