/* =====================================================================
   Batch ID map  -  store  ->  ADP Batch ID / Batch Description
   ---------------------------------------------------------------------
   The lookup behind columns 2 and 4 of the Company Store Payroll
   Export - Toast report. Both come from dev_aloha.dbo.gblstore, keyed
   on the restaurant's StoreID.

   Flags show which store set each store belongs to, so it is obvious
   which rows can ever reach ADP:
     InCompany_9_79   - * All - Company Restaurants (the payroll set)
     InCorpToast_9_244 - corporate Toast stores (the proc default)
     InAllStores_2_0  - what the 2026-08-20 reference run used

   Read-only.
   ===================================================================== */

SET NOCOUNT ON;

DECLARE @AsOf date = '2026-08-16';   -- store-set membership is date-sensitive

SELECT
    gs.StoreId,
    gs.Name                                  AS StoreName,
    gs.ShortStoreName,
    gs.ADPBatchID,
    gs.ADPBatchDescription,
    CASE WHEN c79.StoreID  IS NULL THEN 0 ELSE 1 END AS InCompany_9_79,
    CASE WHEN c244.StoreID IS NULL THEN 0 ELSE 1 END AS InCorpToast_9_244,
    CASE WHEN a0.StoreID   IS NULL THEN 0 ELSE 1 END AS InAllStores_2_0,
    gs.DeleteStore                           AS IsDeletedStore,
    CASE
        WHEN ISNULL(gs.ADPBatchID,'') = ''  THEN 'MISSING - no ADPBatchID set'
        WHEN gs.ADPBatchID = '0'            THEN 'PLACEHOLDER - ADPBatchID is 0'
        WHEN gs.ADPBatchID = CONVERT(varchar(20), gs.StoreId) THEN 'OK - matches store number'
        ELSE 'OK - differs from store number'
    END                                      AS BatchIDStatus,
    CASE WHEN ISNULL(gs.ADPBatchDescription,'') = ''
         THEN 'blank' ELSE 'set' END         AS BatchDescriptionStatus
FROM dev_aloha.dbo.gblstore gs
LEFT JOIN dev_aloha.dbo.get_StoresIncluded(9,'79',  @AsOf) c79  ON c79.StoreID  = gs.StoreId
LEFT JOIN dev_aloha.dbo.get_StoresIncluded(9,'244', @AsOf) c244 ON c244.StoreID = gs.StoreId
LEFT JOIN dev_aloha.dbo.get_StoresIncluded(2,'0',   @AsOf) a0   ON a0.StoreID   = gs.StoreId
ORDER BY gs.StoreId;
