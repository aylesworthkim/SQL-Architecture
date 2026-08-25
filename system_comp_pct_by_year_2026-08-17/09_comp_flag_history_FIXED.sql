-- =====================================================================
-- COMP FLAG HISTORY, PARSE FIXED — real ground truth per fiscal year
-- 2026-08-17. Replaces script 08 Part C, which was broken.
--
-- ---------------------------------------------------------------------
-- WHAT WAS WRONG WITH SCRIPT 08 PART C
-- ---------------------------------------------------------------------
-- It reported StoresWithRealAuditHistory = 0 for every year, even though
-- the audit holds 254 StoreIsComping flips across 113 stores going back
-- to 2017-02-16.
--
-- Cause: AuditDataChanges.RecordPK is NOT the bare StoreID. The trigger
-- builds it as a string --
--     QUOTENAME(@RecordPKName + ' = ' + @RecordPk, '''')
-- so the stored value is literally 'StoreId = 1139'. Script 08 used
-- TRY_CAST(RecordPK AS int), which returned NULL on every single row, so
-- the flip table came out empty and every year silently fell back to
-- "assumed from current value". That made script 08's "audit-
-- reconstructed" number just the current flag in disguise -- it agreed
-- with the derived figure because it was not an independent check at all.
--
-- The casing also drifts across the history ('StoreID = ' in 2017-2019
-- rows, 'StoreId = ' from late 2019 on), so parse on the '=' rather than
-- matching a prefix.
--
-- ---------------------------------------------------------------------
-- TWO MORE THINGS SCRIPT 08 GOT WRONG
-- ---------------------------------------------------------------------
-- * Blank OldValue/NewValue. The trigger resets @OldValue/@NewValue to ''
--   between columns, so INSERT events log OldValue='' and DELETE events
--   log NewValue=''. Script 08 mapped blank to 0 via "IN ('1','True')
--   ELSE 0", conflating "no information" with "explicitly not comping".
--   Rows with a blank NewValue carry nothing and must be dropped.
-- * Junk PKs. The audit contains StoreId = 1, 197, 198, 9999 -- the dev
--   centre, test kitchens, and two IDs that were never restaurants.
--
-- ---------------------------------------------------------------------
-- WHAT THE HISTORY SHOWS — the set is re-cut by hand every January
-- ---------------------------------------------------------------------
--   2018-12-31  Don Wilson       13 stores turned ON within 3 minutes
--   2022-01-03  Marisa Kunkle    ~30 stores flipped
--   2023-01-03  Matthew Hayward  9 stores turned ON
--   2024-01-08  Don + Matt       several flipped
--   2026-01-05  Don Wilson       1190, 1194 turned ON
-- So comp membership is a deliberate annual decision, which is exactly
-- why today's flag cannot be applied backwards -- and why this audit is
-- worth mining.
--
-- NOTE: Matt himself made several of these flips (2023-01-03, 2024-01-08,
-- 2025-01-06). He has been maintaining this flag, so he may simply have
-- the per-year lists -- worth asking before doing more reconstruction.
--
-- ---------------------------------------------------------------------
-- COVERAGE LIMIT — be honest about this
-- ---------------------------------------------------------------------
-- The audit starts 2017-02-16 and records only CHANGES. For a store whose
-- flag never moved after that date we can extrapolate backwards from its
-- first recorded flip's OldValue, which is genuinely informative. But any
-- flip BEFORE Feb 2017 is invisible, so FY2015-FY2016 cannot be validated
-- at all and FY2017 only partially. Grid 3 reports, per year, how many
-- stores rest on real audit evidence versus a fallback assumption -- read
-- it before trusting any year's comparison.
-- =====================================================================

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

DECLARE @DayGrace     int = 1;
DECLARE @MinWeekShare decimal(5,4) = 0.85;
DECLARE @AuditStart   date = '2017-02-16';   -- earliest flip on record

CREATE TABLE #skipstore (StoreID int PRIMARY KEY);
INSERT INTO #skipstore (StoreID) VALUES (1),(88888),(9998),(9999),(5002),(1200),(1201),(197),(198);


-- ---------------------------------------------------------------------
-- Parse the flip history properly.
--   RecordPK  'StoreId = 1139'  ->  1139   (split on '=', casing-safe)
--   NewValue  blank/NULL        ->  dropped, carries no information
-- ---------------------------------------------------------------------
SELECT
    TRY_CAST(LTRIM(RTRIM(SUBSTRING(a.RecordPK,
                                  CHARINDEX('=', a.RecordPK) + 1,
                                  50))) AS int) AS StoreID,
    CASE WHEN LTRIM(RTRIM(ISNULL(a.OldValue,''))) = '1' THEN 1
         WHEN LTRIM(RTRIM(ISNULL(a.OldValue,''))) = '0' THEN 0
         ELSE NULL END                          AS OldFlag,
    CASE WHEN LTRIM(RTRIM(a.NewValue)) = '1' THEN 1 ELSE 0 END AS NewFlag,
    a.ChangeDate,
    a.UpdatedBy
INTO #flips
FROM contacts.dbo.AuditDataChanges a
WHERE a.TableName  = 'Store'
  AND a.ColumnName = 'StoreIsComping'
  AND CHARINDEX('=', a.RecordPK) > 0
  AND LTRIM(RTRIM(ISNULL(a.NewValue,''))) IN ('0','1')   -- drop blanks
  AND TRY_CAST(LTRIM(RTRIM(SUBSTRING(a.RecordPK,
                                     CHARINDEX('=', a.RecordPK) + 1,
                                     50))) AS int) IS NOT NULL;

DELETE FROM #flips WHERE StoreID IN (SELECT StoreID FROM #skipstore);

CREATE CLUSTERED INDEX ix_flips ON #flips(StoreID, ChangeDate);


-- =====================================================================
-- GRID 1  PARSE CHECK. Confirms the fix. ParsedOK should equal RawRows,
--         and DistinctStores should be in the region of 100.
--         If ParsedOK is 0 the parse is still wrong -- stop here.
-- =====================================================================
SELECT
    (SELECT COUNT(*) FROM contacts.dbo.AuditDataChanges
      WHERE TableName = 'Store' AND ColumnName = 'StoreIsComping') AS RawRows,
    (SELECT COUNT(*) FROM #flips)                                  AS ParsedOK,
    (SELECT COUNT(DISTINCT StoreID) FROM #flips)                   AS DistinctStores,
    (SELECT MIN(ChangeDate) FROM #flips)                           AS Earliest,
    (SELECT MAX(ChangeDate) FROM #flips)                           AS Latest;


-- =====================================================================
-- GRID 2  THE ANNUAL RE-CUT. Any day where 5+ stores were flipped at
--         once -- the deliberate start-of-year comp list decisions.
--         This is the documentary evidence that comp membership is set
--         per year, and by whom.
-- =====================================================================
SELECT
    CAST(f.ChangeDate AS date) AS FlipDate,
    f.UpdatedBy,
    COUNT(*)                                              AS StoresFlipped,
    SUM(CASE WHEN f.NewFlag = 1 THEN 1 ELSE 0 END)         AS TurnedOn,
    SUM(CASE WHEN f.NewFlag = 0 THEN 1 ELSE 0 END)         AS TurnedOff
FROM #flips f
GROUP BY CAST(f.ChangeDate AS date), f.UpdatedBy
HAVING COUNT(*) >= 5
ORDER BY FlipDate;


-- ---------------------------------------------------------------------
-- Reconstruct the flag as of each fiscal year start, and record WHY we
-- believe each value so the confidence is visible rather than implied.
-- ---------------------------------------------------------------------
SELECT FiscalYear, MIN([Date]) AS FY_Start
INTO #fystart
FROM dev_aloha.dbo.CalendarV2
WHERE FiscalYear IS NOT NULL
GROUP BY FiscalYear;

SELECT
    fy.FiscalYear,
    s.StoreID,
    COALESCE(
        -- 1. most recent flip at or before the year start: authoritative
        (SELECT TOP 1 f.NewFlag FROM #flips f
          WHERE f.StoreID = s.StoreID AND f.ChangeDate < DATEADD(day,1,fy.FY_Start)
          ORDER BY f.ChangeDate DESC),
        -- 2. else the OldValue of the earliest later flip: also evidence
        (SELECT TOP 1 f.OldFlag FROM #flips f
          WHERE f.StoreID = s.StoreID AND f.ChangeDate >= DATEADD(day,1,fy.FY_Start)
            AND f.OldFlag IS NOT NULL
          ORDER BY f.ChangeDate ASC),
        -- 3. else fall back to today's value: an ASSUMPTION
        CASE WHEN s.StoreIsComping = 1 THEN 1 ELSE 0 END
    ) AS WasComping,
    CASE
        WHEN EXISTS (SELECT 1 FROM #flips f
                      WHERE f.StoreID = s.StoreID
                        AND f.ChangeDate < DATEADD(day,1,fy.FY_Start))
            THEN 'audited (flip on/before year start)'
        WHEN EXISTS (SELECT 1 FROM #flips f
                      WHERE f.StoreID = s.StoreID
                        AND f.ChangeDate >= DATEADD(day,1,fy.FY_Start)
                        AND f.OldFlag IS NOT NULL)
            THEN 'audited (back-extrapolated from later flip)'
        ELSE 'ASSUMED from current value'
    END AS Basis
INTO #asof
FROM #fystart fy
CROSS JOIN contacts.dbo.Store s
WHERE s.StoreID NOT IN (SELECT StoreID FROM #skipstore)
  AND fy.FiscalYear BETWEEN 2015 AND 2026;


-- Rebuild the derived comp set (script 06 logic).
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
-- GRID 3  <<== READ THIS BEFORE ANY COMPARISON. How much of each year
--              rests on real audit evidence.
--
--   AuditPct near 0 (expect FY2015-2016, and much of FY2017) means the
--   audit simply cannot speak to that year and its comparison below is
--   meaningless. The audit's first flip is 2017-02-16.
-- =====================================================================
SELECT
    a.FiscalYear,
    COUNT(*)                                                          AS StoresConsidered,
    SUM(CASE WHEN a.Basis LIKE 'audited%' THEN 1 ELSE 0 END)          AS OnAuditEvidence,
    SUM(CASE WHEN a.Basis = 'ASSUMED from current value' THEN 1 ELSE 0 END) AS Assumed,
    CAST(100.0 * SUM(CASE WHEN a.Basis LIKE 'audited%' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*),0) AS decimal(5,1))                        AS AuditPct
FROM #asof a
GROUP BY a.FiscalYear
ORDER BY a.FiscalYear;


-- =====================================================================
-- GRID 4  THE REAL VALIDATION. Comp % from the derived test versus from
--         the audit-reconstructed flag, per year.
--
--   Only trust rows where grid 3's AuditPct is high. Where the two
--   CompPct columns agree, that year is genuinely confirmed by an
--   independent source rather than resting on my method alone.
--
--   Both columns use the SAME paired-week dollars -- the only difference
--   is which stores are counted, which is exactly the question.
-- =====================================================================
SELECT
    p.CompYear AS FiscalYear,

    COUNT(*)                                             AS DerivedStores,
    CAST(100.0 * (SUM(CASE WHEN p.PairedWeeks >= t.MinWeeksRequired THEN p.TyNet ELSE 0 END)
                - SUM(CASE WHEN p.PairedWeeks >= t.MinWeeksRequired THEN p.LyNet ELSE 0 END))
         / NULLIF(SUM(CASE WHEN p.PairedWeeks >= t.MinWeeksRequired THEN p.LyNet ELSE 0 END), 0)
         AS decimal(6,2))                                AS CompPct_Derived,

    SUM(CASE WHEN a.WasComping = 1 THEN 1 ELSE 0 END)     AS AuditFlagStores,
    CAST(100.0 * (SUM(CASE WHEN a.WasComping = 1 THEN p.TyNet ELSE 0 END)
                - SUM(CASE WHEN a.WasComping = 1 THEN p.LyNet ELSE 0 END))
         / NULLIF(SUM(CASE WHEN a.WasComping = 1 THEN p.LyNet ELSE 0 END), 0)
         AS decimal(6,2))                                AS CompPct_AuditFlag
FROM #paired p
JOIN #thresh t ON t.CompYear = p.CompYear
LEFT JOIN #asof a ON a.StoreID = p.StoreID AND a.FiscalYear = p.CompYear
GROUP BY p.CompYear
ORDER BY p.CompYear;


-- =====================================================================
-- GRID 5  Disagreements, restricted to years the audit can actually
--         speak to (FY2018+). This is the short list worth eyeballing --
--         each row is a store where the recorded business decision and
--         the sales-presence test part ways.
-- =====================================================================
SELECT
    a.FiscalYear,
    a.StoreID,
    st.StoreName,
    a.WasComping        AS AuditSaysComping,
    a.Basis             AS AuditBasis,
    CASE WHEN p.PairedWeeks >= t.MinWeeksRequired THEN 1 ELSE 0 END AS DerivedSaysComping,
    ISNULL(p.PairedWeeks, 0) AS PairedWeeks,
    t.MinWeeksRequired,
    CASE WHEN st.StoreCloseDate >= '9999-01-01' THEN NULL
         ELSE st.StoreCloseDate END AS StoreCloseDate
FROM #asof a
LEFT JOIN #paired p ON p.StoreID = a.StoreID AND p.CompYear = a.FiscalYear
LEFT JOIN #thresh t ON t.CompYear = a.FiscalYear
LEFT JOIN contacts.dbo.Store st ON st.StoreID = a.StoreID
WHERE a.FiscalYear >= 2018
  AND a.Basis LIKE 'audited%'                 -- evidence-backed only
  AND a.WasComping <> CASE WHEN p.PairedWeeks >= t.MinWeeksRequired
                           THEN 1 ELSE 0 END
  AND (p.PairedWeeks > 0 OR a.WasComping = 1) -- suppress never-traded noise
ORDER BY a.FiscalYear, a.StoreID;


-- =====================================================================
-- GRID 6  The audit-reconstructed comp store list per year, for the
--         years it covers. If grid 4 agrees, THIS is the list to hand
--         Matt -- it is the recorded business decision, not an inference.
-- =====================================================================
SELECT
    a.FiscalYear,
    a.StoreID,
    st.StoreName,
    a.Basis,
    ISNULL(p.PairedWeeks, 0)       AS PairedWeeks,
    CAST(p.LyNet AS decimal(18,2)) AS PriorYearNet,
    CAST(p.TyNet AS decimal(18,2)) AS ThisYearNet
FROM #asof a
LEFT JOIN #paired p ON p.StoreID = a.StoreID AND p.CompYear = a.FiscalYear
LEFT JOIN contacts.dbo.Store st ON st.StoreID = a.StoreID
WHERE a.WasComping = 1
  AND a.FiscalYear >= 2018
ORDER BY a.FiscalYear, a.StoreID;


-- Cleanup (optional)
-- DROP TABLE #skipstore, #d, #sw, #cap, #paired, #thresh, #fystart, #flips, #asof;
