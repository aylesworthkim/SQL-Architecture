-- =====================================================================
-- RECOVER THE COMP FLAG'S HISTORY FROM THE AUDIT TRAIL
--
-- Kim's point: which stores carry the comp flag CHANGES from year to
-- year. Exactly right, and it's the reason the current flag can't be
-- applied backwards -- and also the reason my "90 flagged = 90 derived"
-- match only validates FY2025. For FY2015-2024 there was no ground truth
-- to check against at all, so those years rest on the method being sound
-- rather than on any verification.
--
-- Unless the flips were audited. And there is a trigger:
--
--   contacts.dbo.trg_Store_Identify_Updated_Columns
--       on table Store, for INSERT, UPDATE, DELETE
--
-- plus contacts.dbo.AuditDataChanges with exactly the right shape:
--   RecordId, TableName, RecordPK, ColumnName, OldValue, NewValue,
--   ChangeDate, UpdatedBy
--
-- If that trigger has been recording StoreIsComping changes, the flag's
-- history is replayable and we can rebuild the ACTUAL comp store list for
-- each past year -- real ground truth, not inference.
--
-- CAVEAT TO CHECK FIRST: the trigger's date in the March doc dump reads
-- 2024-09-05. If that is its CREATE date rather than a modify date, the
-- audit may only reach back to late 2024, which would validate FY2025 and
-- FY2026 but not the earlier years. Part A tells us which.
--
-- Run Part A first and read it before running B or C.
-- =====================================================================


-- #####################################################################
-- PART A — DISCOVERY. Does the audit capture this column, and how far
--          back does it go? Nothing here assumes a table shape.
-- #####################################################################

-- A1. Which audit-style tables actually exist, and in which database?
--     Column names differ between them (contacts uses ColumnName /
--     ChangeDate; dev_aloha.dbo.Audit uses FieldName / UpdateDate), so
--     confirm the shape before trusting Part B.
SELECT 'contacts' AS DbName, t.name AS TableName, c.name AS ColumnName,
       c.column_id, ty.name AS DataType
FROM contacts.sys.tables t
JOIN contacts.sys.columns c ON c.object_id = t.object_id
JOIN contacts.sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN ('AuditDataChanges','Audit')
UNION ALL
SELECT 'dev_aloha', t.name, c.name, c.column_id, ty.name
FROM dev_aloha.sys.tables t
JOIN dev_aloha.sys.columns c ON c.object_id = t.object_id
JOIN dev_aloha.sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN ('AuditDataChanges','Audit')
ORDER BY DbName, TableName, column_id;


-- A2. The trigger itself. Is it enabled, and when was it really created?
--     create_date is the answer to the caveat above.
SELECT
    tr.name              AS TriggerName,
    OBJECT_NAME(tr.parent_id) AS OnTable,
    tr.is_disabled,
    tr.create_date,
    tr.modify_date
FROM contacts.sys.triggers tr
WHERE OBJECT_NAME(tr.parent_id) = 'Store'
ORDER BY tr.name;

-- A2b. What the trigger actually writes -- confirms it targets
--      AuditDataChanges and whether it logs every column or a subset.
EXEC contacts.dbo.sp_helptext 'dbo.trg_Store_Identify_Updated_Columns';


-- A3. THE KEY QUESTION. Is StoreIsComping in the audit, and how deep?
--     If RowsCaptured is 0, stop -- the flag's history is genuinely gone
--     and the derived series is the only option (say so to Matt).
SELECT
    COUNT(*)                                  AS RowsCaptured,
    COUNT(DISTINCT a.RecordPK)                AS DistinctStores,
    MIN(a.ChangeDate)                         AS EarliestChange,
    MAX(a.ChangeDate)                         AS LatestChange,
    COUNT(DISTINCT YEAR(a.ChangeDate))        AS YearsCovered
FROM contacts.dbo.AuditDataChanges a
WHERE a.TableName = 'Store'
  AND a.ColumnName = 'StoreIsComping';


-- A4. Coverage by year, so you can see exactly which fiscal years the
--     audit can actually speak to.
SELECT
    YEAR(a.ChangeDate)          AS ChangeYear,
    COUNT(*)                    AS Flips,
    COUNT(DISTINCT a.RecordPK)  AS StoresAffected,
    SUM(CASE WHEN a.NewValue IN ('1','True') THEN 1 ELSE 0 END) AS TurnedOn,
    SUM(CASE WHEN a.NewValue IN ('0','False') THEN 1 ELSE 0 END) AS TurnedOff
FROM contacts.dbo.AuditDataChanges a
WHERE a.TableName = 'Store'
  AND a.ColumnName = 'StoreIsComping'
GROUP BY YEAR(a.ChangeDate)
ORDER BY ChangeYear;


