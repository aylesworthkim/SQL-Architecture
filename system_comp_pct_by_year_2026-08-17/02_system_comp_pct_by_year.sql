-- =====================================================================
-- TOTAL SYSTEM COMP % BY FISCAL YEAR                   for Matt Hayward
-- Rewritten 2026-08-17 against the ACTUAL probe results (script 01).
--
-- Matt's ask: one comp % per year, as far back as we can get. He has the
-- dollars but no per-year comp store list, and flagged the 13 -> 12
-- period calendar change in 2024.
--
-- SOURCE: dev_aloha.dbo.tbl_SalesDataByDayPart  (FY2014 -> FY2026)
--   Confirmed by the probe: 13 fiscal years, $211.1M in FY2025, and it
--   carries its own FiscalYear / FiscalWeek / DateOfBusiness per row.
--   This is the Flash Report's own source, so the numbers tie to what
--   Matt already sees. First comparable year is FY2015.
--
-- WHY NOT WeeklySales (which reaches back to 2004): its WeekName is the
--   OLD 13-period encoding ('Y2004_P02_WK2') and does NOT join to
--   CalendarV2.WeekName ('2005-01-02'). Probe grid C1 came back empty.
--   Script 03 parses that string instead to extend the series to ~2005.
--
-- ---------------------------------------------------------------------
-- WHAT THE PROBE CHANGED vs. the first draft of this script
-- ---------------------------------------------------------------------
-- a) NO CalendarV2 JOIN AT ALL. Probe grid B2 found 25 WeekNames that
--    map to TWO fiscal years (calendar boundary weeks), which would have
--    misassigned those weeks. tbl_SalesDataByDayPart already stamps each
--    DAY with its own FiscalYear, so day-level attribution is exact and
--    the boundary problem disappears.
--
-- b) THE 53-WEEK WORRY WAS THE WRONG WORRY. CalendarV2's fiscal years
--    are calendar-aligned at 364-366 DaysInYear -- never 371. So a
--    "53 week" year is just partial boundary weeks, not an extra week of
--    sales. But the DAY COUNT does move: FY2022 = 366 days, FY2023 = 364.
--    That is a ~0.55% swing, which absolutely matters when the answer is
--    "-0.8%". So this script reports raw AND day-adjusted comp.
--
-- c) SENTINEL DATES, NOT NULLS. contacts.dbo.Store uses '9999-01-01' for
--    "no close date" / "not open yet" -- there are ZERO NULLs. Any
--    "StoreCloseDate IS NULL" logic silently matches nothing.
--
-- d) FN_GetCompingDate IS NOT TRUSTWORTHY -- see script 04. It is not
--    used here. This script derives comp status from sales presence.
--
-- e) FY2026 IS PARTIAL (data through 2026-08-16). Each year pair is
--    clipped to the weeks BOTH years have, so FY2026 comes out as a
--    proper YTD-vs-YTD comp instead of a fake -40%.
--
-- EXPORT: run, then right-click grid 1 -> Save Results As -> CSV.
-- =====================================================================

-- =====================================================================
-- CLEANUP BATCH — must stay separated from the rest by its own GO.
-- Clears temp tables left by scripts 03/05 (or a prior run of this one)
-- in the same query window. SQL Server compiles a whole batch before
-- running any of it, so an inline "IF ... DROP TABLE" cannot save you
-- from a leftover table with different columns -- you get "Msg 213:
-- Column name or number of supplied values does not match table
-- definition" before the drop ever executes. Its own batch fixes that.
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

-- ===================== KNOBS ==========================================
-- Fraction of the compared days a store must have rung sales on, in BOTH
-- years, to count as comp. 0.95 gives a couple of weeks of grace for a
-- remodel or a hurricane. Set to 1.0 for the strictest reading.
DECLARE @MinDayFraction decimal(5,4) = 0.95;

-- Store scope. Leave NULL for TOTAL SYSTEM (company + franchise), which
-- is what Matt asked for. Or slice:  79 = company, 8 = franchise.
DECLARE @StoreGroupId int = NULL;
-- ======================================================================


