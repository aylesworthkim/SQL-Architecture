-- =====================================================================
-- DEEP HISTORY EXTENSION — comp % back to ~2005, from WeeklySales
--                                                      for Matt Hayward
--
-- Script 02 covers FY2015 -> FY2026 (limited by tbl_SalesDataByDayPart
-- starting in FY2014). Matt asked for "as far back as we can get", and
-- dev_aloha.dbo.WeeklySales goes back to 2004 -- Newk's had ONE store
-- then (1001 Oxford MS, opened 2004-02-02), which is why the probe's
-- orphan list showed exactly 1 row per 2004 week.
--
-- ---------------------------------------------------------------------
-- WHY THIS NEEDS ITS OWN SCRIPT: THE CALENDAR ENCODING
-- ---------------------------------------------------------------------
-- WeeklySales.WeekName is the OLD 13-PERIOD encoding:   'Y2004_P02_WK2'
-- CalendarV2.WeekName  is a date string:                '2005-01-02'
-- They do not join. That is why probe grid C1 returned nothing and grid
-- D showed WeeklySales_Net as NULL for all 13 years.
--
-- WeeklySales is in fact now the ONLY place the historical 13-period
-- calendar still survives -- CalendarV2 reports PeriodsInYear = 12 for
-- every year from 2004 through 2035, so it has been retro-fitted to the
-- new calendar and no longer describes how those years were actually
-- run. So we parse the string instead of joining.
--
--   'Y2004_P02_WK2'  (char(13), fixed width)
--    ^pos 2-5 = fiscal year
--          ^pos 8-9 = fiscal period (01-13)
--                ^pos 13 = week within period (1-5)
--
--   WeekOfYear = (Period - 1) * 4 + WeekInPeriod
--   ... so P13_WK5 = 53, the 53rd week in a 53-week year. Checks out.
--
-- ---------------------------------------------------------------------
-- READ THIS BEFORE SPLICING THE TWO SERIES TOGETHER
-- ---------------------------------------------------------------------
-- These are two DIFFERENT fiscal calendars. A 13-period year and a
-- 12-period year do not start and end on the same day, so this series
-- and script 02's series will NOT agree to the penny in the overlap
-- years -- and that is expected, not a bug.
--
-- Each series is internally consistent (year Y vs year Y-1 on the SAME
-- calendar), which is what a comp % needs. Grid 3 below shows the
-- overlap so you can see how close they run. If they track within a few
-- tenths, quote script 02 for FY2015+ and this one for the older years,
-- and tell Matt the pre-2015 numbers are on the legacy 13-period
-- calendar. Do not present one spliced column as a single basis.
-- =====================================================================

SET NOCOUNT ON;

DECLARE @MinWeekFraction decimal(5,4) = 0.95;


-- ---------------------------------------------------------------------
-- 0. Same non-restaurant exclusions as script 02.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#notastore2') IS NOT NULL DROP TABLE #notastore2;
CREATE TABLE #notastore2 (StoreID int PRIMARY KEY);
INSERT INTO #notastore2 (StoreID) VALUES (1),(88888),(9998),(9999),(5002),(1200),(1201);


-- ---------------------------------------------------------------------
-- 1. VALIDATE THE PARSE FIRST. Any row that does not match the expected
--    shape lands here. This grid should be EMPTY -- if it is not, fix
--    the parse before believing anything below it.
-- ---------------------------------------------------------------------
SELECT TOP 100
    ws.WeekName,
    COUNT(*) AS Rows_Unparseable
FROM dev_aloha.dbo.WeeklySales ws
WHERE RTRIM(ws.WeekName) NOT LIKE 'Y[0-9][0-9][0-9][0-9]|_P[0-9][0-9]|_WK[0-9]' ESCAPE '|'
GROUP BY ws.WeekName
ORDER BY ws.WeekName;


-- ---------------------------------------------------------------------
-- 2. Parse WeekName into fiscal year / period / week.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#w') IS NOT NULL DROP TABLE #w;

