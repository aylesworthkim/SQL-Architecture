-- =====================================================================
-- Sysco Market mass-update 2026-05-26 — STEP 1: DISCOVERY (read-only)
--
-- Goal: For every store in the SSRS Restaurant Contact Information
-- Sheet, change the "Sysco Market" column to match the "DC Name"
-- column from "Restaurant by Sysco Center (1).xlsx".
--
-- The schema doc says two tables are involved with Sysco:
--   contacts.dbo.SyscoMarket  (76 rows, PK SyscoID)        -- lookup
--   contacts.dbo.StoreSysco   (163 rows, PK UniqueID)      -- per-store?
--   contacts.dbo.Store.StoreSyscoID  (int)                 -- FK on Store
--
-- Goal of this script: confirm exactly which column on which table
-- the SSRS report reads, what the current names look like, and what
-- new rows (if any) we need to add to SyscoMarket for the 15 DC Names
-- the xlsx introduces.
--
-- This script is 100% read-only. Send Claude all the result grids.
-- =====================================================================

USE contacts;
GO

-- =====================================================================
-- 1) Column lists for the three tables in play
-- =====================================================================
SELECT 'SyscoMarket' AS tbl, ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE,
       CHARACTER_MAXIMUM_LENGTH AS max_len, IS_NULLABLE
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'SyscoMarket'
UNION ALL
SELECT 'StoreSysco',  ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE,
       CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'StoreSysco'
UNION ALL
SELECT 'Store (StoreSyscoID only)', ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE,
       CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Store'
  AND  COLUMN_NAME LIKE '%Sysco%'
ORDER BY tbl, ORDINAL_POSITION;
GO

-- =====================================================================
-- 2) Foreign keys involving the Sysco tables (which side owns StoreSyscoID?)
-- =====================================================================
SELECT
    fk.name                              AS fk_name,
    OBJECT_NAME(fk.parent_object_id)     AS parent_table,
    cp.name                              AS parent_column,
    OBJECT_NAME(fk.referenced_object_id) AS referenced_table,
    cr.name                              AS referenced_column
FROM   sys.foreign_keys fk
JOIN   sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN   sys.columns cp ON cp.object_id = fk.parent_object_id     AND cp.column_id = fkc.parent_column_id
JOIN   sys.columns cr ON cr.object_id = fk.referenced_object_id AND cr.column_id = fkc.referenced_column_id
WHERE  OBJECT_NAME(fk.parent_object_id)     IN ('SyscoMarket','StoreSysco','Store')
   OR  OBJECT_NAME(fk.referenced_object_id) IN ('SyscoMarket','StoreSysco','Store')
ORDER BY parent_table, fk_name;
GO

-- =====================================================================
-- 3) Whole SyscoMarket table (76 rows expected — what names exist today)
-- =====================================================================
SELECT * FROM contacts.dbo.SyscoMarket ORDER BY 1;
GO

-- =====================================================================
-- 4) Whole StoreSysco table — see whether each store has 0/1/many rows
--    and what columns it actually carries
-- =====================================================================
SELECT TOP 20 * FROM contacts.dbo.StoreSysco ORDER BY 1;

SELECT COUNT(*) AS row_count,
       COUNT(DISTINCT storeid) AS distinct_storeids,
       MIN(storeid) AS min_sid,
       MAX(storeid) AS max_sid
FROM contacts.dbo.StoreSysco;
GO

-- =====================================================================
-- 5) Show the current "Sysco Market" linkage for every store —
--    joining Store.StoreSyscoID -> SyscoMarket.SyscoID (best guess)
-- =====================================================================
SELECT s.StoreID, s.StoreName, s.StoreState,
       s.StoreSyscoID,
       sm.*    -- everything from SyscoMarket so we can see all its cols
FROM   contacts.dbo.Store s
LEFT JOIN contacts.dbo.SyscoMarket sm
       ON sm.SyscoID = s.StoreSyscoID
ORDER BY s.StoreID;
GO

-- =====================================================================
-- 6) What stored proc / view powers the SSRS report?
--    Find the proc that joins Store + SyscoMarket and inspect its text.
-- =====================================================================
SELECT o.name, o.type_desc
FROM   sys.objects o
WHERE  o.type IN ('P','V','IF','TF','FN')
  AND  OBJECT_DEFINITION(o.object_id) LIKE '%SyscoMarket%'
ORDER BY o.name;
GO

-- =====================================================================
-- 7) See the body of the proc that the SSRS report calls.
--    (Once we know the proc name from step 6, swap it in here.
--     For now, dump the one named in contacts dependency.rpt.)
-- =====================================================================
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_DSP_Restaurant_Location_Coverage_Check_Report')) AS proc_def;
GO
