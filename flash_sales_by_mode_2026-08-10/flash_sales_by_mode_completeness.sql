/* ============================================================================
   flash_sales_by_mode_completeness.sql   (2026-08-10)  -- READ-ONLY spot check

   REQUEST: "Another data export of sales by mode feeding the Flash Report --
   I think we may be missing some days sales for the individual modes, and
   I'd like to spot check them."

   RANGE: 2026-01-01 through 2026-08-09 (YTD, last complete business day).

   Source: dev_aloha.dbo.tbl_SalesDataByDayPart -- the same rollup the Daily
   Sales Flash Report reads. Mode buckets below are IDENTICAL to the Flash
   bucketing captured in flash_comp_mode_mapping_2026-07-22\01_discovery.sql.

   SAFE: 100% read-only. No writes, no ALTERs.

   HOW TO HAND OFF:
     - Q1 IS the export: Results-to-Grid, then right-click grid ->
       "Save Results As..." -> CSV.
     - Q2 does the finding for you: returns only (day, mode) combos that
       collapsed vs their own trailing norm = the "missing day for a mode"
       fingerprint.
     - Q3 is the per-store drill-in once Q1/Q2 flag a suspect day.
   ============================================================================ */
USE dev_aloha;
GO

/* ---------------------------------------------------------------------------
   Q1 -- Company-wide NET SALES BY MODE, one row per day (THE EXPORT)
   Eyeball any mode column reading 0.00 on a day it's normally non-trivial.
--------------------------------------------------------------------------- */
DECLARE @AsOf  date = '2026-08-09';
DECLARE @Start date = '2026-01-01';

SELECT
    DateOfBusiness,
    DOW         = LEFT(DATENAME(WEEKDAY, DateOfBusiness),3),
    DineIn      = SUM(DineInNetSales + OLODineInNetSales),
    CallIn      = SUM(CallInNetSales + OLOCallInNetSales),
    ToGo        = SUM(ToGoNetSales + FoodsbyNet + DriveThruNetSales + OLODriveThruNetSales),
    CurbSide    = SUM(CurbSideNetSales + CurbSideOLONetSales),
    Delivery    = SUM(DispatchOLONetSales + DeliveryNetSales + NwkDeliveryNetSales + RailsOLONetSales
                    + BiteSquadNetSales + DoorDashNetSales + PostmatesNetSales + GoogleNetSales
                    + DeliverClubNetSales + UberEatsNetSales + WaitrNet + FavorNet
                    + NwkDelivNetDisp + DoorDashNetDisp + PostmatesNetDisp + LyftNetDisp
                    + DeliverLogicNetDisp + GrubHubRailsNet + DispatchSkipCart + DispatchRailsAI),
    OLO         = SUM(OLONetSales),
    GNG         = SUM(GNGNetSales),
    Catering    = SUM(CateringNetSales),
    NetTotal    = SUM(NetSales),
    StoresRptg  = COUNT(DISTINCT RestaurantID)
FROM dev_aloha.dbo.tbl_SalesDataByDayPart
WHERE DateOfBusiness BETWEEN @Start AND @AsOf
  AND RestaurantID IN (SELECT storeid FROM dev_aloha.dbo.get_StoresIncluded(9,'4',@AsOf))
GROUP BY DateOfBusiness
ORDER BY DateOfBusiness;
GO

/* ---------------------------------------------------------------------------
   Q2 -- GAP DETECTOR: flags (day, mode) that fell to ~0 vs its own norm.
   Unpivots to (Day, Mode, Net), compares each day to that mode's trailing
   28-day average, returns only the suspicious drops. Thresholds are tunable.
--------------------------------------------------------------------------- */
DECLARE @AsOf2  date = '2026-08-09';
DECLARE @Start2 date = '2026-01-01';

