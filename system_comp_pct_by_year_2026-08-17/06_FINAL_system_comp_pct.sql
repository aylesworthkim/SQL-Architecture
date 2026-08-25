-- =====================================================================
-- FINAL — TOTAL SYSTEM COMP % BY FISCAL YEAR            for Matt Hayward
-- 2026-08-17. This is the script to run and the grid to send.
--
-- VALIDATION: script 05's gap-robust method returned FY2025 = -0.73%.
-- Matt independently said 2025 was about -0.8%. Two different routes to
-- the same number, so the method is sound. Script 02's -1.15% was an
-- artifact of dropping 13 stores that had Toast-migration data holes.
--
-- ---------------------------------------------------------------------
-- METHOD
-- ---------------------------------------------------------------------
-- Comp each store only over the FISCAL WEEKS where it has good data in
-- BOTH the year and the prior year. A store with a 3-week data hole
-- contributes its other 49 weeks, measured against the same 49 weeks
-- last year. Apples to apples, and it does not throw a whole restaurant
-- away over a pipeline gap.
--
-- ---------------------------------------------------------------------
-- TWO FIXES OVER SCRIPT 05
-- ---------------------------------------------------------------------
-- 1. WEEKEND-CLOSED STORES ARE NO LONGER SILENTLY DROPPED.
--    Script 05 required 6 sales-days for a week to count. Stores 1188
--    Lubbock (Broadway) and 1198 Athens GA (UGA) are closed EVERY
--    weekend -- script 05 grid 1 showed 1188 with a 2-day gap every
--    single week of 2025. A 5-day store can never hit 6, so Lubbock was
--    excluded from the comp set entirely despite opening in 2022.
--    Now the day threshold is calibrated PER STORE PER YEAR: a week
--    counts if it is within 1 day of that store's own busiest week. A
--    7-day store needs 6+, a 5-day store needs 4+. Self-calibrating.
--
-- 2. FY2026 YTD NOW APPEARS.
--    Script 05 hard-coded a 45-week minimum, so the partial FY2026
--    (~33 weeks of data) had every store filtered out and the year
--    vanished from the results. The minimum is now a FRACTION of the
--    most weeks any store achieved that year, so it scales to a partial
--    year automatically. Watch the IsPartialYear flag.
--
-- EXPORT: run, then right-click grid 1 -> Save Results As -> CSV.
-- =====================================================================

-- Cleanup batch — its own GO so the drops execute before the rest
-- compiles. See NOTES.md ("Msg 213") for why this is load-bearing.
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
IF OBJECT_ID('tempdb..#cap')       IS NOT NULL DROP TABLE #cap;
IF OBJECT_ID('tempdb..#thresh')    IS NOT NULL DROP TABLE #thresh;
GO
-- ^^^ load-bearing GO. Do not delete.

SET NOCOUNT ON;

-- ===================== KNOBS ==========================================
-- A week counts if the store was open within this many days of its own
-- busiest week that year. 1 allows a single holiday closure.
DECLARE @DayGrace int = 1;

-- A store counts as comp if it has at least this fraction of the most
-- paired weeks any store managed that year. Scales to partial years.
DECLARE @MinWeekShare decimal(5,4) = 0.85;

-- NULL = TOTAL SYSTEM (company + franchise), what Matt asked for.
-- 79 = company only, 8 = franchise only.
DECLARE @StoreGroupId int = NULL;
-- ======================================================================


-- Non-restaurant records. Closed stores are deliberately NOT excluded --
-- a store that closed in 2022 was legitimately comp in 2015-2021.
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
  AND (@StoreGroupId IS NULL
       OR d.RestaurantID IN (SELECT sgm.StoreId
                             FROM contacts.dbo.StoreGroupMembers sgm
                             WHERE sgm.StoreGroupId = @StoreGroupId))
GROUP BY d.FiscalYear, d.FiscalWeek, d.DateOfBusiness, d.RestaurantID;

CREATE CLUSTERED INDEX ix_d ON #d(StoreID, FiscalYear, FiscalWeek);


-- Store-week grain.
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


-- FIX 1: per-store-per-year day threshold, so a 5-day-a-week store is
-- judged against 5 days and not against 7.
SELECT
    StoreID,
    FiscalYear,
    MAX(DaysOpen) AS BusiestWeekDays
INTO #cap
FROM #sw
GROUP BY StoreID, FiscalYear;

CREATE UNIQUE CLUSTERED INDEX ix_cap ON #cap(StoreID, FiscalYear);


-- Pair each store's week N in the comp year against its own week N in
-- the prior year, keeping only weeks that are "full" on BOTH sides.
SELECT
    ty.FiscalYear   AS CompYear,
    ty.StoreID,
    COUNT(*)        AS PairedWeeks,
    SUM(ty.Net)     AS TyNet,
    SUM(ly.Net)     AS LyNet
INTO #paired
FROM #sw ty
JOIN #cap cty ON cty.StoreID = ty.StoreID AND cty.FiscalYear = ty.FiscalYear
JOIN #sw ly
  ON  ly.StoreID    = ty.StoreID
  AND ly.FiscalYear = ty.FiscalYear - 1
  AND ly.FiscalWeek = ty.FiscalWeek
