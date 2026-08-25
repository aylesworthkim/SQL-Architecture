-- =====================================================================
-- DIAGNOSE THE TWO PROBLEMS SCRIPT 02 SURFACED, AND FIX THE NUMBER
--                                                      for Matt Hayward
-- Written 2026-08-17 after reading script 02's output.
--
-- Script 02 returned FY2025 = -1.15%. Matt said -0.8%. Our number is
-- probably the wrong one, for a reason worth understanding:
--
-- ---------------------------------------------------------------------
-- PROBLEM 1 — 13 stores fell out of the FY2025 comp set for being
--             "dark" 19-34 days, and every one of them has a late-2025
--             ToastLive date.
-- ---------------------------------------------------------------------
-- From script 02 grid 3, FY2025 exclusions (TyDaysOpen out of 364):
--   1004 Tuscaloosa 345    1023 Panama City 344   1033 Waco 344
--   1037 Tallahassee 344   1039 Byram 343         1054 West Plano 343
--   1029 Huntsville W 342  1157 Columbus GA 342   1021 Shreveport 341
--   1184 Benton 340        1048 Bossier City 339  1182 Athens Epps 337
--   1036 Gulfport 330
--
-- Thirteen restaurants did not all go dark for a month in the same year.
-- This is the missed-poll pattern, almost certainly around each store's
-- Toast cutover. So FY2025 was computed on 77 comp stores when it should
-- be closer to 90, and the -1.15% is an artifact of dropping them.
--
-- Grids 1 and 2 below prove or disprove that by finding the actual
-- missing date ranges and lining them up against ToastLive.
--
-- ---------------------------------------------------------------------
-- PROBLEM 2 — StoreID reuse. contacts.dbo.Store holds only the CURRENT
--             occupant of each StoreID.
-- ---------------------------------------------------------------------
-- Script 02 grid 2 listed store 1053 "Knoxville TN (Cedar Bluff)",
-- StoreOpenDate 2024-08-12, as a comp store in FY2015. Also 1049
-- "Nashville Belle Meade" (opened 2018) in FY2015-16, and 1139
-- "Smyrna GA" (opened 2021) in FY2019-20.
--
-- Those IDs were occupied by DIFFERENT restaurants earlier. Newk's
-- reuses store numbers, and the Store row gets overwritten, so the name
-- and open date attached to old sales are wrong. Grid 3 finds every ID
-- this affects.
--
-- Impact on the comp number is smaller than it looks -- the sales
-- presence test mostly handles it, because a changeover leaves a gap
-- (1053 was correctly excluded in FY2024 and FY2025). The real damage is
-- that store NAMES and OPEN DATES in the comp list are wrong for older
-- years. But watch for the nasty case grid 4 checks: an old store
-- closing in December and a new one opening in January under the same
-- ID would look like one continuous comp store.
--
-- ---------------------------------------------------------------------
-- THE FIX — grid 5 computes a gap-robust comp % that does not throw a
--           store away just because it has a data hole.
-- ---------------------------------------------------------------------
-- Instead of requiring a store to be open ~all year, compare each store
-- only over the FISCAL WEEKS where it has good data in BOTH years. A
-- store dark for 3 weeks contributes its other 49 weeks, measured
-- against the same 49 weeks last year. Apples to apples, and the 13
-- Toast-gap stores come back in.
--
-- Run grid 5 alongside script 02 grid 1. Where they disagree, grid 5 is
-- the more defensible number -- but read grids 1-2 first so you know
-- WHY they disagree before you send anything.
-- =====================================================================

