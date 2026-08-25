/* ============================================================================
   01_discovery.sql
   Flash Report Comp% mode-mapping investigation  (2026-07-22)

   PROBLEM (Scenario A, confirmed):
     Current-year (Toast) net sales are correct and tie to Toast. Total R-Net
     comp is flat/up. But the PER-MODE Comp% column (DineInNet, CallInNet,
     ToGoNet, OLO, DeliveryNet, Catering, CurbSide...) shows large phantom
     swings YoY. Suspected cause: current-year (Toast) rows and prior-year
     (Aloha) rows in dev_aloha.dbo.tbl_SalesDataByDayPart classify the SAME
     business channel into DIFFERENT mode columns, so revenue appears to move
     between modes across the Aloha->Toast seam even though the total is stable.

   GOAL of this pack: capture live ground truth so we can pinpoint exactly
     which mode columns diverge between the two eras, then write the fix.

   SAFE: 100% read-only. No writes, no ALTERs. Run in SSMS.

   HOW TO RUN / RETURN RESULTS:
     - Run each numbered section and send back the grid (or CSV).
     - For Section 2 (proc text) switch to Results-to-Text (Ctrl+T) so nothing
       gets truncated, OR just right-click each proc in Object Explorer ->
       "Script Stored Procedure as > CREATE To > New Window" and send those.
   ============================================================================ */

USE dev_aloha;
GO

/* ---------------------------------------------------------------------------
   SECTION 1 — Toast dining-option -> OrderMode -> Flash bucket mapping
   This table IS the current-year (Toast) bucketing rule.
   (Lives in the toast DB.)
--------------------------------------------------------------------------- */
PRINT '===== SECTION 1: cfg_map_DiningOptionToOrderMode (Toast side) =====';
SELECT *
FROM toast.dbo.cfg_map_DiningOptionToOrderMode
ORDER BY FlashSort, OrderModeID, DiningOptionName;   -- adjust col names if they differ
GO

/* ---------------------------------------------------------------------------
   SECTION 2 — Full text of the three procs that build / read the rollup
   (a) sp_toast_SalesDataByDayPart  -> populates CURRENT-YEAR (Toast) columns
   (b) sp_SalesDataByDayPart        -> populated PRIOR-YEAR (Aloha) columns
   (c) sp_rpt_Daily_Sales_FLash_Report_Summary -> reads table, computes Comp%
   Send all three back in full.
--------------------------------------------------------------------------- */
PRINT '===== SECTION 2a: sp_toast_SalesDataByDayPart =====';
EXEC sp_helptext 'dbo.sp_toast_SalesDataByDayPart';
GO
PRINT '===== SECTION 2b: sp_SalesDataByDayPart (Aloha rollup) =====';
EXEC sp_helptext 'dbo.sp_SalesDataByDayPart';
GO
PRINT '===== SECTION 2c: sp_rpt_Daily_Sales_FLash_Report_Summary =====';
EXEC sp_helptext 'dbo.sp_rpt_Daily_Sales_FLash_Report_Summary';
GO
-- If any name above errors as "not found", list the real names:
PRINT '===== SECTION 2d: procs whose name matches SalesDataByDayPart / Flash =====';
SELECT s.name AS [schema], o.name AS proc_name, o.type_desc, o.modify_date
FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE o.type = 'P'
  AND (o.name LIKE '%SalesDataByDayPart%' OR o.name LIKE '%Flash%')
ORDER BY o.name;
GO

/* ---------------------------------------------------------------------------
   SECTION 3 — Exact column inventory of the rollup table
   Confirms the real mode-column names (so the fix references the right ones).
--------------------------------------------------------------------------- */
PRINT '===== SECTION 3: columns of tbl_SalesDataByDayPart =====';
SELECT c.column_id, c.name AS column_name, t.name AS data_type
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dev_aloha.dbo.tbl_SalesDataByDayPart')
ORDER BY c.column_id;
GO

/* ---------------------------------------------------------------------------
   SECTION 4 — THE DIVERGENCE, at the company level (mirrors the Flash total)
   Sums every Flash mode for the current-year window and the prior-year window,
   over All Reportable Restaurants, so we can see which channels swing YoY.
   Adjust @AsOf to the date leadership is asking about.
--------------------------------------------------------------------------- */
DECLARE @AsOf   date = '2026-07-21';
DECLARE @CyStart date = '2026-01-01';
DECLARE @PyStart date = '2025-01-01';
DECLARE @PyAsOf  date = DATEADD(DAY, -364, @AsOf);  -- Flash PY alignment (same-day-last-year ~ -364)