;WITH daily AS (
    SELECT DateOfBusiness,
        DineIn   = SUM(DineInNetSales + OLODineInNetSales),
        CallIn   = SUM(CallInNetSales + OLOCallInNetSales),
        ToGo     = SUM(ToGoNetSales + FoodsbyNet + DriveThruNetSales + OLODriveThruNetSales),
        CurbSide = SUM(CurbSideNetSales + CurbSideOLONetSales),
        Delivery = SUM(DispatchOLONetSales + DeliveryNetSales + NwkDeliveryNetSales + RailsOLONetSales
                    + BiteSquadNetSales + DoorDashNetSales + PostmatesNetSales + GoogleNetSales
                    + DeliverClubNetSales + UberEatsNetSales + WaitrNet + FavorNet
                    + NwkDelivNetDisp + DoorDashNetDisp + PostmatesNetDisp + LyftNetDisp
                    + DeliverLogicNetDisp + GrubHubRailsNet + DispatchSkipCart + DispatchRailsAI),
        OLO      = SUM(OLONetSales),
        Catering = SUM(CateringNetSales)
    FROM dev_aloha.dbo.tbl_SalesDataByDayPart
    WHERE DateOfBusiness BETWEEN @Start2 AND @AsOf2
      AND RestaurantID IN (SELECT storeid FROM dev_aloha.dbo.get_StoresIncluded(9,'4',@AsOf2))
    GROUP BY DateOfBusiness
),
unpiv AS (
    SELECT DateOfBusiness, Mode, Net
    FROM daily
    CROSS APPLY (VALUES
        ('DineIn',DineIn),('CallIn',CallIn),('ToGo',ToGo),('CurbSide',CurbSide),
        ('Delivery',Delivery),('OLO',OLO),('Catering',Catering)
    ) v(Mode,Net)
),
norm AS (
    SELECT *,
        TrailingAvg = AVG(Net) OVER (PARTITION BY Mode
                        ORDER BY DateOfBusiness ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING)
    FROM unpiv
)
SELECT DateOfBusiness,
       DOW = LEFT(DATENAME(WEEKDAY,DateOfBusiness),3),
       Mode, Net, TrailingAvg,
       PctOfNorm = CASE WHEN TrailingAvg > 0 THEN 100.0*Net/TrailingAvg END
FROM norm
WHERE TrailingAvg > 500                 -- mode is normally material
  AND Net < 0.40 * TrailingAvg          -- but this day is <40% of its own norm
ORDER BY DateOfBusiness DESC, Mode;
GO

/* ---------------------------------------------------------------------------
   Q3 -- Per-store drill-in once Q1/Q2 point to a suspect day.
   Which stores are missing a given mode on a given day? Set @Day.
   If a store shows NetTotal ~0 for ALL modes -> upstream pull gap (hstCheck),
   not a mode-mapping issue.
--------------------------------------------------------------------------- */
DECLARE @Day date = '2026-08-07';   -- <-- set to a suspect day from Q1/Q2
SELECT RestaurantID, RestaurantName,
    DineIn   = SUM(DineInNetSales + OLODineInNetSales),
    CallIn   = SUM(CallInNetSales + OLOCallInNetSales),
    ToGo     = SUM(ToGoNetSales + FoodsbyNet + DriveThruNetSales + OLODriveThruNetSales),
    CurbSide = SUM(CurbSideNetSales + CurbSideOLONetSales),
    Delivery = SUM(DispatchOLONetSales + DeliveryNetSales + DoorDashNetSales + UberEatsNetSales),
    OLO      = SUM(OLONetSales),
    Catering = SUM(CateringNetSales),
    NetTotal = SUM(NetSales)
FROM dev_aloha.dbo.tbl_SalesDataByDayPart
WHERE DateOfBusiness = @Day
  AND RestaurantID IN (SELECT storeid FROM dev_aloha.dbo.get_StoresIncluded(9,'4',@Day))
GROUP BY RestaurantID, RestaurantName
ORDER BY NetTotal;
GO