-- ---------------------------------------------------------------------
-- 0. Non-restaurant records to drop. These are real rows in
--    contacts.dbo.Store that would pollute a system number.
--    NOTE: we deliberately do NOT exclude closed ("zClosed - ") stores.
--    A store that closed in 2022 was still a legitimate comp store in
--    2015-2021 and must stay in those years.
-- ---------------------------------------------------------------------
CREATE TABLE #notastore (StoreID int PRIMARY KEY, Reason varchar(60));

INSERT INTO #notastore (StoreID, Reason) VALUES
    (1,     'Dev Center (Do Not Report)'),
    (88888, 'Newk''s Eatery placeholder - open date 1970-01-01'),
    (9998,  'Newk''s Lab SC - test kitchen'),
    (9999,  'Newk''s Lab MS - test kitchen'),
    (5002,  'Rockwall TX - Virtual Site, not a restaurant'),
    (1200,  'Columbus MS - Upcoming, open date 9999-01-01'),
    (1201,  'Laurel MS - Upcoming, open date 9999-01-01');


-- ---------------------------------------------------------------------
-- 1. Day-level store sales. One row per store per day per fiscal year.
--    Rolled up off daypart. No calendar join needed.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#d') IS NOT NULL DROP TABLE #d;

SELECT
    d.FiscalYear,
    d.FiscalWeek,
    d.DateOfBusiness,
    d.RestaurantID          AS StoreID,
    SUM(d.NetSales)         AS Net
