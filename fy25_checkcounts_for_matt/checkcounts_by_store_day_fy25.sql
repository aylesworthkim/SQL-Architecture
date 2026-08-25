-- =====================================================================
-- FY2025 Check Counts by Store & Day  — for Matt Hayward
--
-- Matt's "Finance Dump - Sales" is daypart-level and 500-errors on a
-- full-year pull. He only needs store x DAY (not daypart), so this
-- aggregates tbl_SalesDataByDayPart (the Flash Report's own source) up
-- to one row per store per day for all of FY2025. Far smaller file, and
-- avoids the broken report.
--
-- Includes BOTH metrics so Matt can pinpoint when his historical log
-- switched basis during the 2025 Toast rollout:
--   CheckCount        = traffic / transactions (each check = 1)  <- the "Now Reporting" basis
--   NonCateringChecks = checks excluding catering (ChecksMinusCatering)
--   GuestCount        = per guest-count tag, excludes catering    <- the OLD "Initially Reported" basis
-- Where his old numbers match GuestCount = old metric; where they match
-- CheckCount = new metric. The crossover week per store is the window
-- he needs to amend.
--
-- For Toast-transition stores the check count is Aloha-sourced before the
-- store's ToastLive date and Toast-sourced on/after — already blended in
-- this table, so it's one continuous series across the cutover.
--
-- EXPORT: run, then right-click the grid -> Save Results As -> CSV
-- (or Query > Results To > File). ~35k rows; opens fine in Excel.
-- =====================================================================

SELECT
    RestaurantID,
    RestaurantName,
    DateOfBusiness,
    FiscalYear,
    FiscalPeriod,
    FiscalWeek,
    WeekName,
    SUM(CheckCount)           AS CheckCount,          -- traffic (transactions)
    SUM(ChecksMinusCatering)  AS NonCateringChecks,   -- non-catering checks
    SUM(GuestCount)           AS GuestCount           -- old basis, for crossover spotting
FROM dev_aloha.dbo.tbl_SalesDataByDayPart
WHERE FiscalYear = 2025
GROUP BY RestaurantID, RestaurantName, DateOfBusiness,
         FiscalYear, FiscalPeriod, FiscalWeek, WeekName
ORDER BY RestaurantID, DateOfBusiness;

-- ---------------------------------------------------------------------
-- OPTIONAL: weekly rollup (matches Matt's weekly tracking grain). Same
-- data summed to store x fiscal week — even smaller, drop-in for his
-- weekly log.
-- ---------------------------------------------------------------------
-- SELECT
--     RestaurantID, RestaurantName, FiscalYear, FiscalPeriod, FiscalWeek, WeekName,
--     SUM(CheckCount)          AS CheckCount,
--     SUM(ChecksMinusCatering) AS NonCateringChecks,
--     SUM(GuestCount)          AS GuestCount
-- FROM dev_aloha.dbo.tbl_SalesDataByDayPart
-- WHERE FiscalYear = 2025
-- GROUP BY RestaurantID, RestaurantName, FiscalYear, FiscalPeriod, FiscalWeek, WeekName
-- ORDER BY RestaurantID, FiscalWeek;

-- ---------------------------------------------------------------------
-- OPTIONAL: just the 5 transition stores, if Matt only wants those.
--   AND RestaurantID IN (1003,1008,1014,1042,1197)
-- ---------------------------------------------------------------------