-- A5. Wider net, in case the column is logged under a different name or
--     the Store audit lives in dev_aloha instead. Also catches
--     CompingFlag / CompingDate if those are what actually got audited.
SELECT TOP 200
    a.TableName, a.ColumnName,
    COUNT(*)          AS Rows,
    MIN(a.ChangeDate) AS Earliest,
    MAX(a.ChangeDate) AS Latest
FROM contacts.dbo.AuditDataChanges a
WHERE a.ColumnName LIKE '%Comp%'
GROUP BY a.TableName, a.ColumnName
ORDER BY Rows DESC;


-- #####################################################################
-- PART B — THE RAW FLIP HISTORY. Run once A3 shows rows.
-- #####################################################################

SELECT
    CAST(a.RecordPK AS varchar(20)) AS StoreID_Raw,
    st.StoreName,
    a.OldValue,
    a.NewValue,
    a.ChangeDate,
    a.UpdatedBy,
    CASE WHEN a.NewValue IN ('1','True') THEN 'started comping'
         ELSE 'stopped comping' END AS Direction
FROM contacts.dbo.AuditDataChanges a
LEFT JOIN contacts.dbo.Store st
       ON CAST(st.StoreID AS varchar(20)) = CAST(a.RecordPK AS varchar(20))
WHERE a.TableName  = 'Store'
  AND a.ColumnName = 'StoreIsComping'
ORDER BY a.ChangeDate, StoreID_Raw;


-- #####################################################################
-- PART C — POINT-IN-TIME RECONSTRUCTION, and the comparison that
--          actually settles whether the derived series is right.
--
-- For each fiscal year start, work out what StoreIsComping WAS on that
-- date by replaying the audit:
--   * latest flip on or before the date  -> use its NewValue
--   * else earliest flip after the date  -> use its OldValue
--   * else no flips at all               -> the flag never changed, so
--                                           the current value held
--
-- Then compare that reconstructed set against the derived comp set per
-- year. Agreement = the derived series is validated for every year the
-- audit covers, and you can tell Matt the whole thing is confirmed
-- rather than just FY2025.
-- #####################################################################

IF OBJECT_ID('tempdb..#skipstore') IS NOT NULL DROP TABLE #skipstore;
IF OBJECT_ID('tempdb..#d')         IS NOT NULL DROP TABLE #d;
IF OBJECT_ID('tempdb..#sw')        IS NOT NULL DROP TABLE #sw;
IF OBJECT_ID('tempdb..#cap')       IS NOT NULL DROP TABLE #cap;
IF OBJECT_ID('tempdb..#paired')    IS NOT NULL DROP TABLE #paired;
IF OBJECT_ID('tempdb..#thresh')    IS NOT NULL DROP TABLE #thresh;
IF OBJECT_ID('tempdb..#fystart')   IS NOT NULL DROP TABLE #fystart;
IF OBJECT_ID('tempdb..#flips')     IS NOT NULL DROP TABLE #flips;
IF OBJECT_ID('tempdb..#asof')      IS NOT NULL DROP TABLE #asof;
GO
-- ^^^ load-bearing GO.

SET NOCOUNT ON;
DECLARE @DayGrace int = 1;
DECLARE @MinWeekShare decimal(5,4) = 0.85;

CREATE TABLE #skipstore (StoreID int PRIMARY KEY);
INSERT INTO #skipstore (StoreID) VALUES (1),(88888),(9998),(9999),(5002),(1200),(1201);

-- Fiscal year start dates.
SELECT FiscalYear, MIN([Date]) AS FY_Start, MAX([Date]) AS FY_End
INTO #fystart
FROM dev_aloha.dbo.CalendarV2
WHERE FiscalYear IS NOT NULL
GROUP BY FiscalYear;

-- Normalised flip history.
SELECT
    TRY_CAST(a.RecordPK AS int) AS StoreID,
    CASE WHEN a.OldValue IN ('1','True') THEN 1 ELSE 0 END AS OldFlag,
    CASE WHEN a.NewValue IN ('1','True') THEN 1 ELSE 0 END AS NewFlag,
    a.ChangeDate
INTO #flips
FROM contacts.dbo.AuditDataChanges a
WHERE a.TableName  = 'Store'
  AND a.ColumnName = 'StoreIsComping'
  AND TRY_CAST(a.RecordPK AS int) IS NOT NULL;

CREATE CLUSTERED INDEX ix_flips ON #flips(StoreID, ChangeDate);