PRINT '===== SECTION 4: company-wide mode split, CY window vs PY window =====';
;WITH cy AS (
    SELECT
        DineInNet   = SUM(DineInNetSales + OLODineInNetSales),
        CallInNet   = SUM(CallInNetSales + OLOCallInNetSales),
        ToGoNet     = SUM(ToGoNetSales + FoodsbyNet + DriveThruNetSales + OLODriveThruNetSales),
        CurbSide    = SUM(CurbSideNetSales + CurbSideOLONetSales),
        DeliveryNet = SUM(DispatchOLONetSales + DeliveryNetSales + NwkDeliveryNetSales + RailsOLONetSales
                        + BiteSquadNetSales + DoorDashNetSales + PostmatesNetSales + GoogleNetSales
                        + DeliverClubNetSales + UberEatsNetSales + WaitrNet + FavorNet
                        + NwkDelivNetDisp + DoorDashNetDisp + PostmatesNetDisp + LyftNetDisp
                        + DeliverLogicNetDisp + GrubHubRailsNet + DispatchSkipCart + DispatchRailsAI),
        OLO         = SUM(OLONetSales),
        GNG         = SUM(GNGNetSales),
        Catering    = SUM(CateringNetSales),
        NetTotal    = SUM(NetSales)
    FROM dev_aloha.dbo.tbl_SalesDataByDayPart
    WHERE DateOfBusiness BETWEEN @CyStart AND @AsOf
      AND RestaurantID IN (SELECT storeid FROM dev_aloha.dbo.get_StoresIncluded(9,'4',@AsOf))
),
py AS (
    SELECT
        DineInNet   = SUM(DineInNetSales + OLODineInNetSales),
        CallInNet   = SUM(CallInNetSales + OLOCallInNetSales),
        ToGoNet     = SUM(ToGoNetSales + FoodsbyNet + DriveThruNetSales + OLODriveThruNetSales),
        CurbSide    = SUM(CurbSideNetSales + CurbSideOLONetSales),
        DeliveryNet = SUM(DispatchOLONetSales + DeliveryNetSales + NwkDeliveryNetSales + RailsOLONetSales
                        + BiteSquadNetSales + DoorDashNetSales + PostmatesNetSales + GoogleNetSales
                        + DeliverClubNetSales + UberEatsNetSales + WaitrNet + FavorNet
                        + NwkDelivNetDisp + DoorDashNetDisp + PostmatesNetDisp + LyftNetDisp
                        + DeliverLogicNetDisp + GrubHubRailsNet + DispatchSkipCart + DispatchRailsAI),
        OLO         = SUM(OLONetSales),
        GNG         = SUM(GNGNetSales),
        Catering    = SUM(CateringNetSales),
        NetTotal    = SUM(NetSales)
    FROM dev_aloha.dbo.tbl_SalesDataByDayPart
    WHERE DateOfBusiness BETWEEN @PyStart AND @PyAsOf
      AND RestaurantID IN (SELECT storeid FROM dev_aloha.dbo.get_StoresIncluded(9,'4',@AsOf))
)
SELECT Mode='DineInNet',   CY=cy.DineInNet,   PY=py.DineInNet,   Var=cy.DineInNet-py.DineInNet     FROM cy,py
UNION ALL SELECT 'CallInNet',   cy.CallInNet,   py.CallInNet,   cy.CallInNet-py.CallInNet     FROM cy,py
UNION ALL SELECT 'ToGoNet',     cy.ToGoNet,     py.ToGoNet,     cy.ToGoNet-py.ToGoNet         FROM cy,py
UNION ALL SELECT 'CurbSide',    cy.CurbSide,    py.CurbSide,    cy.CurbSide-py.CurbSide       FROM cy,py
UNION ALL SELECT 'DeliveryNet', cy.DeliveryNet, py.DeliveryNet, cy.DeliveryNet-py.DeliveryNet FROM cy,py
UNION ALL SELECT 'OLO',         cy.OLO,         py.OLO,         cy.OLO-py.OLO                 FROM cy,py
UNION ALL SELECT 'GNG',         cy.GNG,         py.GNG,         cy.GNG-py.GNG                 FROM cy,py
UNION ALL SELECT 'Catering',    cy.Catering,    py.Catering,    cy.Catering-py.Catering       FROM cy,py
UNION ALL SELECT 'NetTotal',    cy.NetTotal,    py.NetTotal,    cy.NetTotal-py.NetTotal       FROM cy,py;
GO

/* ---------------------------------------------------------------------------
   SECTION 5 — THE SMOKING GUN: single-store daily view across a cutover seam
   Business is continuous across a store's Aloha->Toast go-live. If the mapping
   is consistent, each mode column trends smoothly through the go-live date.
   If a column suddenly drops to ~0 while another jumps on the go-live date,
   that pair is a mis-mapped channel.

   Pick a store that cut over during a period WITH data on both sides.
   1188 = Lubbock, cut over ~2026-05-22 (last Aloha->Toast). Change if needed.
--------------------------------------------------------------------------- */
DECLARE @Store int = 1188;
DECLARE @SeamStart date = '2026-05-08';
DECLARE @SeamEnd   date = '2026-06-05';

PRINT '===== SECTION 5: per-day mode columns across a cutover seam =====';
SELECT
    DateOfBusiness,
    DineIn      = SUM(DineInNetSales),
    DineIn_OLO  = SUM(OLODineInNetSales),
    CallIn      = SUM(CallInNetSales),
    CallIn_OLO  = SUM(OLOCallInNetSales),
    ToGo        = SUM(ToGoNetSales),
    DriveThru   = SUM(DriveThruNetSales),
    Curb        = SUM(CurbSideNetSales),
    Curb_OLO    = SUM(CurbSideOLONetSales),
    OLO         = SUM(OLONetSales),
    GNG         = SUM(GNGNetSales),
    Catering    = SUM(CateringNetSales),
    DoorDash    = SUM(DoorDashNetSales),
    UberEats    = SUM(UberEatsNetSales),
    NetTotal    = SUM(NetSales)
FROM dev_aloha.dbo.tbl_SalesDataByDayPart
WHERE RestaurantID = @Store
  AND DateOfBusiness BETWEEN @SeamStart AND @SeamEnd
GROUP BY DateOfBusiness
ORDER BY DateOfBusiness;
GO
