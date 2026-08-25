-- =============================================================
-- Restaurant updates 2026-04-29 - STEP 2: UPDATE (transactional)
-- Boss ticket: 10 Roundtable / Relentless stores ->
--   - Primary contact: Wes Williams (PrimaryContacts.PrimaryID = 24)
--   - Area Director:   Brenda Graf  (AreaDir.AreaDirID         = 2118)
-- Net changes vs current state (verified 2026-04-29):
--   - 5 primary contacts flip from Todd White (21) -> Wes (24)
--   - 8 area directors flip (5 from Wes 2088, 3 from Jack 2106) -> Brenda 2118
--   - The remaining re-sets are no-ops
-- =============================================================

USE contacts;
GO

BEGIN TRANSACTION;

-- BEFORE snapshot
SELECT 'BEFORE' AS phase, s.storeid, s.StoreName,
       s.StorePrimaryContact AS pc_id, pc.PrimaryName AS pc_name,
       s.StoreAreaDirID      AS ad_id, ad.AreaDirName  AS ad_name
FROM   contacts.dbo.store s
LEFT JOIN contacts.dbo.PrimaryContacts pc ON pc.PrimaryID  = s.StorePrimaryContact
LEFT JOIN contacts.dbo.AreaDir         ad ON ad.AreaDirID  = s.StoreAreaDirID
WHERE  s.storeid IN (1042,1053,1069,1073,1120,1127,1175,1178,1184,1189)
ORDER BY s.storeid;

-- 1) Primary contact -> Wes Williams (PrimaryID 24)
UPDATE contacts.dbo.store
SET    StorePrimaryContact = 24,
       LastUpdated   = GETDATE(),
       LastUpdatedBy = 'Kim Aylesworth'
WHERE  storeid IN (1042,1053,1069,1073,1120,1127,1175,1178,1184,1189);

-- 2) Area Director -> Brenda Graf (AreaDirID 2118)
UPDATE contacts.dbo.store
SET    StoreAreaDirID = 2118,
       LastUpdated   = GETDATE(),
       LastUpdatedBy = 'Kim Aylesworth'
WHERE  storeid IN (1042,1053,1069,1073,1120,1127,1175,1178,1184,1189);

-- AFTER snapshot
SELECT 'AFTER'  AS phase, s.storeid, s.StoreName,
       s.StorePrimaryContact AS pc_id, pc.PrimaryName AS pc_name,
       s.StoreAreaDirID      AS ad_id, ad.AreaDirName  AS ad_name
FROM   contacts.dbo.store s
LEFT JOIN contacts.dbo.PrimaryContacts pc ON pc.PrimaryID  = s.StorePrimaryContact
LEFT JOIN contacts.dbo.AreaDir         ad ON ad.AreaDirID  = s.StoreAreaDirID
WHERE  s.storeid IN (1042,1053,1069,1073,1120,1127,1175,1178,1184,1189)
ORDER BY s.storeid;

-- ---- review the AFTER grid ----
-- If every pc_name = 'Wes Williams' and every ad_name = 'Brenda Graf':
--    COMMIT TRANSACTION;
-- Otherwise:
--    ROLLBACK TRANSACTION;
