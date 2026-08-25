-- =====================================================================
-- Sysco Market mass-update 2026-05-26 — STEP 2: UPDATE (transactional)
--
-- Goal: Make the SSRS Restaurant Contact Information Sheet's
--       "Sysco Market" column display the DC Name from
--       "Restaurant by Sysco Center (1).xlsx" for every store.
--
-- Strategy decided after discovery (see SUMMARY.md in this folder):
--   A) Rename 15 existing rows in contacts.dbo.SyscoMarket.SyscoMarket
--      column from "SYSCO - XXX" to the new DC Name. 14 of the 15 are
--      same-row renames; 1 is SyscoID=10 (formerly WEST COAST FLORIDA /
--      SYSCO - WCF) renamed to Tampa Bay per Kim's call.
--      Company_Name and all other SyscoMarket columns are LEFT ALONE.
--
--   B) Re-point Store.StoreSyscoID for 13 stores whose xlsx market
--      assignment differs from their current StoreSyscoID:
--         * 5 TN stores: KNOXVILLE (8) -> Nashville (58)
--         * 5 FL/AL stores: CENTRAL ALABAMA (7) -> Gulf Coast (34)
--         * 1 TX store (1180 San Angelo): CENTRAL TEXAS (4) -> West Texas (76)
--         * 1 TX store (1188 Lubbock): ** Choose (1) -> West Texas (76)
--         * 1 KS store (1199 Wichita): ** Choose (1) -> Kansas City (46)
--
--   Skipped: store 1096 (zClosed - Little Rock AR Pleasant Ridge) shows
--   up in the xlsx under "Gulf Coast" but is closed and currently
--   sits at SyscoID=2 (Arkansas). Reach out to the boss if needed.
--
-- This script is wrapped in BEGIN TRAN / COMMIT.  Run it whole,
-- inspect the BEFORE/AFTER grids, then run COMMIT or ROLLBACK at the end.
-- =====================================================================

USE contacts;
GO

SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- =====================================================================
-- BEFORE snapshot — current state of all rows we are about to touch
-- =====================================================================
PRINT '--- BEFORE: SyscoMarket rows we will rename ---';
SELECT 'BEFORE-sm' AS phase, SyscoID, Company_Name, SyscoMarket
FROM   contacts.dbo.SyscoMarket
WHERE  SyscoID IN (2,3,4,5,6,7,9,10,11,12,14,34,46,58,76)
ORDER BY SyscoID;

PRINT '--- BEFORE: 13 stores whose StoreSyscoID we will change ---';
SELECT 'BEFORE-store' AS phase, s.StoreID, s.StoreName,
       s.StoreSyscoID AS cur_sysco_id,
       sm.Company_Name AS cur_company_name,
       sm.SyscoMarket  AS cur_sysco_label
FROM   contacts.dbo.Store s
LEFT JOIN contacts.dbo.SyscoMarket sm ON sm.SyscoID = s.StoreSyscoID
WHERE  s.StoreID IN (1019,1023,1034,1037,1053,1097,1099,1104,1118,1176,1180,1188,1199)
ORDER BY s.StoreID;
GO

-- =====================================================================
-- Part A — Rename the SyscoMarket.SyscoMarket column on 15 rows.
-- Uses a VALUES-based join so it's one statement, easy to audit.
-- =====================================================================
WITH new_names (SyscoID, NewLabel) AS (
    SELECT  2, 'Arkansas'         UNION ALL
    SELECT  3, 'East Texas'       UNION ALL
    SELECT  4, 'Central Texas'    UNION ALL
    SELECT  5, 'Jackson'          UNION ALL
    SELECT  6, 'Memphis'          UNION ALL
    SELECT  7, 'Central Alabama'  UNION ALL
    SELECT  9, 'Atlanta'          UNION ALL
    SELECT 10, 'Tampa Bay'        UNION ALL  -- was 'SYSCO - WCF' (WEST COAST FLORIDA)
    SELECT 11, 'Charlotte'        UNION ALL
    SELECT 12, 'Baltimore'        UNION ALL
    SELECT 14, 'Denver'           UNION ALL
    SELECT 34, 'Gulf Coast'       UNION ALL
    SELECT 46, 'Kansas City'      UNION ALL
    SELECT 58, 'Nashville'        UNION ALL
    SELECT 76, 'West Texas'
)
UPDATE sm
SET    sm.SyscoMarket = nn.NewLabel
FROM   contacts.dbo.SyscoMarket sm
JOIN   new_names nn ON nn.SyscoID = sm.SyscoID;