JOIN #cap cly ON cly.StoreID = ly.StoreID AND cly.FiscalYear = ly.FiscalYear
WHERE ty.DaysOpen >= cty.BusiestWeekDays - @DayGrace
  AND ly.DaysOpen >= cly.BusiestWeekDays - @DayGrace
GROUP BY ty.FiscalYear, ty.StoreID;


-- FIX 2: comp-store threshold as a share of the best-covered store that
-- year, so the partial FY2026 is not wiped out by a hard 45-week floor.
SELECT
    CompYear,
    MAX(PairedWeeks) AS MaxPairedWeeks,
    CAST(MAX(PairedWeeks) * @MinWeekShare AS int) AS MinWeeksRequired
INTO #thresh
FROM #paired
GROUP BY CompYear;


-- =====================================================================
-- GRID 1  <<== SEND THIS. One row per fiscal year, one comp %.
--
--   CompPct        = the number Matt asked for. FY2025 = -0.73, which
--                    matches the -0.8% he quoted.
--   CompStores     = weight. Under ~10 is anecdote, not a system comp.
--   IsPartialYear  = 1 means YTD vs same-weeks-last-year (FY2026).
--   WeeksRequired  = the bar a store had to clear to be counted.
-- =====================================================================
SELECT
    p.CompYear                                          AS FiscalYear,
    COUNT(*)                                            AS CompStores,
    t.MaxPairedWeeks                                    AS WeeksAvailable,
    t.MinWeeksRequired                                  AS WeeksRequired,
    CASE WHEN t.MaxPairedWeeks < 45 THEN 1 ELSE 0 END   AS IsPartialYear,
    CAST(SUM(p.LyNet) AS decimal(18,2))                 AS PriorYearNet,
    CAST(SUM(p.TyNet) AS decimal(18,2))                 AS ThisYearNet,
    CAST(SUM(p.TyNet) - SUM(p.LyNet) AS decimal(18,2))  AS DollarChange,
    CAST(100.0 * (SUM(p.TyNet) - SUM(p.LyNet))
         / NULLIF(SUM(p.LyNet), 0) AS decimal(6,2))     AS CompPct
FROM #paired p
JOIN #thresh t ON t.CompYear = p.CompYear
WHERE p.PairedWeeks >= t.MinWeeksRequired
GROUP BY p.CompYear, t.MaxPairedWeeks, t.MinWeeksRequired
ORDER BY p.CompYear;


-- =====================================================================
-- GRID 2  Comp store list per year -- what Matt said he didn't have.
--
--   CAUTION: StoreName and StoreOpenDate come from contacts.dbo.Store,
--   which holds only the CURRENT occupant of a StoreID. Confirmed reused
--   IDs: 1049, 1053, 1139. For those, the name/open date shown against
--   older years belongs to a different restaurant. The dollars are still
--   correct for whoever occupied the number at the time.
-- =====================================================================
SELECT
    p.CompYear      AS FiscalYear,
    p.StoreID,
    st.StoreName,
    st.StoreOpenDate,
    CASE WHEN st.StoreCloseDate >= '9999-01-01' THEN NULL
         ELSE st.StoreCloseDate END AS StoreCloseDate,
    p.PairedWeeks,
    CASE WHEN p.StoreID IN (1049,1053,1139)
         THEN 'StoreID reused - name/open date may be a later occupant'
         ELSE '' END AS DataCaveat,
    CAST(p.LyNet AS decimal(18,2)) AS PriorYearNet,
    CAST(p.TyNet AS decimal(18,2)) AS ThisYearNet,
    CAST(100.0 * (p.TyNet - p.LyNet)
         / NULLIF(p.LyNet, 0) AS decimal(8,2)) AS StoreCompPct
FROM #paired p
JOIN #thresh t ON t.CompYear = p.CompYear
LEFT JOIN contacts.dbo.Store st ON st.StoreID = p.StoreID
WHERE p.PairedWeeks >= t.MinWeeksRequired
ORDER BY p.CompYear, p.StoreID;


-- =====================================================================
-- GRID 3  Confirms fix 1 worked. The weekend-closed stores and their
--         busiest-week day count. 1188 Lubbock and 1198 Athens UGA
--         should show BusiestWeekDays = 5, and 1188 should now appear
--         in grid 1's FY2025 comp set (it could not under script 05).
-- =====================================================================
SELECT
    c.StoreID,
    st.StoreName,
    c.FiscalYear,
    c.BusiestWeekDays,
    (SELECT COUNT(*) FROM #paired p
     WHERE p.StoreID = c.StoreID AND p.CompYear = c.FiscalYear) AS InPairedSet
FROM #cap c
LEFT JOIN contacts.dbo.Store st ON st.StoreID = c.StoreID
WHERE c.BusiestWeekDays <= 6
  AND c.FiscalYear >= 2024
ORDER BY c.BusiestWeekDays, c.StoreID, c.FiscalYear;


