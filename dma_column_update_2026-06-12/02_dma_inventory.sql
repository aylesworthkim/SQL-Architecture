-- =====================================================================
-- DMA column update 2026-06-12 — STEP 2: DMA inventory for the
-- Nielsen validation (boss request items 3 + 4)
--
-- Run both sections, paste the results back to Claude. The comparison
-- against the Nielsen DMA list happens offline; discrepancies come
-- back as 04_update_dma.sql.
--
-- Validating straight from the DB rather than the report export —
-- same data the report joins, plus we see stores with NULL/missing
-- DMA that the report would just show blank.
-- =====================================================================

USE contacts;

-- §1: every store with its current DMA assignment
SELECT
    s.StoreID,
    s.StoreName,
    s.StoreCity,
    s.StoreState,
    s.StoreZip,
    s.StoreStatus,
    s.StoreDMAID,
    d.DMAName AS Current_DMA
FROM contacts.dbo.Store s
LEFT JOIN contacts.dbo.DMA d ON d.DMAID = s.StoreDMAID
ORDER BY s.StoreState, s.StoreCity, s.StoreID;

-- §2: the DMA lookup itself (what names exist to map TO —
-- if a correct Nielsen DMA isn't in this table yet, the fix
-- script will need an INSERT before the Store update)
SELECT DMAID, DMAName
FROM contacts.dbo.DMA
ORDER BY DMAName;

-- §3: heads-up — dev_aloha keeps its OWN per-store DMA (it feeds the
-- Flash Report's DMA grouping via get_storesincluded). Same
-- denormalized-siblings trap as the May 26 StoreSysco incident.
-- Run this so we can see whether the two systems agree; ask boss
-- whether dev_aloha should be aligned to Nielsen too.
-- (Column names guessed — if this errors, run
--  sp_help 'dev_aloha.dbo.Stores' and adjust.)
SELECT
    si.StoreID,
    si.StoreName,
    si.DMAName AS DevAloha_DMA
FROM dev_aloha.dbo.get_storesincluded(9, '243', CONVERT(date, GETDATE()-1)) si
ORDER BY si.StoreID;