-- =====================================================================
-- CLEANUP BATCH — must stay separated from the rest by its own GO.
--
-- If you ran script 02 earlier in this same query window, it left
-- #notastore behind as a TWO-column table (StoreID, Reason). This script
-- wants it with one column. SQL Server compiles an entire batch BEFORE
-- executing any of it, so an inline "IF ... DROP TABLE" never gets the
-- chance to run -- the INSERT is validated against the stale definition
-- and you get:
--
--   Msg 213 ... Column name or number of supplied values does not match
--   table definition.
--
-- Putting the drops in their own batch (ended by GO) makes them actually
-- execute first, so everything below compiles against a clean slate.
-- Safe to run even if none of these exist.
-- =====================================================================
IF OBJECT_ID('tempdb..#notastore') IS NOT NULL DROP TABLE #notastore;
IF OBJECT_ID('tempdb..#skipstore') IS NOT NULL DROP TABLE #skipstore;
IF OBJECT_ID('tempdb..#d')         IS NOT NULL DROP TABLE #d;
IF OBJECT_ID('tempdb..#yr')        IS NOT NULL DROP TABLE #yr;
IF OBJECT_ID('tempdb..#pairs')     IS NOT NULL DROP TABLE #pairs;
IF OBJECT_ID('tempdb..#days')      IS NOT NULL DROP TABLE #days;
IF OBJECT_ID('tempdb..#store')     IS NOT NULL DROP TABLE #store;
IF OBJECT_ID('tempdb..#dates')     IS NOT NULL DROP TABLE #dates;
IF OBJECT_ID('tempdb..#span')      IS NOT NULL DROP TABLE #span;
IF OBJECT_ID('tempdb..#missing')   IS NOT NULL DROP TABLE #missing;
IF OBJECT_ID('tempdb..#gaps')      IS NOT NULL DROP TABLE #gaps;
IF OBJECT_ID('tempdb..#sw')        IS NOT NULL DROP TABLE #sw;
IF OBJECT_ID('tempdb..#paired')    IS NOT NULL DROP TABLE #paired;
GO
-- ^^^ the GO above is load-bearing. Do not delete it.

SET NOCOUNT ON;

DECLARE @MinDaysPerWeek  int = 6;   -- days of sales for a week to count
DECLARE @MinPairedWeeks  int = 45;  -- qualifying weeks to count as comp

-- Self-contained: rebuild the day-level table. Uses #skipstore (not
-- #notastore) so it can never collide with script 02 again, and names
-- the column explicitly on the INSERT.
CREATE TABLE #skipstore (StoreID int PRIMARY KEY);
INSERT INTO #skipstore (StoreID) VALUES (1),(88888),(9998),(9999),(5002),(1200),(1201);

SELECT
    d.FiscalYear,
    d.FiscalWeek,
    d.DateOfBusiness,
    d.RestaurantID   AS StoreID,
    SUM(d.NetSales)  AS Net
INTO #d
FROM dev_aloha.dbo.tbl_SalesDataByDayPart d
WHERE d.FiscalYear IS NOT NULL
  AND d.FiscalWeek IS NOT NULL
  AND d.RestaurantID NOT IN (SELECT StoreID FROM #skipstore)
GROUP BY d.FiscalYear, d.FiscalWeek, d.DateOfBusiness, d.RestaurantID;

CREATE CLUSTERED INDEX ix_d ON #d(StoreID, DateOfBusiness);


-- ---------------------------------------------------------------------
-- Find real GAPS: days with no sales that fall BETWEEN a store's first
-- and last sale of that fiscal year. This deliberately does not flag a
-- store that opened or closed mid-year -- those aren't gaps.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#dates') IS NOT NULL DROP TABLE #dates;
SELECT DISTINCT FiscalYear, DateOfBusiness INTO #dates FROM #d;
CREATE CLUSTERED INDEX ix_dates ON #dates(FiscalYear, DateOfBusiness);

IF OBJECT_ID('tempdb..#span') IS NOT NULL DROP TABLE #span;
SELECT FiscalYear, StoreID,
       MIN(DateOfBusiness) AS FirstSale,
       MAX(DateOfBusiness) AS LastSale
INTO #span
FROM #d
WHERE Net > 0
GROUP BY FiscalYear, StoreID;

IF OBJECT_ID('tempdb..#missing') IS NOT NULL DROP TABLE #missing;
SELECT s.StoreID, s.FiscalYear, dt.DateOfBusiness
INTO #missing
FROM #span s
JOIN #dates dt
  ON  dt.FiscalYear = s.FiscalYear
  AND dt.DateOfBusiness BETWEEN s.FirstSale AND s.LastSale
LEFT JOIN #d d
  ON  d.StoreID = s.StoreID
  AND d.DateOfBusiness = dt.DateOfBusiness
  AND d.Net > 0
WHERE d.StoreID IS NULL;

-- Collapse consecutive missing days into ranges.
IF OBJECT_ID('tempdb..#gaps') IS NOT NULL DROP TABLE #gaps;
SELECT
    StoreID,
    FiscalYear,
    MIN(DateOfBusiness) AS GapStart,
    MAX(DateOfBusiness) AS GapEnd,
    COUNT(*)            AS GapDays
INTO #gaps
FROM (
    SELECT
        StoreID, FiscalYear, DateOfBusiness,
        DATEADD(day,
            -ROW_NUMBER() OVER (PARTITION BY StoreID, FiscalYear
                                ORDER BY DateOfBusiness),
            DateOfBusiness) AS grp
    FROM #missing
) x
GROUP BY StoreID, FiscalYear, grp;