SELECT
    ws.StoreID,
    CAST(SUBSTRING(RTRIM(ws.WeekName), 2, 4) AS int)  AS FiscalYear,
    CAST(SUBSTRING(RTRIM(ws.WeekName), 8, 2) AS int)  AS FiscalPeriod,
    CAST(SUBSTRING(RTRIM(ws.WeekName), 13, 1) AS int) AS WeekInPeriod,
    (CAST(SUBSTRING(RTRIM(ws.WeekName), 8, 2) AS int) - 1) * 4
        + CAST(SUBSTRING(RTRIM(ws.WeekName), 13, 1) AS int) AS WeekOfYear,
    SUM(CONVERT(float, ws.Net)) AS Net
INTO #w
FROM dev_aloha.dbo.WeeklySales ws
WHERE RTRIM(ws.WeekName) LIKE 'Y[0-9][0-9][0-9][0-9]|_P[0-9][0-9]|_WK[0-9]' ESCAPE '|'
  AND ws.StoreID NOT IN (SELECT StoreID FROM #notastore2)
GROUP BY
    ws.StoreID,
    CAST(SUBSTRING(RTRIM(ws.WeekName), 2, 4) AS int),
    CAST(SUBSTRING(RTRIM(ws.WeekName), 8, 2) AS int),
    CAST(SUBSTRING(RTRIM(ws.WeekName), 13, 1) AS int);

CREATE CLUSTERED INDEX ix_w ON #w(FiscalYear, StoreID);


-- =====================================================================
-- GRID 1  Coverage sanity check. Confirm the parse produced sane years,
--         13 periods, and 52/53 weeks. MaxPeriod should be 13 (this is
--         the legacy calendar). Watch StoresWithData ramp 1 -> ~130.
-- =====================================================================
SELECT
    FiscalYear,
    MAX(FiscalPeriod)          AS MaxPeriod,
    MAX(WeekOfYear)            AS MaxWeek,
    COUNT(DISTINCT StoreID)    AS StoresWithData,
    CAST(SUM(Net) AS decimal(18,2)) AS TotalNet
FROM #w
GROUP BY FiscalYear
ORDER BY FiscalYear;


-- ---------------------------------------------------------------------
-- 3. Year pairs clipped to the weeks both years have, then per-store
--    presence and dollars. Same shape as script 02, weekly grain.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#wyr') IS NOT NULL DROP TABLE #wyr;
SELECT FiscalYear, MAX(WeekOfYear) AS MaxWeek
INTO #wyr FROM #w GROUP BY FiscalYear;

IF OBJECT_ID('tempdb..#wpairs') IS NOT NULL DROP TABLE #wpairs;
SELECT
    ty.FiscalYear AS CompYear,
    CASE WHEN ty.MaxWeek <= ly.MaxWeek THEN ty.MaxWeek ELSE ly.MaxWeek END AS WeeksCompared
INTO #wpairs
FROM #wyr ty
JOIN #wyr ly ON ly.FiscalYear = ty.FiscalYear - 1;

IF OBJECT_ID('tempdb..#wstore') IS NOT NULL DROP TABLE #wstore;
SELECT
    p.CompYear,
    p.WeeksCompared,
    w.StoreID,
    SUM(CASE WHEN w.FiscalYear = p.CompYear     AND w.Net > 0 THEN 1 ELSE 0 END) AS TyWeeksOpen,
    SUM(CASE WHEN w.FiscalYear = p.CompYear - 1 AND w.Net > 0 THEN 1 ELSE 0 END) AS LyWeeksOpen,
    SUM(CASE WHEN w.FiscalYear = p.CompYear     THEN w.Net ELSE 0 END)           AS TyNet,
    SUM(CASE WHEN w.FiscalYear = p.CompYear - 1 THEN w.Net ELSE 0 END)           AS LyNet
INTO #wstore
FROM #wpairs p
JOIN #w w
  ON  w.FiscalYear IN (p.CompYear, p.CompYear - 1)
  AND w.WeekOfYear <= p.WeeksCompared
GROUP BY p.CompYear, p.WeeksCompared, w.StoreID;


-- =====================================================================
-- GRID 2  <<== THE DEEP SERIES. Comp % by fiscal year, legacy
--              13-period calendar, back to the first year with a
--              prior year to compare against.
--
--   Expect the early years (2005-2010) to be wild -- a 2-store to
--   20-store system swings hard, and one strong new store dominates.
--   CompStores is the column that tells Matt how much weight to give
--   each year. Anything under ~10 stores is anecdote, not a system comp.
-- =====================================================================
SELECT
    s.CompYear                                          AS FiscalYear,
    s.WeeksCompared,
    COUNT(*)                                            AS CompStores,
    CAST(SUM(s.LyNet) AS decimal(18,2))                 AS PriorYearNet,
    CAST(SUM(s.TyNet) AS decimal(18,2))                 AS ThisYearNet,
    CAST(SUM(s.TyNet) - SUM(s.LyNet) AS decimal(18,2))  AS DollarChange,
    CAST(100.0 * (SUM(s.TyNet) - SUM(s.LyNet))
         / NULLIF(SUM(s.LyNet), 0) AS decimal(6,2))     AS CompPct
FROM #wstore s
WHERE s.TyWeeksOpen >= s.WeeksCompared * @MinWeekFraction
  AND s.LyWeeksOpen >= s.WeeksCompared * @MinWeekFraction
GROUP BY s.CompYear, s.WeeksCompared
ORDER BY s.CompYear;


-- =====================================================================
-- GRID 3  THE OVERLAP TEST -- the credibility check for this whole
--         script. Run script 02 first, save its grid 1, then compare
--         FY2015-FY2025 here.
--
--         Two different calendars, so do not expect an exact match. If
--         the two CompPct columns track within a few tenths of a point,
--         the deep pre-2015 series is trustworthy. If they diverge by
--         whole points in the overlap, do NOT send the pre-2015 numbers
--         -- something is wrong with either the parse or WeeklySales
--         itself, and script 02's range is all we can defend.
-- =====================================================================
SELECT
    s.CompYear                                      AS FiscalYear,
    COUNT(*)                                        AS CompStores_WeeklySales,
    CAST(SUM(s.LyNet) AS decimal(18,2))             AS PriorYearNet_WeeklySales,
    CAST(SUM(s.TyNet) AS decimal(18,2))             AS ThisYearNet_WeeklySales,
    CAST(100.0 * (SUM(s.TyNet) - SUM(s.LyNet))
         / NULLIF(SUM(s.LyNet), 0) AS decimal(6,2)) AS CompPct_WeeklySales
FROM #wstore s
WHERE s.TyWeeksOpen >= s.WeeksCompared * @MinWeekFraction
  AND s.LyWeeksOpen >= s.WeeksCompared * @MinWeekFraction
  AND s.CompYear >= 2015
GROUP BY s.CompYear
ORDER BY s.CompYear;


-- =====================================================================
-- GRID 4  Comp store list per year for the deep series (pre-2015 is the
--         part Matt has no other way to get).
-- =====================================================================
SELECT
    s.CompYear         AS FiscalYear,
    s.StoreID,
    st.StoreName,
    st.StoreOpenDate,
    CASE WHEN st.StoreCloseDate >= '9999-01-01' THEN NULL
         ELSE st.StoreCloseDate END AS StoreCloseDate,
    s.LyWeeksOpen,
    s.TyWeeksOpen,
    s.WeeksCompared,
    CAST(s.LyNet AS decimal(18,2)) AS PriorYearNet,
    CAST(s.TyNet AS decimal(18,2)) AS ThisYearNet
FROM #wstore s
LEFT JOIN contacts.dbo.Store st ON st.StoreID = s.StoreID
WHERE s.TyWeeksOpen >= s.WeeksCompared * @MinWeekFraction
  AND s.LyWeeksOpen >= s.WeeksCompared * @MinWeekFraction
ORDER BY s.CompYear, s.StoreID;


-- Cleanup (optional)
-- DROP TABLE #notastore2, #w, #wyr, #wpairs, #wstore;
