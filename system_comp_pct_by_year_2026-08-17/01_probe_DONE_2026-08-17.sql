-- =====================================================================
-- STEP 1 of 2 — PROBE / CONFIRM  (Total System Comp % by Year, for Matt)
--
-- Run this whole file first and eyeball the 7 result grids. It answers
-- the questions we have to settle before the comp math can be trusted:
--
--   A. What is Newk's own "comping date" rule? (there IS a function)
--   B. How far back does the fiscal calendar go, and what happened to
--      the calendar in FY2024 (13 periods -> 12)?
--   C. How far back does usable store-level sales data actually go?
--   D. Does WeeklySales.Net tie to the Flash Report's NetSales?
--
-- Nothing here writes anything. All SELECT / sp_helptext.
-- =====================================================================

SET NOCOUNT ON;

-- ---------------------------------------------------------------------
-- A1. The house comping rule. Newk's has FN_GetCompingDate + an SSRS
--     report "/Accounting/Restaurant Open Date and Comping Date", so
--     there is an official definition of when a store starts comping.
--     Read this text -- it tells us if it's OpenDate + 12mo, + 18mo,
--     + 52 weeks, etc. That number drives everything downstream.
-- ---------------------------------------------------------------------
EXEC dev_aloha.dbo.sp_helptext 'dbo.FN_GetCompingDate';


-- ---------------------------------------------------------------------
-- A2. Its signature, so we know how to call it (arg count/types).
-- ---------------------------------------------------------------------
SELECT
    o.name              AS FunctionName,
    p.parameter_id      AS ArgPosition,
    p.name              AS ArgName,
    t.name              AS ArgType,
    p.max_length        AS ArgLen
FROM dev_aloha.sys.objects o
LEFT JOIN dev_aloha.sys.parameters p ON p.object_id = o.object_id
LEFT JOIN dev_aloha.sys.types      t ON t.user_type_id = p.user_type_id
WHERE o.name IN ('FN_GetCompingDate','staged_FN_GetCompingDate')
ORDER BY o.name, p.parameter_id;


-- ---------------------------------------------------------------------
-- A3. The store roster with the historical facts we need.
--     StoreIsComping is a *current* bit that gets flipped over time by
--     new01_Move_NonComping_To_Comping -- it is NOT history. But
--     StoreOpenDate / StoreCloseDate ARE stable historical facts, and
--     that is what lets us rebuild the comp list for any past year.
-- ---------------------------------------------------------------------
SELECT
    s.StoreID,
    s.StoreName,
    s.StoreOpenDate,
    s.StoreCloseDate,
    s.StoreIsComping        AS IsComping_TODAY_only,
    s.StoreStatus,
    s.StoreCompany,
    s.StoreOwnershipID,
    s.ToastLive,
    YEAR(s.StoreOpenDate)   AS OpenYear,
    YEAR(s.StoreCloseDate)  AS CloseYear
FROM contacts.dbo.Store s
ORDER BY s.StoreOpenDate, s.StoreID;

-- How many stores are missing an open date? Any NULLs here are stores we
-- cannot classify from dates alone and will have to handle by hand.
SELECT
    COUNT(*)                                                       AS TotalStores,
    SUM(CASE WHEN StoreOpenDate  IS NULL THEN 1 ELSE 0 END)        AS MissingOpenDate,
    SUM(CASE WHEN StoreCloseDate IS NULL THEN 1 ELSE 0 END)        AS StillOpen_NullCloseDate,
    MIN(StoreOpenDate)                                             AS EarliestOpen,
    MAX(StoreOpenDate)                                             AS LatestOpen
FROM contacts.dbo.Store;


-- ---------------------------------------------------------------------
-- B. THE FISCAL CALENDAR -- this is where the 13-period -> 12-period
--    change shows up. Look at PeriodsInYear: it should read 13 for the
--    older years and 12 from FY2024 on. Also watch WeeksInYear for any
--    53-week year, because a 53-vs-52 mismatch will inflate/deflate a
--    naive year-over-year number.
-- ---------------------------------------------------------------------
SELECT
    FiscalYear,
    MIN([Date])                     AS FY_Start,
    MAX([Date])                     AS FY_End,
    COUNT(*)                        AS DaysInYear,
    COUNT(DISTINCT FiscalPeriod)    AS PeriodsInYear,   -- <== 13 vs 12
    COUNT(DISTINCT FiscalWeek)      AS WeeksInYear,     -- <== 52 vs 53
    COUNT(DISTINCT WeekName)        AS DistinctWeekNames
FROM dev_aloha.dbo.CalendarV2
WHERE FiscalYear IS NOT NULL
GROUP BY FiscalYear
ORDER BY FiscalYear;


-- B2. Sanity check the WeekName -> FiscalYear join we rely on later.
--     EVERY row should come back with Years = 1. If any week maps to two
--     fiscal years, the weekly join is unsafe and we switch to the daily
--     source instead.
SELECT
    WeekName,
    COUNT(DISTINCT FiscalYear) AS Years,
    COUNT(DISTINCT FiscalWeek) AS Weeks,
    MIN([Date]) AS FirstDay,
    MAX([Date]) AS LastDay
FROM dev_aloha.dbo.CalendarV2
WHERE WeekName IS NOT NULL AND FiscalYear IS NOT NULL
GROUP BY WeekName
HAVING COUNT(DISTINCT FiscalYear) > 1 OR COUNT(DISTINCT FiscalWeek) > 1
ORDER BY WeekName;
-- (empty result = the join is safe)