-- Reconstruct the flag as of each fiscal year start.
SELECT
    fy.FiscalYear,
    s.StoreID,
    COALESCE(
        (SELECT TOP 1 f.NewFlag FROM #flips f
          WHERE f.StoreID = s.StoreID AND f.ChangeDate <= fy.FY_Start
          ORDER BY f.ChangeDate DESC),
        (SELECT TOP 1 f.OldFlag FROM #flips f
          WHERE f.StoreID = s.StoreID AND f.ChangeDate > fy.FY_Start
          ORDER BY f.ChangeDate ASC),
        CASE WHEN s.StoreIsComping = 1 THEN 1 ELSE 0 END
    ) AS WasComping,
    CASE WHEN EXISTS (SELECT 1 FROM #flips f WHERE f.StoreID = s.StoreID)
         THEN 'audited' ELSE 'assumed from current value' END AS Basis
INTO #asof
FROM #fystart fy
CROSS JOIN contacts.dbo.Store s
WHERE s.StoreID NOT IN (SELECT StoreID FROM #skipstore)
  AND fy.FiscalYear BETWEEN 2015 AND 2026;

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


-- =====================================================================
-- GRID C1  Store counts side by side, per year. If AuditedFlagStores
--          tracks DerivedStores closely, the derived series is validated
--          for real. Where Basis is mostly "assumed", the audit does not
--          reach that far back and the comparison is meaningless -- read
--          A4 to know which years those are.
-- =====================================================================
SELECT
    f.FiscalYear,
    SUM(CASE WHEN f.WasComping = 1 THEN 1 ELSE 0 END)   AS AuditedFlagStores,
    SUM(CASE WHEN f.Basis = 'audited' THEN 1 ELSE 0 END) AS StoresWithRealAuditHistory,
    (SELECT COUNT(*) FROM #paired p
      JOIN #thresh t ON t.CompYear = p.CompYear
      WHERE p.CompYear = f.FiscalYear
        AND p.PairedWeeks >= t.MinWeeksRequired)         AS DerivedStores
FROM #asof f
GROUP BY f.FiscalYear
ORDER BY f.FiscalYear;


-- =====================================================================
-- GRID C2  FY2025 comp % three ways. If these land on top of each other
--          the number is as solid as it can get.
-- =====================================================================
SELECT 'Derived (paired-week test)' AS Method,
       COUNT(*) AS CompStores,
       CAST(100.0 * (SUM(p.TyNet) - SUM(p.LyNet))
            / NULLIF(SUM(p.LyNet), 0) AS decimal(6,2)) AS CompPct
FROM #paired p
JOIN #thresh t ON t.CompYear = p.CompYear
WHERE p.CompYear = 2025 AND p.PairedWeeks >= t.MinWeeksRequired

UNION ALL

SELECT 'Audit-reconstructed flag', COUNT(*),
       CAST(100.0 * (SUM(p.TyNet) - SUM(p.LyNet))
            / NULLIF(SUM(p.LyNet), 0) AS decimal(6,2))
FROM #paired p
JOIN #asof a ON a.StoreID = p.StoreID AND a.FiscalYear = p.CompYear
WHERE p.CompYear = 2025 AND a.WasComping = 1

UNION ALL

SELECT 'Current flag, still-open only', COUNT(*),
       CAST(100.0 * (SUM(p.TyNet) - SUM(p.LyNet))
            / NULLIF(SUM(p.LyNet), 0) AS decimal(6,2))
FROM #paired p
JOIN contacts.dbo.Store s ON s.StoreID = p.StoreID
WHERE p.CompYear = 2025
  AND s.StoreIsComping = 1
  AND s.StoreCloseDate >= '9999-01-01';


-- =====================================================================
-- GRID C3  Where the two sets disagree, per year, store by store. This
--          is the list to eyeball -- it tells you whether the derived
--          test is too generous or too strict, and in which direction.
-- =====================================================================
SELECT
    COALESCE(a.FiscalYear, p.CompYear) AS FiscalYear,
    COALESCE(a.StoreID, p.StoreID)     AS StoreID,
    st.StoreName,
    a.WasComping                       AS AuditSaysComping,
    a.Basis                            AS AuditBasis,
    CASE WHEN p.StoreID IS NOT NULL AND p.PairedWeeks >= t.MinWeeksRequired
         THEN 1 ELSE 0 END             AS DerivedSaysComping,
    p.PairedWeeks,
    t.MinWeeksRequired
FROM #asof a
FULL OUTER JOIN #paired p
      ON p.StoreID = a.StoreID AND p.CompYear = a.FiscalYear
LEFT JOIN #thresh t ON t.CompYear = COALESCE(a.FiscalYear, p.CompYear)
LEFT JOIN contacts.dbo.Store st ON st.StoreID = COALESCE(a.StoreID, p.StoreID)
WHERE ISNULL(a.WasComping, 0)
      <> CASE WHEN p.StoreID IS NOT NULL AND p.PairedWeeks >= t.MinWeeksRequired
              THEN 1 ELSE 0 END
  AND COALESCE(a.FiscalYear, p.CompYear) BETWEEN 2015 AND 2026
ORDER BY FiscalYear, StoreID;


-- Cleanup (optional)
-- DROP TABLE #skipstore, #d, #sw, #cap, #paired, #thresh, #fystart, #flips, #asof;
