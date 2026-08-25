-- =====================================================================
-- VALIDATE THE DERIVED COMP SET AGAINST contacts.dbo.Store.StoreIsComping
--
-- "Total System" = all stores carrying the comp flag. No company/franchise
-- split -- that was my misreading, and it changes nothing in the numbers
-- because the scripts never applied an ownership filter.
--
-- The flag is the house definition of who comps. It just has no history:
-- it is ONE CURRENT-STATE BIT, rewritten over time by
-- dev_aloha.dbo.new01_Move_NonComping_To_Comping. So it answers "who is
-- comping now" but cannot answer "who was comping in 2018", which is why
-- the historical series has to be derived.
--
-- What this script does: check the derived set against the flag for
-- FY2025, the last complete year, where both are available.
--
-- Counting the roster by hand first gives 95 stores flagged comp, of which
-- 5 are stale (closed years ago, never un-flagged):
--     1165 Fort Worth (Presidio)   closed 2023-02-10
--     1116 Irving (Cypress Waters) closed 2023-01-20
--     1143 Austin (Congress Ave)   closed 2024-03-15
--     1150 Greenwood IN            closed 2024-03-30
--     1095 Lafayette LA            closed 2025-10-24
-- 95 - 5 = 90, and the derived FY2025 comp set is also 90. Grids below
-- confirm that store by store.
--
-- If grids 3 and 4 come back empty, the derived method reproduces the
-- house definition exactly and the whole series can be quoted with
-- confidence.
-- =====================================================================

IF OBJECT_ID('tempdb..#skipstore') IS NOT NULL DROP TABLE #skipstore;
IF OBJECT_ID('tempdb..#d')         IS NOT NULL DROP TABLE #d;
IF OBJECT_ID('tempdb..#sw')        IS NOT NULL DROP TABLE #sw;
IF OBJECT_ID('tempdb..#cap')       IS NOT NULL DROP TABLE #cap;
IF OBJECT_ID('tempdb..#paired')    IS NOT NULL DROP TABLE #paired;
IF OBJECT_ID('tempdb..#thresh')    IS NOT NULL DROP TABLE #thresh;
IF OBJECT_ID('tempdb..#derived')   IS NOT NULL DROP TABLE #derived;
IF OBJECT_ID('tempdb..#flagged')   IS NOT NULL DROP TABLE #flagged;
GO
-- ^^^ load-bearing GO.

SET NOCOUNT ON;

DECLARE @DayGrace     int = 1;
DECLARE @CompYear     int = 2025;   -- last complete fiscal year
DECLARE @MinWeekShare decimal(5,4) = 0.85;

CREATE TABLE #skipstore (StoreID int PRIMARY KEY);
INSERT INTO #skipstore (StoreID) VALUES (1),(88888),(9998),(9999),(5002),(1200),(1201);

-- Rebuild the derived comp set (same logic as script 06).
SELECT d.FiscalYear, d.FiscalWeek, d.DateOfBusiness,
       d.RestaurantID AS StoreID, SUM(d.NetSales) AS Net
