-- =====================================================================
-- WHY WE DO NOT USE FN_GetCompingDate  —  two independent defects
--
-- This is a side finding from Matt's comp % request, but it affects
-- anything that relies on the official comping date, including the SSRS
-- report /Accounting/Restaurant Open Date and Comping Date and the
-- "Non Comping Stores" reports. Worth raising separately from Matt's ask.
--
-- The function (dev_aloha.dbo.FN_GetCompingDate, Don Wilson, 2017) says:
--     "Calculates the first day of the 19th full period that the given
--      store is open."
--
-- ---------------------------------------------------------------------
-- DEFECT 1 — it returns the 6th period, not the 19th. Dead variable.
-- ---------------------------------------------------------------------
--   set @fperiod = @fperiod + 5                       -- 6th period
--   ...
--   set @compdate             = <start of @FYear / @Fperiod>
--   set @NineteenthPeriodStart = <start of @FYear+1 / @Fperiod>   -- +13 more
--                                                     -- = 19th period
--   return @compdate            <== returns the 6-period value
--
-- @NineteenthPeriodStart is computed and then thrown away. Its name and
-- the documented summary both say 19 periods (~18 months, the usual
-- restaurant comp maturity); the returned value is 6 periods (~6 months).
-- One of the two is wrong, and the dead variable strongly suggests an
-- edit that was never finished. Ask Matt/Finance which is intended
-- before anyone "fixes" it -- the answer changes the comp store list.
--
-- ---------------------------------------------------------------------
-- DEFECT 2 — the 13-period wrap math is now wrong, because CalendarV2
--            was retro-fitted to 12 periods.
-- ---------------------------------------------------------------------
-- The function hardcodes the old calendar:
--   set @FYear   = case when @Fperiod > 13 then @Fyear + 1 else @Fyear end
--   set @fperiod = case when @Fperiod > 13 then @Fperiod - 13 else @fperiod end
--
-- But the probe showed CalendarV2 now reports PeriodsInYear = 12 for
-- EVERY year 2004-2035. So with FiscalPeriod only ever running 1-12:
--
--   opens in period 8      -> 8 + 5 = 13, which is NOT > 13, so no wrap.
--                             It then looks up FiscalPeriod = 13, which no
--                             longer exists -> the subquery returns no row
--                             -> THE FUNCTION RETURNS NULL.
--   opens in periods 9-12   -> wraps by 13 instead of 12, landing one
--                             period EARLY (year+1 P1-P4 instead of P2-P5).
--   opens in periods 1-7    -> still fine.
--
-- So roughly a third of stores get a wrong or NULL comping date, and it
-- depends on which period they opened in. Grid 2 below proves it per
-- store; grid 3 counts the damage.
--
-- Nothing here changes anything -- all SELECT. No ALTER, no UPDATE.
-- =====================================================================

SET NOCOUNT ON;


-- ---------------------------------------------------------------------
-- A period spine with a sequence number. This is the calendar-agnostic
-- way to say "N periods after the store opened" -- it works whether the
-- year has 12 periods or 13, which is exactly what the function fails to
-- do.
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#per') IS NOT NULL DROP TABLE #per;

SELECT
    FiscalYear,
    FiscalPeriod,
    MIN(PeriodStart) AS PeriodStart,
    ROW_NUMBER() OVER (ORDER BY MIN(PeriodStart)) AS PerSeq
INTO #per
FROM dev_aloha.dbo.CalendarV2
WHERE FiscalYear   IS NOT NULL
  AND FiscalPeriod IS NOT NULL
GROUP BY FiscalYear, FiscalPeriod;

CREATE UNIQUE CLUSTERED INDEX ix_per ON #per(FiscalYear, FiscalPeriod);


-- =====================================================================
-- GRID 1  Sanity: how many periods does each fiscal year actually have
--         in CalendarV2 now? Confirms the 12-period retro-fit and shows
--         that FiscalPeriod 13 no longer exists anywhere.
-- =====================================================================
SELECT
    FiscalYear,
    COUNT(*)               AS PeriodsInYear,
    MIN(FiscalPeriod)      AS MinPeriod,
    MAX(FiscalPeriod)      AS MaxPeriod
FROM #per
GROUP BY FiscalYear
ORDER BY FiscalYear;


-- =====================================================================
-- GRID 2  Per-store proof. Compare what the function returns against
--         correctly-sequenced period arithmetic.
--
--   FnResult              = what FN_GetCompingDate returns today
--   Correct_6Period       = start of the 6th period after open, done right
--   Correct_19Period      = start of the 19th period after open, done right
--                           (the documented intent)
--   Verdict               = where the function disagrees with itself
--
--   Look for: Verdict = 'BUG: returns NULL' (opened in period 8) and
--   'BUG: off by one period' (opened in periods 9-12).
-- =====================================================================
SELECT
    s.StoreID,
    s.StoreName,
    s.StoreOpenDate,
    c.FiscalYear                             AS OpenFiscalYear,
    c.FiscalPeriod                           AS OpenFiscalPeriod,
    dev_aloha.dbo.FN_GetCompingDate(s.StoreID) AS FnResult,
    p6.PeriodStart                           AS Correct_6Period,
    p19.PeriodStart                          AS Correct_19Period,
    CASE
        WHEN c.FiscalPeriod IS NULL
            THEN 'n/a - open date not in CalendarV2 (sentinel or pre-2004)'
        WHEN dev_aloha.dbo.FN_GetCompingDate(s.StoreID) IS NULL
            THEN 'BUG: returns NULL (period ' + CAST(c.FiscalPeriod AS varchar(2))
                 + ' + 5 = 13, which no longer exists)'
        WHEN dev_aloha.dbo.FN_GetCompingDate(s.StoreID) <> p6.PeriodStart
            THEN 'BUG: off by one period (13-period wrap on a 12-period calendar)'
        WHEN dev_aloha.dbo.FN_GetCompingDate(s.StoreID) = p6.PeriodStart
            THEN 'Matches 6-period math - but docs say 19 periods'
        ELSE 'unexpected'
    END                                      AS Verdict