INTO #d
FROM dev_aloha.dbo.tbl_SalesDataByDayPart d
WHERE d.FiscalYear IS NOT NULL
  AND d.FiscalWeek IS NOT NULL
  AND d.RestaurantID NOT IN (SELECT StoreID FROM #notastore)
  AND (@StoreGroupId IS NULL
       OR d.RestaurantID IN (SELECT sgm.StoreId
                             FROM contacts.dbo.StoreGroupMembers sgm
                             WHERE sgm.StoreGroupId = @StoreGroupId))
GROUP BY d.FiscalYear, d.FiscalWeek, d.DateOfBusiness, d.RestaurantID;

CREATE CLUSTERED INDEX ix_d ON #d(FiscalYear, StoreID);


-- ---------------------------------------------------------------------
-- 2. How far each fiscal year actually runs in the DATA (not the
--    calendar). This is what makes the partial FY2026 behave.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#yr') IS NOT NULL DROP TABLE #yr;

SELECT
    FiscalYear,
    MAX(FiscalWeek)              AS MaxWeek,
    MIN(DateOfBusiness)          AS FirstDay,
    MAX(DateOfBusiness)          AS LastDay,
    COUNT(DISTINCT DateOfBusiness) AS DaysWithData
INTO #yr
FROM #d
GROUP BY FiscalYear;


-- ---------------------------------------------------------------------
-- 3. Year pairs, each clipped to the weeks BOTH years have.
--    For complete years this is a no-op. For FY2026 (partial) it turns
--    the comparison into YTD vs same-weeks-last-year.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#pairs') IS NOT NULL DROP TABLE #pairs;

SELECT
    ty.FiscalYear AS CompYear,
    CASE WHEN ty.MaxWeek <= ly.MaxWeek THEN ty.MaxWeek ELSE ly.MaxWeek END AS WeeksCompared,
    CASE WHEN ty.MaxWeek <  ly.MaxWeek THEN 1 ELSE 0 END AS IsPartialYear
INTO #pairs
FROM #yr ty
JOIN #yr ly ON ly.FiscalYear = ty.FiscalYear - 1;


-- ---------------------------------------------------------------------
-- 4. Days available in each side of each pair, inside the clipped
--    window. This is the FY2022=366 / FY2023=364 correction.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#days') IS NOT NULL DROP TABLE #days;

SELECT
    p.CompYear,
    COUNT(DISTINCT CASE WHEN d.FiscalYear = p.CompYear     THEN d.DateOfBusiness END) AS DaysTY,
    COUNT(DISTINCT CASE WHEN d.FiscalYear = p.CompYear - 1 THEN d.DateOfBusiness END) AS DaysLY
INTO #days
FROM #pairs p
JOIN #d d
  ON  d.FiscalYear IN (p.CompYear, p.CompYear - 1)
  AND d.FiscalWeek <= p.WeeksCompared
GROUP BY p.CompYear;


-- ---------------------------------------------------------------------
-- 5. Per store, per year pair: days open and dollars on both sides.
--    This single table drives every grid below.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#store') IS NOT NULL DROP TABLE #store;

SELECT
    p.CompYear,
    p.WeeksCompared,
    d.StoreID,
    COUNT(DISTINCT CASE WHEN d.FiscalYear = p.CompYear     AND d.Net > 0 THEN d.DateOfBusiness END) AS TyDaysOpen,
    COUNT(DISTINCT CASE WHEN d.FiscalYear = p.CompYear - 1 AND d.Net > 0 THEN d.DateOfBusiness END) AS LyDaysOpen,
    SUM(CASE WHEN d.FiscalYear = p.CompYear     THEN d.Net ELSE 0 END) AS TyNet,
    SUM(CASE WHEN d.FiscalYear = p.CompYear - 1 THEN d.Net ELSE 0 END) AS LyNet
INTO #store
FROM #pairs p
JOIN #d d
  ON  d.FiscalYear IN (p.CompYear, p.CompYear - 1)
  AND d.FiscalWeek <= p.WeeksCompared
GROUP BY p.CompYear, p.WeeksCompared, d.StoreID;

ALTER TABLE #store ADD IsComp bit NULL;

UPDATE s
SET IsComp = CASE
        WHEN s.TyDaysOpen >= dy.DaysTY * @MinDayFraction
         AND s.LyDaysOpen >= dy.DaysLY * @MinDayFraction
        THEN 1 ELSE 0
    END
FROM #store s
JOIN #days dy ON dy.CompYear = s.CompYear;


-- =====================================================================
-- GRID 1  <<== MATT'S ANSWER. One row per year, one comp %.
--
--   CompPct        = the headline number (FY2025 should land near -0.8)
--   CompPctDayAdj  = same thing corrected for unequal day counts. Use
--                    this one if DaysTY <> DaysLY, which is real: FY2023
--                    has 364 days against FY2022's 366.
--   IsPartialYear  = 1 means YTD-vs-YTD, not a full year (FY2026).
-- =====================================================================
SELECT
    s.CompYear                                              AS FiscalYear,
    dy.DaysLY                                               AS DaysPriorYear,
    dy.DaysTY                                               AS DaysThisYear,
    p.IsPartialYear,
    COUNT(*)                                                AS CompStores,
    CAST(SUM(s.LyNet) AS decimal(18,2))                     AS PriorYearNet,
    CAST(SUM(s.TyNet) AS decimal(18,2))                     AS ThisYearNet,
    CAST(SUM(s.TyNet) - SUM(s.LyNet) AS decimal(18,2))      AS DollarChange,
    CAST(100.0 * (SUM(s.TyNet) - SUM(s.LyNet))
         / NULLIF(SUM(s.LyNet), 0) AS decimal(6,2))         AS CompPct,
    CAST(100.0 * ((SUM(s.TyNet) / NULLIF(dy.DaysTY, 0))
                - (SUM(s.LyNet) / NULLIF(dy.DaysLY, 0)))
         / NULLIF(SUM(s.LyNet) / NULLIF(dy.DaysLY, 0), 0)
         AS decimal(6,2))                                   AS CompPctDayAdj
FROM #store s
JOIN #pairs p ON p.CompYear = s.CompYear
JOIN #days  dy ON dy.CompYear = s.CompYear
WHERE s.IsComp = 1
GROUP BY s.CompYear, dy.DaysTY, dy.DaysLY, p.IsPartialYear
ORDER BY s.CompYear;


-- =====================================================================
-- GRID 2  The comp store list per year -- the thing Matt said he does
--         not have. Save this too; it is his audit trail.
-- =====================================================================
SELECT
    s.CompYear         AS FiscalYear,
    s.StoreID,
    st.StoreName,
    st.StoreOpenDate,
    CASE WHEN st.StoreCloseDate >= '9999-01-01' THEN NULL
         ELSE st.StoreCloseDate END              AS StoreCloseDate,
    s.LyDaysOpen,
    s.TyDaysOpen,
    CAST(s.LyNet AS decimal(18,2)) AS PriorYearNet,
    CAST(s.TyNet AS decimal(18,2)) AS ThisYearNet,
    CAST(100.0 * (s.TyNet - s.LyNet)
         / NULLIF(s.LyNet, 0) AS decimal(8,2)) AS StoreCompPct
FROM #store s
LEFT JOIN contacts.dbo.Store st ON st.StoreID = s.StoreID
WHERE s.IsComp = 1
ORDER BY s.CompYear, s.StoreID;


-- =====================================================================
-- GRID 3  Everything EXCLUDED each year, with the reason and how many
--         days it missed. READ THIS BEFORE SENDING NUMBERS OUT.
--
--         A store that missed only a handful of days is very likely a
--         DATA GAP (missed poll), not a real closure -- and it will move
--         the system comp %. Cross-check any store whose open/close
--         dates do NOT explain the missing days. Sort by DaysShortfall
--         ascending and look at the small numbers first.
-- =====================================================================
SELECT
    s.CompYear         AS FiscalYear,
    s.StoreID,
    st.StoreName,
    st.StoreOpenDate,
    CASE WHEN st.StoreCloseDate >= '9999-01-01' THEN NULL
         ELSE st.StoreCloseDate END              AS StoreCloseDate,
    dy.DaysLY,
    s.LyDaysOpen,
    dy.DaysTY,
    s.TyDaysOpen,
    CASE WHEN (dy.DaysLY - s.LyDaysOpen) >= (dy.DaysTY - s.TyDaysOpen)
         THEN (dy.DaysLY - s.LyDaysOpen)
         ELSE (dy.DaysTY - s.TyDaysOpen) END     AS DaysShortfall,
    CASE
        WHEN s.LyDaysOpen = 0 THEN 'No prior-year sales - new opening'
        WHEN s.TyDaysOpen = 0 THEN 'No current-year sales - closed'
        WHEN s.LyDaysOpen <  dy.DaysLY * @MinDayFraction
             AND s.TyDaysOpen >= dy.DaysTY * @MinDayFraction
             THEN 'Partial prior year - opened mid-year'
        WHEN s.TyDaysOpen <  dy.DaysTY * @MinDayFraction
             AND s.LyDaysOpen >= dy.DaysLY * @MinDayFraction
             THEN 'Partial current year - closed or dark mid-year'
        ELSE 'Partial in both years'
    END                AS ExclusionReason,
    CAST(s.LyNet AS decimal(18,2)) AS PriorYearNet,
    CAST(s.TyNet AS decimal(18,2)) AS ThisYearNet
FROM #store s
JOIN #days dy ON dy.CompYear = s.CompYear
LEFT JOIN contacts.dbo.Store st ON st.StoreID = s.StoreID
WHERE s.IsComp = 0
  -- drop all-zero rows: the table carries some store-years with no sales
  -- on either side (e.g. 1038 in FY2022, 1028 in FY2023, 1174 in FY2025),
  -- which are just noise in an exclusion review.
  AND NOT (s.TyNet = 0 AND s.LyNet = 0)
ORDER BY s.CompYear, DaysShortfall, s.StoreID;


-- =====================================================================
-- GRID 4  Sensitivity. Same years, three strictness settings. If these
--         land within ~0.2 pts the number is solid whichever definition
--         Finance prefers. If they swing, send it with a caveat.
--
-- FIXED 2026-08-17: the strict column originally compared TyDaysOpen
-- against DaysTY, the count of distinct dates across ALL stores (364).
-- No individual store is ever open 364 days -- they close for holidays,
-- so a normal full year is ~358-360. The column returned 0 stores and a
-- NULL comp for every year. It now uses 0.99 of the busiest store's
-- actual day count, which is what "open all year" really means here.
-- =====================================================================
SELECT
    s.CompYear AS FiscalYear,

    SUM(CASE WHEN s.TyDaysOpen >= mx.MaxTyDays * 0.99
              AND s.LyDaysOpen >= mx.MaxLyDays * 0.99
             THEN 1 ELSE 0 END) AS Stores_Strict,
    CAST(100.0 * (SUM(CASE WHEN s.TyDaysOpen >= mx.MaxTyDays * 0.99 AND s.LyDaysOpen >= mx.MaxLyDays * 0.99 THEN s.TyNet ELSE 0 END)
                - SUM(CASE WHEN s.TyDaysOpen >= mx.MaxTyDays * 0.99 AND s.LyDaysOpen >= mx.MaxLyDays * 0.99 THEN s.LyNet ELSE 0 END))
         / NULLIF(SUM(CASE WHEN s.TyDaysOpen >= mx.MaxTyDays * 0.99 AND s.LyDaysOpen >= mx.MaxLyDays * 0.99 THEN s.LyNet ELSE 0 END), 0)
         AS decimal(6,2)) AS CompPct_Strict,

    SUM(CASE WHEN s.IsComp = 1 THEN 1 ELSE 0 END) AS Stores_Default,
    CAST(100.0 * (SUM(CASE WHEN s.IsComp = 1 THEN s.TyNet ELSE 0 END)
                - SUM(CASE WHEN s.IsComp = 1 THEN s.LyNet ELSE 0 END))
         / NULLIF(SUM(CASE WHEN s.IsComp = 1 THEN s.LyNet ELSE 0 END), 0)
         AS decimal(6,2)) AS CompPct_Default,

    SUM(CASE WHEN s.TyDaysOpen > 0 AND s.LyDaysOpen > 0 THEN 1 ELSE 0 END) AS Stores_Loose,
    CAST(100.0 * (SUM(CASE WHEN s.TyDaysOpen > 0 AND s.LyDaysOpen > 0 THEN s.TyNet ELSE 0 END)
                - SUM(CASE WHEN s.TyDaysOpen > 0 AND s.LyDaysOpen > 0 THEN s.LyNet ELSE 0 END))
         / NULLIF(SUM(CASE WHEN s.TyDaysOpen > 0 AND s.LyDaysOpen > 0 THEN s.LyNet ELSE 0 END), 0)
         AS decimal(6,2)) AS CompPct_Loose
FROM #store s
JOIN #days dy ON dy.CompYear = s.CompYear
JOIN (SELECT CompYear,
             MAX(TyDaysOpen) AS MaxTyDays,
             MAX(LyDaysOpen) AS MaxLyDays
      FROM #store GROUP BY CompYear) mx ON mx.CompYear = s.CompYear
GROUP BY s.CompYear
ORDER BY s.CompYear;


-- =====================================================================
-- GRID 5  Total system, ALL stores, no comp filter. Matt already has
--         these dollars, so this is the tie-out proving we are reading
--         the same source. Total growth runs ABOVE comp growth in any
--         year the system was net opening restaurants -- and BELOW it
--         through the 2016-2024 closure run.
-- =====================================================================
SELECT
    p.CompYear AS FiscalYear,
    COUNT(DISTINCT CASE WHEN d.FiscalYear = p.CompYear - 1 THEN d.StoreID END) AS Stores_PriorYear,
    COUNT(DISTINCT CASE WHEN d.FiscalYear = p.CompYear     THEN d.StoreID END) AS Stores_ThisYear,
    CAST(SUM(CASE WHEN d.FiscalYear = p.CompYear - 1 THEN d.Net ELSE 0 END) AS decimal(18,2)) AS AllStores_PriorYearNet,
    CAST(SUM(CASE WHEN d.FiscalYear = p.CompYear     THEN d.Net ELSE 0 END) AS decimal(18,2)) AS AllStores_ThisYearNet,
    CAST(100.0 * (SUM(CASE WHEN d.FiscalYear = p.CompYear     THEN d.Net ELSE 0 END)
                - SUM(CASE WHEN d.FiscalYear = p.CompYear - 1 THEN d.Net ELSE 0 END))
         / NULLIF(SUM(CASE WHEN d.FiscalYear = p.CompYear - 1 THEN d.Net ELSE 0 END), 0)
         AS decimal(6,2)) AS TotalSystemGrowthPct
FROM #pairs p
JOIN #d d
  ON  d.FiscalYear IN (p.CompYear, p.CompYear - 1)
  AND d.FiscalWeek <= p.WeeksCompared
GROUP BY p.CompYear
ORDER BY p.CompYear;


-- Cleanup (optional)
-- DROP TABLE #notastore, #d, #yr, #pairs, #days, #store;
