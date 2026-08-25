-- =====================================================================
-- Sysco Market mass-update 2026-05-26 — STEP 3: REDO Part B only
--
-- Background: 02_update.sql ran but only Part A (SyscoMarket renames)
-- persisted. The 13 Store.StoreSyscoID re-points didn't take effect,
-- almost certainly because the original script had GO between batches
-- and the COMMIT only covered the first batch.
--
-- This script:
--   - is a single batch (no GO between BEGIN TRAN and the UPDATE)
--   - touches only the 13 stores that need re-pointing
--   - prints BEFORE/AFTER inside the transaction
--   - waits for an explicit COMMIT / ROLLBACK at the end
--
-- Note about 1195 Mandeville:
--   In the discovery (2026-05-26 earlier today), 1195 was at SyscoID=5
--   (Jackson) — correct per the xlsx. In the latest SSRS export it now
--   shows "** Choose", meaning Store.StoreSyscoID=1. Something flipped
--   it between discovery and now (possibly a manual edit via the forms
--   site). Excluded from this auto-fix — flag for Kim's review.
-- =====================================================================

USE contacts;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

-- BEFORE: current state of the 13 stores
SELECT 'BEFORE-store' AS phase, s.StoreID, s.StoreName,
       s.StoreSyscoID AS cur_sysco_id,
       sm.Company_Name AS cur_company_name,
       sm.SyscoMarket  AS cur_sysco_label
FROM   contacts.dbo.Store s
LEFT JOIN contacts.dbo.SyscoMarket sm ON sm.SyscoID = s.StoreSyscoID
WHERE  s.StoreID IN (1019,1023,1034,1037,1053,1097,1099,1104,1118,1176,1180,1188,1199)
ORDER BY s.StoreID;

-- The actual UPDATE
WITH store_moves (StoreID, NewSyscoID) AS (
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
    SELECT 1199, 46            -- Wichita KS (Waterfront)      -> Kansas City
)
UPDATE s
SET    s.StoreSyscoID  = mv.NewSyscoID,
       s.LastUpdated   = GETDATE(),
       s.LastUpdatedBy = 'Kim Aylesworth'
FROM   contacts.dbo.Store s
JOIN   store_moves mv ON mv.StoreID = s.StoreID;

DECLARE @rows INT = @@ROWCOUNT;
PRINT CONCAT('Part B Store.StoreSyscoID re-points: ', @rows, ' rows (expected 13)');

-- AFTER: confirm every one of the 13 now shows the right label
SELECT 'AFTER-store' AS phase, s.StoreID, s.StoreName,
       s.StoreSyscoID AS new_sysco_id,
       sm.Company_Name AS new_company_name,
       sm.SyscoMarket  AS new_sysco_label
FROM   contacts.dbo.Store s
LEFT JOIN contacts.dbo.SyscoMarket sm ON sm.SyscoID = s.StoreSyscoID
WHERE  s.StoreID IN (1019,1023,1034,1037,1053,1097,1099,1104,1118,1176,1180,1188,1199)
ORDER BY s.StoreID;

-- =====================================================================
-- If the PRINT says "13 rows" and the AFTER grid shows the expected
-- labels (Nashville x5, Gulf Coast x5, West Texas x2, Kansas City x1):
--      COMMIT TRANSACTION;
-- Else:
--      ROLLBACK TRANSACTION;
-- =====================================================================
