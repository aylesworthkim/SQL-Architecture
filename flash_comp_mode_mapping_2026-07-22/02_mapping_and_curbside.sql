/* ============================================================================
   02_mapping_and_curbside.sql   (2026-07-22)  -- read-only

   Findings so far:
     * Aloha & Toast rollups use IDENTICAL OrderModeID->column logic.
     * Company YTD comps are normal for every mode EXCEPT CurbSide (-39%).
   This pack settles whether CurbSide (and mode tagging generally) is a real
   trend or a Toast dining-option -> OrderMode mapping artifact.
   ============================================================================ */

/* --- Q1: the Toast dining-option -> OrderMode mapping (SELECT * this time) ---
   This is the one table we still need. It decides which OrderModeID each Toast
   order is tagged with. Compare its curbside/togo/olo rows to the Aloha scheme
   (12=Curbside, 103=CurbSideOLO, 2/108=ToGo, 100=OLO, 1/107=DineIn). */
SELECT * FROM toast.dbo.cfg_map_DiningOptionToOrderMode ORDER BY OrderModeID;
GO

/* --- Q2: CurbSide by MONTH, CY(2026) vs PY(2025), company-wide ---
   Step-change down as stores cut to Toast  => mapping artifact.
   Gradual glide down                        => real post-COVID behavior. */
USE dev_aloha;
DECLARE @AsOf date = '2026-07-21';
SELECT
    MonthNo = MONTH(DateOfBusiness),
    Curb_2025 = SUM(CASE WHEN YEAR(DateOfBusiness)=2025 THEN CurbSideNetSales + CurbSideOLONetSales ELSE 0 END),
    Curb_2026 = SUM(CASE WHEN YEAR(DateOfBusiness)=2026 THEN CurbSideNetSales + CurbSideOLONetSales ELSE 0 END)
FROM dev_aloha.dbo.tbl_SalesDataByDayPart
WHERE DateOfBusiness BETWEEN '2025-01-01' AND @AsOf
  AND RestaurantID IN (SELECT storeid FROM dev_aloha.dbo.get_StoresIncluded(9,'4',@AsOf))
GROUP BY MONTH(DateOfBusiness)
ORDER BY MonthNo;
GO

/* --- Q3: pick a clean cutover-seam store (has BOTH Aloha and Toast rows) ---
   The 1188 test failed because 1188 had no pre-cutover Aloha rows. Find stores
   that actually straddle their ToastLive so we can eyeball mode continuity. */
DECLARE @AsOf2 date = '2026-07-21';
SELECT TOP 20
    s.storeid, s.storename, s.ToastLive,
    AlohaDays = SUM(CASE WHEN t.DateOfBusiness <  s.ToastLive THEN 1 ELSE 0 END),
    ToastDays = SUM(CASE WHEN t.DateOfBusiness >= s.ToastLive THEN 1 ELSE 0 END)
FROM dev_aloha.dbo.get_StoresIncluded(9,'4',@AsOf2) s
JOIN dev_aloha.dbo.tbl_SalesDataByDayPart t ON t.RestaurantID = s.storeid
WHERE t.DateOfBusiness BETWEEN DATEADD(DAY,-30,s.ToastLive) AND DATEADD(DAY,30,s.ToastLive)
  AND s.ToastLive > '2025-01-01' AND s.ToastLive < '2026-06-01'
GROUP BY s.storeid, s.storename, s.ToastLive
HAVING SUM(CASE WHEN t.DateOfBusiness <  s.ToastLive THEN 1 ELSE 0 END) >= 7
   AND SUM(CASE WHEN t.DateOfBusiness >= s.ToastLive THEN 1 ELSE 0 END) >= 7
ORDER BY s.ToastLive DESC;
GO
-- Then re-run Section 5 of 01_discovery.sql with @Store set to one of these
-- storeids and @SeamStart/@SeamEnd bracketing its ToastLive.