-- =====================================================================
-- GRID 1  <<== THE FY2025 SMOKING GUN. The 13 excluded stores, their
--              actual missing date ranges, and their ToastLive date.
--
--   DaysFromToastLive = GapStart minus ToastLive. A cluster of small
--   numbers (gap starts at or just after cutover) confirms the Toast
--   migration ate the data and these are NOT real closures.
--
--   If instead the gaps are scattered far from ToastLive, they may be
--   genuine -- go look at a couple in the Flash Report before deciding.
-- =====================================================================
SELECT
    g.StoreID,
    st.StoreName,
    g.GapStart,
    g.GapEnd,
    g.GapDays,
    st.ToastLive,
    DATEDIFF(day, st.ToastLive, g.GapStart) AS DaysFromToastLive,
    CASE
        WHEN st.ToastLive >= '9999-01-01' THEN 'never went Toast'
        WHEN g.GapStart BETWEEN DATEADD(day, -14, st.ToastLive)
                            AND DATEADD(day,  14, st.ToastLive)
            THEN 'GAP AT TOAST CUTOVER - data problem, not a closure'
        ELSE 'gap not near cutover - investigate'
    END AS Assessment
FROM #gaps g
LEFT JOIN contacts.dbo.Store st ON st.StoreID = g.StoreID
WHERE g.FiscalYear = 2025
ORDER BY g.GapDays DESC, g.StoreID;


-- =====================================================================
-- GRID 2  Same thing across ALL years -- total gap days per store per
--         year, worst first. This is the data-quality backlog. Any year
--         with a big pile of gap days has a comp % you cannot fully
--         trust until the polls are backfilled.
-- =====================================================================
SELECT
    g.FiscalYear,
    COUNT(DISTINCT g.StoreID)                     AS StoresWithGaps,
    SUM(g.GapDays)                                AS TotalGapDays,
    MAX(g.GapDays)                                AS WorstSingleGap,
    SUM(CASE WHEN g.GapDays >= 7  THEN 1 ELSE 0 END) AS Gaps_1WeekPlus,
    SUM(CASE WHEN g.GapDays >= 21 THEN 1 ELSE 0 END) AS Gaps_3WeeksPlus
FROM #gaps g
GROUP BY g.FiscalYear
ORDER BY g.FiscalYear;


-- =====================================================================
-- GRID 3  STOREID REUSE. Every ID whose sales history starts BEFORE the
--         open date on its Store row -- i.e. the row describes a later
--         occupant. Confirms 1053 / 1049 / 1139 and finds the rest.
--
--         Treat StoreName and StoreOpenDate in any historical report as
--         unreliable for these IDs.
-- =====================================================================
SELECT
    d.StoreID,
    st.StoreName                AS CurrentOccupantName,
    st.StoreOpenDate            AS CurrentOccupantOpenDate,
    MIN(d.DateOfBusiness)       AS FirstSaleInData,
    MAX(d.DateOfBusiness)       AS LastSaleInData,
    DATEDIFF(year, MIN(d.DateOfBusiness), st.StoreOpenDate) AS YearsOfHistoryBeforeOpenDate
FROM #d d
JOIN contacts.dbo.Store st ON st.StoreID = d.StoreID
WHERE d.Net > 0
  AND st.StoreOpenDate < '9999-01-01'
GROUP BY d.StoreID, st.StoreName, st.StoreOpenDate
HAVING MIN(d.DateOfBusiness) < DATEADD(day, -30, st.StoreOpenDate)
ORDER BY MIN(d.DateOfBusiness);


-- =====================================================================
-- GRID 4  The dangerous reuse case: a long mid-history blackout on an
--         ID, meaning one restaurant closed and another opened under the
--         same number. Any comp year that STRADDLES one of these breaks
--         is comparing two different restaurants.
--
--         Cross-check these StoreIDs against script 02 grid 2. A break
--         entirely inside one fiscal year is safe (the presence test
--         drops it). A break that lands near a year boundary is not.
-- =====================================================================
SELECT
    g.StoreID,
    st.StoreName        AS CurrentOccupantName,
    st.StoreOpenDate    AS CurrentOccupantOpenDate,
    g.FiscalYear        AS BreakInFiscalYear,
    g.GapStart,
    g.GapEnd,
    g.GapDays,
    CASE WHEN g.GapDays >= 120 THEN 'LIKELY CHANGE OF OCCUPANT'
         ELSE 'long closure or remodel' END AS Assessment