INTO #d
FROM dev_aloha.dbo.tbl_SalesDataByDayPart d
WHERE d.FiscalYear IS NOT NULL AND d.FiscalWeek IS NOT NULL
  AND d.RestaurantID NOT IN (SELECT StoreID FROM #skipstore)
GROUP BY d.FiscalYear, d.FiscalWeek, d.DateOfBusiness, d.RestaurantID;

SELECT StoreID, FiscalYear, FiscalWeek,
       COUNT(DISTINCT CASE WHEN Net > 0 THEN DateOfBusiness END) AS DaysOpen,
       SUM(Net) AS Net
INTO #sw
FROM #d GROUP BY StoreID, FiscalYear, FiscalWeek;
CREATE CLUSTERED INDEX ix_sw ON #sw(StoreID, FiscalYear, FiscalWeek);

SELECT StoreID, FiscalYear, MAX(DaysOpen) AS BusiestWeekDays
INTO #cap FROM #sw GROUP BY StoreID, FiscalYear;
CREATE UNIQUE CLUSTERED INDEX ix_cap ON #cap(StoreID, FiscalYear);

SELECT ty.FiscalYear AS CompYear, ty.StoreID,
       COUNT(*) AS PairedWeeks, SUM(ty.Net) AS TyNet, SUM(ly.Net) AS LyNet
INTO #paired
FROM #sw ty
JOIN #cap cty ON cty.StoreID = ty.StoreID AND cty.FiscalYear = ty.FiscalYear
JOIN #sw ly ON ly.StoreID = ty.StoreID
           AND ly.FiscalYear = ty.FiscalYear - 1
           AND ly.FiscalWeek = ty.FiscalWeek
JOIN #cap cly ON cly.StoreID = ly.StoreID AND cly.FiscalYear = ly.FiscalYear
WHERE ty.DaysOpen >= cty.BusiestWeekDays - @DayGrace
  AND ly.DaysOpen >= cly.BusiestWeekDays - @DayGrace
GROUP BY ty.FiscalYear, ty.StoreID;

SELECT CompYear, CAST(MAX(PairedWeeks) * @MinWeekShare AS int) AS MinWeeksRequired
INTO #thresh FROM #paired GROUP BY CompYear;

SELECT p.StoreID, p.PairedWeeks, p.TyNet, p.LyNet
INTO #derived
FROM #paired p
JOIN #thresh t ON t.CompYear = p.CompYear
WHERE p.CompYear = @CompYear
  AND p.PairedWeeks >= t.MinWeeksRequired;

-- The flag set.
SELECT s.StoreID, s.StoreName, s.StoreOpenDate, s.StoreCloseDate, s.ToastLive
INTO #flagged
FROM contacts.dbo.Store s
WHERE s.StoreIsComping = 1
  AND s.StoreID NOT IN (SELECT StoreID FROM #skipstore);


-- =====================================================================
-- GRID 1  Headline reconciliation. Expect FlaggedTotal 95,
--         FlaggedStaleClosed 5, FlaggedStillOpen 90, DerivedCount 90.
-- =====================================================================
SELECT
    (SELECT COUNT(*) FROM #flagged)                                     AS FlaggedTotal,
    (SELECT COUNT(*) FROM #flagged WHERE StoreCloseDate < '9999-01-01') AS FlaggedStaleClosed,
    (SELECT COUNT(*) FROM #flagged WHERE StoreCloseDate >= '9999-01-01')AS FlaggedStillOpen,
    (SELECT COUNT(*) FROM #derived)                                     AS DerivedCompStores,
    @CompYear                                                           AS FiscalYearChecked;


-- =====================================================================
-- GRID 2  The stale flags. Closed, but still carrying StoreIsComping = 1.
--         This is the maintenance backlog on the flag itself, and the
--         reason it cannot be trusted as a historical record.
-- =====================================================================
SELECT StoreID, StoreName, StoreOpenDate, StoreCloseDate
FROM #flagged
WHERE StoreCloseDate < '9999-01-01'
ORDER BY StoreCloseDate;


-- =====================================================================
-- GRID 3  Flagged as comping but NOT in the derived FY2025 set.
--         Should be only the stale-closed ones. Anything else is a store
--         the derived method is wrongly leaving out -- investigate.
-- =====================================================================
SELECT
    f.StoreID,
    f.StoreName,
    f.StoreOpenDate,
    CASE WHEN f.StoreCloseDate >= '9999-01-01' THEN NULL
         ELSE f.StoreCloseDate END AS StoreCloseDate,
    f.ToastLive,
    ISNULL(p.PairedWeeks, 0)       AS PairedWeeks,
    t.MinWeeksRequired,
    CASE WHEN f.StoreCloseDate < '9999-01-01'
              THEN 'expected - stale flag on a closed store'
         WHEN p.StoreID IS NULL
              THEN 'NO PAIRED WEEKS AT ALL - investigate'
         ELSE 'short of the week threshold - investigate'
    END AS Verdict
FROM #flagged f
LEFT JOIN #paired p ON p.StoreID = f.StoreID AND p.CompYear = @CompYear
LEFT JOIN #thresh t ON t.CompYear = @CompYear
WHERE NOT EXISTS (SELECT 1 FROM #derived d WHERE d.StoreID = f.StoreID)
ORDER BY Verdict, f.StoreID;


-- =====================================================================
-- GRID 4  In the derived FY2025 set but NOT flagged as comping.
--         Should be empty. Anything here is a store the derived method
--         is counting that the business does not consider a comp store.
-- =====================================================================
SELECT
    d.StoreID,
    st.StoreName,
    st.StoreOpenDate,
    st.StoreIsComping,
    st.StoreStatus,
    d.PairedWeeks,
    CAST(d.LyNet AS decimal(18,2)) AS PriorYearNet,
    CAST(d.TyNet AS decimal(18,2)) AS ThisYearNet
FROM #derived d
LEFT JOIN contacts.dbo.Store st ON st.StoreID = d.StoreID
WHERE NOT EXISTS (SELECT 1 FROM #flagged f WHERE f.StoreID = d.StoreID)
ORDER BY d.StoreID;


-- =====================================================================
-- GRID 5  What the FY2025 comp % looks like computed BOTH ways, so you
--         can see whether the choice of store set actually moves the
--         number. The flag-based version uses the same paired-week
--         dollars, just filtered by StoreIsComping instead of by the
--         derived test.
-- =====================================================================
SELECT
    'Derived (paired-week test)' AS Method,
    COUNT(*)                                            AS CompStores,
    CAST(SUM(d.LyNet) AS decimal(18,2))                 AS PriorYearNet,
    CAST(SUM(d.TyNet) AS decimal(18,2))                 AS ThisYearNet,
    CAST(100.0 * (SUM(d.TyNet) - SUM(d.LyNet))
         / NULLIF(SUM(d.LyNet), 0) AS decimal(6,2))     AS CompPct
FROM #derived d

UNION ALL

SELECT
    'Flag (StoreIsComping = 1, still open)' AS Method,
    COUNT(*),
    CAST(SUM(p.LyNet) AS decimal(18,2)),
    CAST(SUM(p.TyNet) AS decimal(18,2)),
    CAST(100.0 * (SUM(p.TyNet) - SUM(p.LyNet))
         / NULLIF(SUM(p.LyNet), 0) AS decimal(6,2))
FROM #paired p
JOIN #flagged f ON f.StoreID = p.StoreID
WHERE p.CompYear = @CompYear
  AND f.StoreCloseDate >= '9999-01-01';


-- Cleanup (optional)
-- DROP TABLE #skipstore, #d, #sw, #cap, #paired, #thresh, #derived, #flagged;
