-- =====================================================================
-- Check-count variance — Week 24 2025 (2025-06-09 .. 2025-06-15)
-- Stores: 1003 Flowood, 1008 Birmingham Downtown, 1014 Ridgeland
--         (Lake Harbour), 1042 Hot Springs, 1197 Pascagoula
--
-- Colleague tracked daily traffic at the time; the Flash Report now
-- shows LOWER check counts for these transition-week stores. They want:
--   (1) are the current numbers right?  (2) why did they change?
--   (3) what window of dates was recalculated?
--
-- HYPOTHESIS: the Flash Report's check count
-- (dev_aloha.dbo.tbl_SalesDataByDayPart, built by
-- sp_toast_SalesDataByDayPart) sources counts from Aloha BEFORE each
-- store's ToastLive date and from Toast ON/AFTER it. The Toast count
-- uses INNER joins through cfg_RestaurantService (daypart) and
-- cfg_map_DiningOptionToOrderMode (dining option) — any check with a
-- daypart/dining-option GUID missing from those config tables is
-- silently dropped. A repoll + rollup rebuild after the original
-- reporting could therefore lower the count.
--
-- This script is READ-ONLY. Run each section, paste results back.
-- Column names follow sp_toast_SalesDataByDayPart as of 2026-06.
-- If a column name errors, run §0 to confirm the schema.
-- =====================================================================

-- ============================================================
-- §0  SCHEMA SANITY (run first if any later column name errors)
-- ============================================================
-- SELECT TOP 1 * FROM toast.dbo.hstCheck;
-- SELECT TOP 5 * FROM toast.dbo.cfg_RestaurantService;
-- SELECT TOP 5 * FROM toast.dbo.cfg_map_DiningOptionToOrderMode;
-- SELECT * FROM dev_aloha.dbo.get_StoresIncluded(9, '243', '2025-06-15')
--   WHERE StoreID IN (1003,1008,1014,1042,1197);

-- ============================================================
-- §1  ToastLive boundary — is week 24 before/during/after cutover
--     for each store? This alone may explain everything: dates
--     >= ToastLive are Toast-sourced, dates before are Aloha-sourced.
-- ============================================================
SELECT StoreID, StoreName, ToastLive
FROM dev_aloha.dbo.get_StoresIncluded(9, '243', '2025-06-15')
WHERE StoreID IN (1003,1008,1014,1042,1197)
ORDER BY StoreID;

-- ============================================================
-- §2  WHAT THE FLASH REPORT CURRENTLY SHOWS
--     (the "Now Reporting" numbers) — per store per day for wk24.
--     CheckCount = all checks; ChecksMinusCatering = the traffic
--     figure the Flash Report's NonCateringChecks line uses.
-- ============================================================
SELECT
    RestaurantID, DateOfBusiness,
    CheckCount, ChecksMinusCatering
FROM dev_aloha.dbo.tbl_SalesDataByDayPart
WHERE RestaurantID IN (1003,1008,1014,1042,1197)
  AND DateOfBusiness BETWEEN '2025-06-09' AND '2025-06-15'
ORDER BY RestaurantID, DateOfBusiness;

-- ============================================================
-- §3  TOAST RAW vs COUNTED — the key comparison.
--   raw_checks        = every non-void/non-deleted Toast check
--   counted_checks    = what survives BOTH inner joins (= what the
--                       rollup actually credits)
--   dropped_no_daypart   = checks whose DayPart GUID isn't in cfg_RestaurantService
--   dropped_no_diningopt = checks whose OrderMode GUID isn't in the mapping
-- If raw > counted, the INNER joins are dropping checks → the bug.
-- ============================================================
SELECT
    c.StoreNum,
    c.DateOfBusiness,
    COUNT(DISTINCT c.checkid)                                           AS raw_checks,
    COUNT(DISTINCT CASE WHEN dp.GUID IS NOT NULL AND ommap.GUID IS NOT NULL
                        THEN c.checkid END)                             AS counted_checks,
    COUNT(DISTINCT CASE WHEN dp.GUID IS NULL THEN c.checkid END)        AS dropped_no_daypart,
    COUNT(DISTINCT CASE WHEN ommap.GUID IS NULL THEN c.checkid END)     AS dropped_no_diningopt
FROM toast.dbo.hstCheck c
LEFT JOIN toast.dbo.cfg_RestaurantService dp            ON c.DayPart   = dp.GUID
LEFT JOIN toast.dbo.cfg_map_DiningOptionToOrderMode ommap ON c.OrderMode = ommap.GUID
WHERE c.StoreNum IN (1003,1008,1014,1042,1197)
  AND c.DateOfBusiness BETWEEN '2025-06-09' AND '2025-06-15'
  AND c.Voided = 0 AND c.Deleted = 0
GROUP BY c.StoreNum, c.DateOfBusiness
ORDER BY c.StoreNum, c.DateOfBusiness;

-- ============================================================
-- §4  ALOHA SIDE — what the ORIGINAL daily numbers most likely were
--     (the colleague's "Initially Reported"), before the store
--     flipped to Toast sourcing. checkdata is the Aloha check source.
-- ============================================================
SELECT
    cd.fkstoreid                  AS StoreID,
    cd.dateofbusiness             AS DateOfBusiness,
    COUNT(cd.checkid)             AS aloha_checks
FROM dev_aloha.dbo.checkdata cd
WHERE cd.fkstoreid IN (1003,1008,1014,1042,1197)
  AND cd.dateofbusiness BETWEEN '2025-06-09' AND '2025-06-15'
  AND cd.fkordermodeid != 99
GROUP BY cd.fkstoreid, cd.dateofbusiness
ORDER BY cd.fkstoreid, cd.dateofbusiness;

-- ============================================================
-- §5  IF §3 shows dropped checks: list the unmapped GUIDs so we
--     know exactly what to add to the config tables. (Daypart side
--     and dining-option side.) Sums show how many checks each
--     missing GUID is costing.
-- ============================================================
-- Dining-option GUIDs present in these checks but NOT mapped:
SELECT c.OrderMode AS unmapped_diningoption_guid,
       COUNT(DISTINCT c.checkid) AS checks_affected
FROM toast.dbo.hstCheck c
LEFT JOIN toast.dbo.cfg_map_DiningOptionToOrderMode ommap ON c.OrderMode = ommap.GUID
WHERE c.StoreNum IN (1003,1008,1014,1042,1197)
  AND c.DateOfBusiness BETWEEN '2025-06-09' AND '2025-06-15'
  AND c.Voided = 0 AND c.Deleted = 0
  AND ommap.GUID IS NULL
GROUP BY c.OrderMode
ORDER BY checks_affected DESC;

-- Daypart GUIDs present in these checks but NOT in cfg_RestaurantService
-- (NULL guid = check has no/blank DayPart — the check-count twin of the
--  hstItem DayPartID-NULL repoll bug):
SELECT ISNULL(c.DayPart,'(null)') AS unmapped_daypart_guid,
       COUNT(DISTINCT c.checkid)  AS checks_affected
FROM toast.dbo.hstCheck c
LEFT JOIN toast.dbo.cfg_RestaurantService dp ON c.DayPart = dp.GUID
WHERE c.StoreNum IN (1003,1008,1014,1042,1197)
  AND c.DateOfBusiness BETWEEN '2025-06-09' AND '2025-06-15'
  AND c.Voided = 0 AND c.Deleted = 0
  AND dp.GUID IS NULL
GROUP BY c.DayPart
ORDER BY checks_affected DESC;
