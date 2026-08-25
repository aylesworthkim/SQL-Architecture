-- =====================================================================
-- DMA column update 2026-06-12 — STEP 4: align Store DMAs with Nielsen
--
-- Validation performed 2026-06-12 against the Nielsen DMA list
-- (List_of_DMA_Codes CSV from boss) + Nielsen county assignments.
-- 91 of 99 stores on the report check out. 8 need fixes:
--
--   GEOGRAPHIC ERRORS (2):
--   * 1196 Statesboro GA: ATLANTA -> SAVANNAH
--       (Bulloch County GA is in the Savannah DMA, not Atlanta)
--   * 1194 Magee MS: HATTIESBURG-LAUREL -> JACKSON, MS
--       (Simpson County MS is one of the 22 Jackson-DMA counties;
--        Hattiesburg-Laurel is only Covington/Forrest/Jasper/Jones/
--        Lamar/Marion/Perry/Wayne)
--
--   NEVER-ASSIGNED DEFAULTS (6) — all show ABILENE-SWEETWATER, which
--   is just the first row of the DMA lookup; these are new/upcoming
--   stores nobody assigned:
--   * 1200 Columbus MS      -> COLUMBUS-TUPELO-WEST POINT
--   * 1201 Laurel MS        -> HATTIESBURG-LAUREL
--   * 1202 Wichita KS       -> WICHITA-HUTCHINSON PLUS
--   * 1203 Savannah GA      -> SAVANNAH
--   * 1204 Brookhaven MS    -> JACKSON, MS  (Lincoln County)
--   * 5002 Rockwall TX      -> DALLAS-FORT WORTH  (virtual site —
--        confirm with boss a virtual site should carry a DMA at all)
--
-- RUN ORDER: §1 (pre-flight), §2 only if SAVANNAH missing, §3 (update).
-- =====================================================================

USE contacts;
SET XACT_ABORT ON;

-- ============================================================
-- §1 PRE-FLIGHT — resolve every target label to a DMAID.
-- Every target below must return a row. If SAVANNAH is missing
-- (it may be — no store used it before), run §2 first.
-- ============================================================
SELECT DMAID, DMAName
FROM contacts.dbo.DMA
WHERE DMAName IN ('JACKSON, MS', 'SAVANNAH', 'HATTIESBURG-LAUREL',
                  'COLUMBUS-TUPELO-WEST POINT', 'WICHITA-HUTCHINSON PLUS',
                  'DALLAS-FORT WORTH')
ORDER BY DMAName;

-- ============================================================
-- §2 ONLY IF 'SAVANNAH' WAS MISSING from §1.
-- Variant A: DMAID is an identity column (most likely):
-- ============================================================
-- INSERT INTO contacts.dbo.DMA (DMAName) VALUES ('SAVANNAH');
--
-- Variant B: if Variant A errors with "Cannot insert explicit value /
-- column does not allow NULLs", DMAID is plain int — use:
-- INSERT INTO contacts.dbo.DMA (DMAID, DMAName)
-- SELECT ISNULL(MAX(DMAID),0)+1, 'SAVANNAH' FROM contacts.dbo.DMA;

-- ============================================================
-- §3 THE UPDATE — transaction-wrapped, BEFORE/AFTER visible
-- ============================================================
BEGIN TRANSACTION;

-- BEFORE
SELECT 'BEFORE' AS phase, s.StoreID, s.StoreName, s.StoreCity, s.StoreState,
       s.StoreDMAID, d.DMAName
FROM contacts.dbo.Store s
LEFT JOIN contacts.dbo.DMA d ON d.DMAID = s.StoreDMAID
WHERE s.StoreID IN (1194, 1196, 1200, 1201, 1202, 1203, 1204, 5002)
ORDER BY s.StoreID;

-- the fix list: StoreID -> target DMAName
WITH fixes (StoreID, TargetDMA) AS (
    SELECT 1194, 'JACKSON, MS'                UNION ALL  -- Magee MS (Simpson Co)
    SELECT 1196, 'SAVANNAH'                   UNION ALL  -- Statesboro GA (Bulloch Co)
    SELECT 1200, 'COLUMBUS-TUPELO-WEST POINT' UNION ALL  -- Columbus MS
    SELECT 1201, 'HATTIESBURG-LAUREL'         UNION ALL  -- Laurel MS (Jones Co)
    SELECT 1202, 'WICHITA-HUTCHINSON PLUS'    UNION ALL  -- Wichita KS (Avante)
    SELECT 1203, 'SAVANNAH'                   UNION ALL  -- Savannah GA (Midtown)
    SELECT 1204, 'JACKSON, MS'                UNION ALL  -- Brookhaven MS (Lincoln Co)
    SELECT 5002, 'DALLAS-FORT WORTH'                     -- Rockwall TX virtual
)
UPDATE s SET s.StoreDMAID = d.DMAID
FROM contacts.dbo.Store s
JOIN fixes f ON f.StoreID = s.StoreID
JOIN contacts.dbo.DMA d ON d.DMAName = f.TargetDMA;

SELECT @@ROWCOUNT AS RowsUpdated;   -- expect 8

-- AFTER
SELECT 'AFTER' AS phase, s.StoreID, s.StoreName, s.StoreCity, s.StoreState,
       s.StoreDMAID, d.DMAName
FROM contacts.dbo.Store s
LEFT JOIN contacts.dbo.DMA d ON d.DMAID = s.StoreDMAID
WHERE s.StoreID IN (1194, 1196, 1200, 1201, 1202, 1203, 1204, 5002)
ORDER BY s.StoreID;

-- Eyeball the AFTER block, then run ONE of:
-- COMMIT TRANSACTION;
-- ROLLBACK TRANSACTION;