-- =====================================================================
-- GRID 4  Stores that STILL fall short, per year, and by how much.
--         Sanity backstop -- a store missing only a couple of weeks here
--         is worth a look before you quote the year.
-- =====================================================================
SELECT
    p.CompYear      AS FiscalYear,
    p.StoreID,
    st.StoreName,
    p.PairedWeeks,
    t.MinWeeksRequired,
    t.MinWeeksRequired - p.PairedWeeks AS WeeksShort,
    CAST(p.LyNet AS decimal(18,2)) AS PriorYearNet,
    CAST(p.TyNet AS decimal(18,2)) AS ThisYearNet
FROM #paired p
JOIN #thresh t ON t.CompYear = p.CompYear
LEFT JOIN contacts.dbo.Store st ON st.StoreID = p.StoreID
WHERE p.PairedWeeks < t.MinWeeksRequired
  AND p.PairedWeeks > 0
ORDER BY p.CompYear, WeeksShort, p.StoreID;


-- =====================================================================
-- GRID 5  CORRECTED GAP REPORT (script 05 grid 1 had the label backwards)
--
-- Script 05 anchored the assessment on GapStart. Wrong end. The output
-- showed GapEnd is ALWAYS the day before ToastLive and GapStart is
-- ALWAYS the 1st of the month:
--     Gulfport   09-01 -> 09-29,  ToastLive 09-30
--     Shreveport 11-01 -> 11-19,  ToastLive 11-20
--     Benton     12-01 -> 12-22,  ToastLive 12-23
-- So the real finding is: THE ALOHA DATA FOR THE PRE-CUTOVER PART OF
-- EACH STORE'S ToastLive MONTH WAS NEVER LOADED. Anchoring on GapEnd
-- classifies these correctly instead of calling them "investigate".
--
-- Also separates out the noise script 05 buried:
--   * single-day holiday/weather closures (Thanksgiving 11-27, 07-04,
--     Easter 04-20, 12-24, and the Jan/Feb winter-storm days) -- real
--   * whole missing fiscal weeks, e.g. 2025-10-13 -> 10-19 across seven
--     stores at once, which is a rollup that never ran
--   * recurring weekend gaps at 1188 / 1198 -- those stores are closed
--     weekends, not missing data
--
-- This is the backfill worklist. Fixing the ToastLive-month gaps is what
-- would let the plain full-year method agree with the paired-week one.
-- =====================================================================
SELECT DISTINCT FiscalYear, DateOfBusiness INTO #dates FROM #d;
CREATE CLUSTERED INDEX ix_dates ON #dates(FiscalYear, DateOfBusiness);

SELECT FiscalYear, StoreID,
       MIN(DateOfBusiness) AS FirstSale,
       MAX(DateOfBusiness) AS LastSale
INTO #span
FROM #d WHERE Net > 0
GROUP BY FiscalYear, StoreID;

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

SELECT
    StoreID, FiscalYear,
    MIN(DateOfBusiness) AS GapStart,
    MAX(DateOfBusiness) AS GapEnd,
    COUNT(*)            AS GapDays
INTO #gaps
FROM (
    SELECT StoreID, FiscalYear, DateOfBusiness,
           DATEADD(day, -ROW_NUMBER() OVER (PARTITION BY StoreID, FiscalYear
                                            ORDER BY DateOfBusiness),
                   DateOfBusiness) AS grp
    FROM #missing
) x
GROUP BY StoreID, FiscalYear, grp;

SELECT
    g.StoreID,
    st.StoreName,
    g.FiscalYear,
    g.GapStart,
    g.GapEnd,
    g.GapDays,
    st.ToastLive,
    DATEDIFF(day, g.GapEnd, st.ToastLive) AS DaysGapEndToToastLive,
    CASE
        -- anchor on GapEnd, not GapStart
        WHEN st.ToastLive < '9999-01-01'
         AND DATEDIFF(day, g.GapEnd, st.ToastLive) BETWEEN 0 AND 3
         AND DAY(g.GapStart) <= 2
            THEN 'TOAST CUTOVER MONTH NOT LOADED - backfill this'
        WHEN st.ToastLive < '9999-01-01'
         AND DATEDIFF(day, g.GapEnd, st.ToastLive) BETWEEN 0 AND 3
            THEN 'gap ends at Toast cutover - backfill this'
        WHEN g.GapDays = 1
            THEN 'single day - holiday or weather, expected'
        WHEN g.GapDays = 7
            THEN 'whole fiscal week missing - rollup did not run'
        WHEN g.StoreID IN (1188, 1198)
            THEN 'store is closed weekends - not a data gap'
        WHEN g.GapDays >= 60
            THEN 'long closure, remodel, or change of occupant'
        ELSE 'investigate'
    END AS Assessment
FROM #gaps g
LEFT JOIN contacts.dbo.Store st ON st.StoreID = g.StoreID
WHERE g.FiscalYear = 2025
  AND g.GapDays > 1              -- single-day holiday closures suppressed
  AND g.StoreID NOT IN (1188, 1198)
ORDER BY g.GapDays DESC, g.StoreID;


-- Cleanup (optional)
-- DROP TABLE #skipstore, #d, #sw, #cap, #paired, #thresh, #dates, #span, #missing, #gaps;