FROM #gaps g
LEFT JOIN contacts.dbo.Store st ON st.StoreID = g.StoreID
WHERE g.GapDays >= 60
ORDER BY g.GapDays DESC;


-- =====================================================================
-- GRID 5  <<== THE GAP-ROBUST COMP %. Compare each store only over the
--              fiscal weeks where it has good data in BOTH years.
--
--   Weeks needing >= @MinDaysPerWeek days of sales in both years to
--   count. A store dark 3 weeks contributes its other 49, matched
--   against the same 49 last year -- so the 13 Toast-gap stores come
--   back into FY2025 instead of being dropped.
--
--   AvgPairedWeeks tells you how much window each store contributed.
--   Compare CompStores here against script 02 grid 1: FY2025 should
--   jump from 77 toward ~90.
-- =====================================================================
IF OBJECT_ID('tempdb..#sw') IS NOT NULL DROP TABLE #sw;
SELECT
    StoreID,
    FiscalYear,
    FiscalWeek,
    COUNT(DISTINCT CASE WHEN Net > 0 THEN DateOfBusiness END) AS DaysOpen,
    SUM(Net) AS Net
INTO #sw
FROM #d
GROUP BY StoreID, FiscalYear, FiscalWeek;

CREATE CLUSTERED INDEX ix_sw ON #sw(StoreID, FiscalYear, FiscalWeek);

IF OBJECT_ID('tempdb..#paired') IS NOT NULL DROP TABLE #paired;
SELECT
    ty.FiscalYear AS CompYear,
    ty.StoreID,
    COUNT(*)          AS PairedWeeks,
    SUM(ty.Net)       AS TyNet,
    SUM(ly.Net)       AS LyNet
INTO #paired
FROM #sw ty
JOIN #sw ly
  ON  ly.StoreID    = ty.StoreID
  AND ly.FiscalYear = ty.FiscalYear - 1
  AND ly.FiscalWeek = ty.FiscalWeek
WHERE ty.DaysOpen >= @MinDaysPerWeek
  AND ly.DaysOpen >= @MinDaysPerWeek
GROUP BY ty.FiscalYear, ty.StoreID;

SELECT
    p.CompYear                                          AS FiscalYear,
    COUNT(*)                                            AS CompStores,
    AVG(p.PairedWeeks)                                  AS AvgPairedWeeks,
    MIN(p.PairedWeeks)                                  AS MinPairedWeeks,
    CAST(SUM(p.LyNet) AS decimal(18,2))                 AS PriorYearNet,
    CAST(SUM(p.TyNet) AS decimal(18,2))                 AS ThisYearNet,
    CAST(SUM(p.TyNet) - SUM(p.LyNet) AS decimal(18,2))  AS DollarChange,
    CAST(100.0 * (SUM(p.TyNet) - SUM(p.LyNet))
         / NULLIF(SUM(p.LyNet), 0) AS decimal(6,2))     AS CompPct_GapRobust
FROM #paired p
WHERE p.PairedWeeks >= @MinPairedWeeks
GROUP BY p.CompYear
ORDER BY p.CompYear;


-- =====================================================================
-- GRID 6  Which stores grid 5 rescued that script 02 dropped, for
--         FY2025 specifically. These should be the 13 Toast-gap stores.
--         Their StoreCompPct is what they contribute once measured on a
--         like-for-like window.
-- =====================================================================
SELECT
    p.StoreID,
    st.StoreName,
    st.ToastLive,
    p.PairedWeeks,
    CAST(p.LyNet AS decimal(18,2)) AS PriorYearNet_PairedWeeks,
    CAST(p.TyNet AS decimal(18,2)) AS ThisYearNet_PairedWeeks,
    CAST(100.0 * (p.TyNet - p.LyNet)
         / NULLIF(p.LyNet, 0) AS decimal(8,2)) AS StoreCompPct
FROM #paired p
LEFT JOIN contacts.dbo.Store st ON st.StoreID = p.StoreID
WHERE p.CompYear = 2025
  AND p.PairedWeeks >= @MinPairedWeeks
  AND p.StoreID IN (1004,1023,1033,1037,1039,1054,1029,1157,1021,1184,1048,1182,1036)
ORDER BY p.StoreID;


-- Cleanup (optional -- the cleanup batch at the top handles this on the
-- next run anyway)
-- DROP TABLE #skipstore, #d, #dates, #span, #missing, #gaps, #sw, #paired;