-- B3. Does LYDate exist and is it populated? CalendarV2 has an LYDate
--     column (same-day-last-year). If it is filled in across the FY2024
--     boundary, that is the company's own answer to "what lines up with
--     what" after the calendar change -- worth knowing.
SELECT
    FiscalYear,
    COUNT(*)                                          AS Days,
    SUM(CASE WHEN LYDate IS NULL THEN 1 ELSE 0 END)   AS Days_Missing_LYDate,
    MIN(LYDate)                                       AS MinLYDate,
    MAX(LYDate)                                       AS MaxLYDate
FROM dev_aloha.dbo.CalendarV2
WHERE FiscalYear IS NOT NULL
GROUP BY FiscalYear
ORDER BY FiscalYear;


-- ---------------------------------------------------------------------
-- C. HOW FAR BACK CAN WE ACTUALLY GO?
--    Three candidate sources, smallest/longest first. The winner is
--    whichever gives the most fiscal years with a full store count.
--
--    NOTE on row counts (from the March doc dump):
--      WeeklySales             88,543 rows  -> ~11 years of weekly data
--      tbl_SalesDataByDayPart 879,726 rows  -> only ~3-4 years (daypart grain)
--      tbl_HstSalesSummary  27,727,832 rows -> long, but needs Type decoding
--    So WeeklySales is the expected winner for "as far back as we can get".
-- ---------------------------------------------------------------------

-- C1. WeeklySales coverage by fiscal year (the long-history candidate)
SELECT
    c.FiscalYear,
    COUNT(DISTINCT ws.WeekName)  AS WeeksWithData,
    COUNT(DISTINCT ws.StoreID)   AS StoresWithData,
    CAST(SUM(CONVERT(float, ws.Net)) AS decimal(18,2)) AS TotalNet
FROM dev_aloha.dbo.WeeklySales ws
JOIN (SELECT DISTINCT WeekName, FiscalYear
      FROM dev_aloha.dbo.CalendarV2
      WHERE WeekName IS NOT NULL AND FiscalYear IS NOT NULL) c
  ON c.WeekName = ws.WeekName
GROUP BY c.FiscalYear
ORDER BY c.FiscalYear;

-- C1b. Any WeekName in WeeklySales that does NOT match the calendar?
--      (orphans = weeks we would silently drop)
SELECT TOP 50
    ws.WeekName,
    COUNT(*) AS Rows_Orphaned
FROM dev_aloha.dbo.WeeklySales ws
WHERE NOT EXISTS (SELECT 1 FROM dev_aloha.dbo.CalendarV2 c
                  WHERE c.WeekName = ws.WeekName AND c.FiscalYear IS NOT NULL)
GROUP BY ws.WeekName
ORDER BY ws.WeekName;
-- (empty result = every week joins cleanly)

-- C2. tbl_SalesDataByDayPart coverage (the Flash Report source -- this is
--     what ties to the numbers Matt already sees, but shorter history)
SELECT
    FiscalYear,
    MIN(DateOfBusiness)         AS FirstDay,
    MAX(DateOfBusiness)         AS LastDay,
    COUNT(DISTINCT RestaurantID) AS StoresWithData,
    CAST(SUM(NetSales) AS decimal(18,2)) AS TotalNet
FROM dev_aloha.dbo.tbl_SalesDataByDayPart
GROUP BY FiscalYear
ORDER BY FiscalYear;

-- C3. tbl_HstSalesSummary coverage (deepest history, Aloha era, but the
--     Type/TypeId codes need decoding before it is usable for net sales)
SELECT
    YEAR(DateOfBusiness) AS CalYear,
    MIN(DateOfBusiness)  AS FirstDay,
    MAX(DateOfBusiness)  AS LastDay,
    COUNT(DISTINCT FKStoreId) AS Stores
FROM dev_aloha.dbo.tbl_HstSalesSummary
GROUP BY YEAR(DateOfBusiness)
ORDER BY CalYear;


-- ---------------------------------------------------------------------
-- D. TIE-OUT: does WeeklySales.Net mean the same thing as the Flash
--    Report's NetSales? Run this for the years where both exist. The
--    Diff column should be ~0 (a few dollars of rounding is fine).
--    If it is materially off, WeeklySales.Net is a different basis and
--    we anchor on tbl_SalesDataByDayPart instead.
-- ---------------------------------------------------------------------
;WITH cal AS (
    SELECT DISTINCT WeekName, FiscalYear
    FROM dev_aloha.dbo.CalendarV2
    WHERE WeekName IS NOT NULL AND FiscalYear IS NOT NULL
),
w AS (
    SELECT c.FiscalYear, SUM(CONVERT(float, ws.Net)) AS WeeklySalesNet
    FROM dev_aloha.dbo.WeeklySales ws
    JOIN cal c ON c.WeekName = ws.WeekName
    GROUP BY c.FiscalYear
),
d AS (
    SELECT FiscalYear, SUM(NetSales) AS FlashNet
    FROM dev_aloha.dbo.tbl_SalesDataByDayPart
    GROUP BY FiscalYear
)
SELECT
    COALESCE(w.FiscalYear, d.FiscalYear)              AS FiscalYear,
    CAST(w.WeeklySalesNet AS decimal(18,2))           AS WeeklySales_Net,
    CAST(d.FlashNet       AS decimal(18,2))           AS FlashReport_Net,
    CAST(w.WeeklySalesNet - d.FlashNet AS decimal(18,2)) AS Diff,
    CAST(100.0 * (w.WeeklySalesNet - d.FlashNet)
         / NULLIF(d.FlashNet, 0) AS decimal(8,4))     AS DiffPct
FROM w
FULL OUTER JOIN d ON d.FiscalYear = w.FiscalYear
ORDER BY FiscalYear;