FROM contacts.dbo.Store s
LEFT JOIN dev_aloha.dbo.CalendarV2 c
       ON c.[Date] = s.StoreOpenDate
LEFT JOIN #per po
       ON po.FiscalYear = c.FiscalYear AND po.FiscalPeriod = c.FiscalPeriod
LEFT JOIN #per p6
       ON p6.PerSeq = po.PerSeq + 5
LEFT JOIN #per p19
       ON p19.PerSeq = po.PerSeq + 18
WHERE s.StoreID NOT IN (1, 88888, 9998, 9999, 5002, 1200, 1201)
ORDER BY c.FiscalPeriod, s.StoreID;


-- =====================================================================
-- GRID 3  The damage, counted. How many stores land in each verdict,
--         broken out by the period they opened in. This is the summary
--         to put in front of whoever owns the function.
-- =====================================================================
SELECT
    c.FiscalPeriod AS OpenFiscalPeriod,
    COUNT(*)       AS Stores,
    SUM(CASE WHEN dev_aloha.dbo.FN_GetCompingDate(s.StoreID) IS NULL
             THEN 1 ELSE 0 END) AS Returns_NULL,
    SUM(CASE WHEN dev_aloha.dbo.FN_GetCompingDate(s.StoreID) IS NOT NULL
              AND dev_aloha.dbo.FN_GetCompingDate(s.StoreID) <> p6.PeriodStart
             THEN 1 ELSE 0 END) AS Wrong_Period,
    SUM(CASE WHEN dev_aloha.dbo.FN_GetCompingDate(s.StoreID) = p6.PeriodStart
             THEN 1 ELSE 0 END) AS Agrees_With_6Period
FROM contacts.dbo.Store s
LEFT JOIN dev_aloha.dbo.CalendarV2 c
       ON c.[Date] = s.StoreOpenDate
LEFT JOIN #per po
       ON po.FiscalYear = c.FiscalYear AND po.FiscalPeriod = c.FiscalPeriod
LEFT JOIN #per p6
       ON p6.PerSeq = po.PerSeq + 5
WHERE s.StoreID NOT IN (1, 88888, 9998, 9999, 5002, 1200, 1201)
  AND c.FiscalPeriod IS NOT NULL
GROUP BY c.FiscalPeriod
ORDER BY c.FiscalPeriod;


-- =====================================================================
-- GRID 4  So what? How much would the comp definition actually move.
--         Counts stores that would be considered "comping as of today"
--         under each rule. The gap between the 6-period and 19-period
--         columns is the size of the open question for Finance.
-- =====================================================================
SELECT
    SUM(CASE WHEN dev_aloha.dbo.FN_GetCompingDate(s.StoreID) <= CAST(GETDATE() AS date)
             THEN 1 ELSE 0 END)                              AS Comping_PerFunctionToday,
    SUM(CASE WHEN p6.PeriodStart  <= CAST(GETDATE() AS date) THEN 1 ELSE 0 END) AS Comping_6PeriodRule,
    SUM(CASE WHEN p19.PeriodStart <= CAST(GETDATE() AS date) THEN 1 ELSE 0 END) AS Comping_19PeriodRule,
    SUM(CASE WHEN s.StoreIsComping = 1 THEN 1 ELSE 0 END)    AS Flagged_IsComping_Bit,
    COUNT(*)                                                 AS StoresConsidered
FROM contacts.dbo.Store s
LEFT JOIN dev_aloha.dbo.CalendarV2 c
       ON c.[Date] = s.StoreOpenDate
LEFT JOIN #per po
       ON po.FiscalYear = c.FiscalYear AND po.FiscalPeriod = c.FiscalPeriod
LEFT JOIN #per p6  ON p6.PerSeq  = po.PerSeq + 5
LEFT JOIN #per p19 ON p19.PerSeq = po.PerSeq + 18
WHERE s.StoreID NOT IN (1, 88888, 9998, 9999, 5002, 1200, 1201)
  AND s.StoreOpenDate < '9999-01-01'
  AND s.StoreCloseDate >= '9999-01-01';   -- currently open only


-- =====================================================================
-- GRID 5  Separately: the StoreIsComping bit is stale, which is its own
--         reason not to use it for history. These stores are flagged as
--         comping but have a real close date in the past.
--         Known examples from the probe: 1095 Lafayette LA (closed
--         2025-10-24), 1116, 1143, 1150, 1165 -- all still flagged 1.
-- =====================================================================
SELECT
    s.StoreID,
    s.StoreName,
    s.StoreOpenDate,
    s.StoreCloseDate,
    s.StoreIsComping,
    s.StoreStatus
FROM contacts.dbo.Store s
WHERE s.StoreIsComping = 1
  AND s.StoreCloseDate < CAST(GETDATE() AS date)
ORDER BY s.StoreCloseDate DESC;


-- Cleanup (optional)
-- DROP TABLE #per;
