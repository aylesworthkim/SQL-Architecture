-- =============================================================
-- Restaurant updates 2026-04-29 — STEP 1: DISCOVERY (read-only)
-- Run this in SSMS. Send Claude the result grids so we can write
-- the UPDATE in step 2 with the right column names.
-- =============================================================

USE contacts;
GO

-- ---------- 1) Column lists ----------
SELECT 'PrimaryContacts' AS table_name, ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'PrimaryContacts'
UNION ALL
SELECT 'AreaDir',         ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'AreaDir'
UNION ALL
SELECT 'store',           ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'store'
ORDER BY table_name, ORDINAL_POSITION;

-- ---------- 2) Foreign keys touching these tables ----------
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
WHERE  OBJECT_NAME(fk.parent_object_id)     IN ('AreaDir','PrimaryContacts','store')
   OR  OBJECT_NAME(fk.referenced_object_id) IN ('AreaDir','PrimaryContacts','store')
ORDER BY parent_table, fk_name;

-- ---------- 3) Existing rows ----------
-- Whole AreaDir table (should be small — one row per AD)
SELECT * FROM contacts.dbo.AreaDir;

-- All PrimaryContacts rows for the 10 stores
-- (we don't know the link column name yet, so just dump everything if needed —
--  but try the common name first)
SELECT * FROM contacts.dbo.PrimaryContacts
WHERE  storeid IN (1042,1053,1069,1073,1120,1127,1175,1178,1184,1189);

-- Store rows for the 10 stores (also surfaces any contact columns that live here)
SELECT * FROM contacts.dbo.store
WHERE  storeid IN (1042,1053,1069,1073,1120,1127,1175,1178,1184,1189);

-- ---------- 4) How AreaDir links to stores ----------
SELECT OBJECT_DEFINITION(OBJECT_ID('contacts.dbo.FN_GetAreaDirStores')) AS fn_definition;
