-- =====================================================================
-- Sysco Market mass-update 2026-05-26 — STEP 4: Fix StoreSysco
--
-- Background: the SSRS Restaurant Contact Information Sheet calls
-- sp_rpt_DSP_Restaurant_Location_Coverage_Check_Report, which joins
-- *through contacts.dbo.StoreSysco* (NOT Store.StoreSyscoID).
-- Earlier discovery missed this because the report's
-- Store.StoreSyscoID column happens to mirror StoreSysco for most rows.
-- They are denormalized siblings that can drift apart.
--
-- This script syncs StoreSysco with what we already wrote to
-- Store.StoreSyscoID earlier today:
--   * UPDATE existing StoreSysco rows for 13 stores
--   * INSERT a new StoreSysco row for 1199 Wichita (no row existed)
-- All in one batch, transaction-wrapped, no GO between BEGIN TRAN
-- and the writes.
-- =====================================================================

USE contacts;
SET XACT_ABORT ON;

-- --- One-time eyeball: confirm the proc's join goes through StoreSysco
PRINT '--- sp_rpt_DSP_Restaurant_Location_Coverage_Check_Report definition ---';
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_DSP_Restaurant_Location_Coverage_Check_Report'))
       AS proc_definition;

BEGIN TRANSACTION;

-- BEFORE: StoreSysco state of all rows we're about to touch (13 + the absent 1199)
SELECT 'BEFORE-ss' AS phase,
       ss.UniqueID, ss.StoreID,
       ss.SyscoID AS cur_sysco_id,
       sm.SyscoMarket AS cur_label
FROM   contacts.dbo.StoreSysco ss
LEFT JOIN contacts.dbo.SyscoMarket sm ON sm.SyscoID = ss.SyscoID
WHERE  ss.StoreID IN (1019,1023,1034,1037,1053,1097,1099,1104,1118,1176,1180,1188,1195)
UNION ALL
SELECT 'BEFORE-ss-missing', NULL, 1199, NULL, NULL
WHERE  NOT EXISTS (SELECT 1 FROM contacts.dbo.StoreSysco WHERE StoreID = 1199)
ORDER BY 3;  -- by StoreID

-- 1) UPDATE the 13 existing StoreSysco rows
WITH ss_moves (StoreID, NewSyscoID) AS (
    SELECT 1019, 58 UNION ALL  -- Murfreesboro TN (Avenues)    -> Nashville
    SELECT 1023, 34 UNION ALL  -- Panama City FL               -> Gulf Coast
    SELECT 1034, 58 UNION ALL  -- Franklin TN (Cool Springs)   -> Nashville
    SELECT 1037, 34 UNION ALL  -- Tallahassee FL               -> Gulf Coast
    SELECT 1053, 58 UNION ALL  -- Knoxville TN (Cedar Bluff)   -> Nashville
    SELECT 1097, 34 UNION ALL  -- Spanish Fort AL              -> Gulf Coast
    SELECT 1099, 34 UNION ALL  -- Mobile AL (McGowin Park)     -> Gulf Coast
    SELECT 1104, 34 UNION ALL  -- Mobile AL (Westgate Pavilion)-> Gulf Coast
    SELECT 1118, 58 UNION ALL  -- Murfreesboro TN (Northgate)  -> Nashville
    SELECT 1176, 58 UNION ALL  -- Chattanooga TN               -> Nashville
    SELECT 1180, 76 UNION ALL  -- San Angelo TX                -> West Texas
    SELECT 1188, 76 UNION ALL  -- Lubbock TX (Broadway)        -> West Texas
    SELECT 1195,  5            -- Mandeville LA                -> Jackson (sync after drift)
)
UPDATE ss
SET    ss.SyscoID = mv.NewSyscoID
FROM   contacts.dbo.StoreSysco ss
JOIN   ss_moves mv ON mv.StoreID = ss.StoreID;

DECLARE @updatedA INT = @@ROWCOUNT;
PRINT CONCAT('StoreSysco UPDATEs: ', @updatedA, ' rows (expected 13)');

-- 2) INSERT the missing row for 1199 Wichita
--    (UniqueID is the table PK; assumed IDENTITY. If it isn't, this will error
--     and the TRAN can be rolled back -- we'll handle that case separately.)
IF NOT EXISTS (SELECT 1 FROM contacts.dbo.StoreSysco WHERE StoreID = 1199)
BEGIN
    INSERT INTO contacts.dbo.StoreSysco (StoreID, SyscoID)
    VALUES (1199, 46);  -- Kansas City
    PRINT 'Inserted StoreSysco row for 1199 -> Kansas City';
END
ELSE
BEGIN
    PRINT '1199 already has a StoreSysco row -- INSERT skipped';
END

-- AFTER: confirm the 14 stores all now point at the right label via StoreSysco
SELECT 'AFTER-ss' AS phase,
       ss.UniqueID, ss.StoreID,
       ss.SyscoID AS new_sysco_id,
       sm.SyscoMarket AS new_label
FROM   contacts.dbo.StoreSysco ss
LEFT JOIN contacts.dbo.SyscoMarket sm ON sm.SyscoID = ss.SyscoID
WHERE  ss.StoreID IN (1019,1023,1034,1037,1053,1097,1099,1104,1118,1176,1180,1188,1195,1199)
ORDER BY ss.StoreID;

-- =====================================================================
-- Eyeball the AFTER grid:
--   1019 -> Nashville     1023 -> Gulf Coast     1034 -> Nashville
--   1037 -> Gulf Coast    1053 -> Nashville      1097 -> Gulf Coast
--   1099 -> Gulf Coast    1104 -> Gulf Coast     1118 -> Nashville
--   1176 -> Nashville     1180 -> West Texas     1188 -> West Texas
--   1195 -> Jackson       1199 -> Kansas City
--
-- If all 14 rows look right:    COMMIT TRANSACTION;
-- Else:                          ROLLBACK TRANSACTION;
-- =====================================================================