DECLARE @rowsA INT = @@ROWCOUNT;
PRINT CONCAT('Part A SyscoMarket renames: ', @rowsA, ' rows (expected 15)');
GO

-- =====================================================================
-- Part B — Re-point Store.StoreSyscoID for 13 stores.
-- =====================================================================
WITH store_moves (StoreID, NewSyscoID) AS (
    SELECT 1019, 58 UNION ALL  -- Murfreesboro TN (Avenues)        Knoxville  -> Nashville
    SELECT 1023, 34 UNION ALL  -- Panama City FL                   CentralAL  -> Gulf Coast
    SELECT 1034, 58 UNION ALL  -- Franklin TN (Cool Springs)       Knoxville  -> Nashville
    SELECT 1037, 34 UNION ALL  -- Tallahassee FL                   CentralAL  -> Gulf Coast
    SELECT 1053, 58 UNION ALL  -- Knoxville TN (Cedar Bluff)       Knoxville  -> Nashville
    SELECT 1097, 34 UNION ALL  -- Spanish Fort AL                  CentralAL  -> Gulf Coast
    SELECT 1099, 34 UNION ALL  -- Mobile AL (McGowin Park)         CentralAL  -> Gulf Coast
    SELECT 1104, 34 UNION ALL  -- Mobile AL (Westgate Pavilion)    CentralAL  -> Gulf Coast
    SELECT 1118, 58 UNION ALL  -- Murfreesboro TN (Northgate)      Knoxville  -> Nashville
    SELECT 1176, 58 UNION ALL  -- Chattanooga TN                   Knoxville  -> Nashville
    SELECT 1180, 76 UNION ALL  -- San Angelo TX                    CentralTX  -> West Texas
    SELECT 1188, 76 UNION ALL  -- Lubbock TX (Broadway)            ** Choose  -> West Texas
    SELECT 1199, 46            -- Wichita KS (Waterfront)          ** Choose  -> Kansas City
)
UPDATE s
SET    s.StoreSyscoID  = sm.NewSyscoID,
       s.LastUpdated   = GETDATE(),
       s.LastUpdatedBy = 'Kim Aylesworth'
FROM   contacts.dbo.Store s
JOIN   store_moves sm ON sm.StoreID = s.StoreID;

DECLARE @rowsB INT = @@ROWCOUNT;
PRINT CONCAT('Part B Store.StoreSyscoID re-points: ', @rowsB, ' rows (expected 13)');
GO

-- =====================================================================
-- AFTER snapshot — eyeball these before deciding to commit
-- =====================================================================
PRINT '--- AFTER: SyscoMarket rows we renamed ---';
SELECT 'AFTER-sm' AS phase, SyscoID, Company_Name, SyscoMarket
FROM   contacts.dbo.SyscoMarket
WHERE  SyscoID IN (2,3,4,5,6,7,9,10,11,12,14,34,46,58,76)
ORDER BY SyscoID;

PRINT '--- AFTER: 13 stores we re-pointed ---';
SELECT 'AFTER-store' AS phase, s.StoreID, s.StoreName,
       s.StoreSyscoID AS new_sysco_id,
       sm.Company_Name AS new_company_name,
       sm.SyscoMarket  AS new_sysco_label
FROM   contacts.dbo.Store s
LEFT JOIN contacts.dbo.SyscoMarket sm ON sm.SyscoID = s.StoreSyscoID
WHERE  s.StoreID IN (1019,1023,1034,1037,1053,1097,1099,1104,1118,1176,1180,1188,1199)
ORDER BY s.StoreID;

-- Full SSRS-equivalent view: every store with its new Sysco Market label.
-- This is what the SSRS "Sysco Market" column will show after commit.
PRINT '--- AFTER: full Store -> Sysco Market preview (top 30 + the 13 re-points) ---';
SELECT TOP 30 s.StoreID, s.StoreName, sm.SyscoMarket AS new_ssrs_value
FROM   contacts.dbo.Store s
LEFT JOIN contacts.dbo.SyscoMarket sm ON sm.SyscoID = s.StoreSyscoID
WHERE  s.StoreStatus = 'Open'           -- adjust if the column name differs
   OR  s.StoreID IN (1019,1023,1034,1037,1053,1097,1099,1104,1118,1176,1180,1188,1199)
ORDER BY s.StoreID;
GO

-- =====================================================================
-- If the AFTER grids look correct:    COMMIT TRANSACTION;
-- If anything looks wrong:            ROLLBACK TRANSACTION;
-- =====================================================================
-- (Do NOT just close the query window without picking one — the
--  transaction will linger and block the SyscoMarket / Store rows.)
