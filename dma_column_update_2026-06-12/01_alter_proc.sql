-- =====================================================================
-- DMA column update 2026-06-12 — STEP 1: alter the report proc
--
-- Boss request:
--   1. Remove the Aloha POS ID/Key # column ("pos Key") from the
--      Restaurant Contact Information Sheet
--   2. Add a DMA column at the end, immediately after Sysco Market
--   (3. validate DMA vs Nielsen — separate step, see 03_*)
--
-- The report's dataset is contacts.dbo.sp_rpt_DSP_Restaurant_Location_
-- Coverage_Check_Report (despite the name). The RDL must ALSO change
-- (pos Key column removed, DMA column added) — see the modified .rdl
-- in this folder; upload it via the SSRS portal (Replace).
--
-- RUN ORDER: Section 0 sanity checks, then Section 1 (the ALTER).
-- =====================================================================

USE contacts;
GO

-- ============================================================
-- SECTION 0 — sanity checks (read-only)
-- ============================================================

-- 0a: confirm the DMA lookup table + Store FK look as expected
SELECT TOP 5 * FROM contacts.dbo.DMA ORDER BY DMAID;

SELECT COUNT(*)                                   AS stores_total,
       SUM(CASE WHEN StoreDMAID IS NULL THEN 1 ELSE 0 END) AS stores_missing_dma
FROM contacts.dbo.Store;

-- 0b: confirm the live proc still matches the 2026-04-29 extract
-- (the May 26 Sysco work changed DATA only, not this proc — verify)
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_rpt_DSP_Restaurant_Location_Coverage_Check_Report'));
GO

-- ============================================================
-- SECTION 1 — ALTER the proc
-- Changes vs prior version (v5):
--   * posKey column REMOVED from #Results + its UPDATE block removed
--     (was populated from contacts.dbo.StoreTechnical.POSKey)
--   * DMA column ADDED after SyscoMarket, populated from
--     Store.StoreDMAID -> contacts.dbo.DMA.DMAName
-- ============================================================

ALTER PROCEDURE [dbo].[sp_rpt_DSP_Restaurant_Location_Coverage_Check_Report]
(
    @StoreGrouping int,
    @StoreGroup varchar(1500)
)
AS
/**
    ## Procedure Name       *[contacts].[dbo].[sp_rpt_DSP_Restaurant_Location_Coverage_Check_Report]*
    **Procedure Type**      *stored procedure*
    **Author**              Wilson, Don < dwilson@newks.com >
    **Version**             1
    **Created**             20190412
    **Report Name**         *Marketing >> Restaurant Contact Information Sheet*
    **Summary**
    *Commissioned by Adam, this provides a list of store attributes for providing to vendors.*

    ### Parameters
    ```sql
    StoreGrouping int           The grouping type of stores
    StoreGroup varchar(1500)    The store / store group / dma / etc to run for
    ```

    ### Output
    *Store ID
    Store Name
    OLO Vendor ID
    Store Status
    Ownership type
    Address
    City
    State
    Zip
    Phone
    Store Email
    Area Director Name
    Area Director Email
    Sysco Market
    DMA*

    ### Change History
    **Change Date:**            *20260612*
    **Author:**                 *Aylesworth, Kim < kaylesworth@newks.com >*
    **Version**:                6
    **Change:**
    *Remove Aloha POS Key column; add DMA column after Sysco Market (per boss request)*

    **Change Date:**            *20200630*
    **Author:**                 *Wilson, Don < dwilson@newks.com >*
    **Version**:                5
    **Change:**
    *Add USF Market*

    **Change Date:**            *20200529*
    **Author:**                 *Wilson, Don < dwilson@newks.com >*
    **Version**:                4
    **Change:**
    *Add OLO Kiosk Vendor ID*

    **Change Date:**            *20200403*
    **Author:**                 *Wilson, Don < dwilson@newks.com >*
    **Version**:                3
    **Change:**
    *Add documentation header*

    **Change Date:**            *20200324*
    **Author:**                 *Wilson, Don < dwilson@newks.com >*
    **Version**:                2
    **Change:**
    *Add the OLO Vendor ID as a field following POS StoreID and Store Name*

-------------------
**/
BEGIN
    declare
    -- If this is for a table build, then Tab, if not, then Proc
    @RunType varchar(4) = 'Proc'
    -- The time the procedure begins running
    ,@StartTime datetime = getdate()
    -- The database the procedure is running in
    ,@DBName varchar(150) = DB_NAME()
    -- The name of the procedure itself
    ,@ProcName varchar(150) = OBJECT_NAME(@@PROCID)
    -- Default the error information to no error
    ,@ErrorNumber int = 0
    ,@ErrorMessage varchar(250) = ''
    ,@ErrorLine int = 0

    BEGIN TRY
        -- if this is a table build, perform it as a transaction
        if (@RunType = 'Tab') begin transaction;

        -- SET NOCOUNT ON added to prevent extra result sets from
        -- interfering with SELECT statements.
        SET NOCOUNT ON;

        SELECT *
        INTO #storesincluded
        FROM dev_aloha.dbo.get_storesincluded (@StoreGrouping , @StoreGroup, convert(date,getdate()-1))

        select
            convert(varchar,s.storeid) as 'storeid',
            s.storename,
            convert(varchar(15),'') 'oloId',
            convert(varchar(100),'') as 'ToastGUID',
            s.StoreStatus,
            CASE
                WHEN si.cofz = 1 THEN 'Company'
                ELSE 'Franchise'
            end as 'Ownership',
            CASE
                WHEN si.cofz = 1 THEN 'Newco Dining LLC'
                ELSE si.companyname
            end as 'Group Name',
            CASE
                WHEN s.StoreAdd2 IS NULL AND s.StoreAdd3 IS NULL THEN s.StoreAdd1
                WHEN s.storeadd3 IS NULL AND s.storeadd2 IS NOT NULL THEN s.storeadd1 + ' ' + s.StoreAdd2
                ELSE s.storeadd1 +' ' + s.StoreAdd2 + '' + s.StoreAdd3
            END AS Address,
            s.StoreCity,
            s.StoreState,
            s.StoreZip,
            isnull(contacts.dbo.fnFormatPhoneNumber(s.storephone), '') AS Phone,
            s.StoreEmail,
            convert(varchar(100),'') primarycontactname,
            convert(varchar(100),'') primarycontactemail,
            convert(varchar(100),'') primarycontactphone,
            convert(varchar(100),'') areadirname,
            convert(varchar(100),'') areadiremail,
            convert(varchar(100),'') BillingName,
            convert(varchar(100),'') BillingEmail,
            convert(varchar(100),'') GeneralManager,
            convert(varchar(200),'') GM_Email,
            convert(char(12),'') GM_Cell_Phone,
            convert(varchar(100),'') BillingPhone,
            convert(varchar(100),'') as SyscoMarket,
            convert(varchar(100),'') as DMA
        into #Results
        from contacts.dbo.store s
        join #StoresIncluded si
        on s.storeid = si.storeid

        update #Results set
            PrimaryContactName = pc.PrimaryName,
            PrimaryContactEmail = pc.PrimaryEmail,
            PrimaryContactPhone = isnull(contacts.dbo.fnFormatPhoneNumber(pc.PrimaryPhone), '')
        from #Results r
        join contacts.dbo.store s
        on convert(varchar,r.storeid) = convert(varchar,s.storeid)
        join contacts.dbo.PrimaryContacts pc
        on s.StorePrimaryContact = pc.PrimaryID

        update #Results set
            AreaDirName = ad.AreaDirName,
            AreaDirEmail = ad.AreaDirEmail
        from #Results r
        join contacts.dbo.Store s
        on convert(varchar,r.storeid) = convert(varchar,s.storeid)
        join contacts.dbo.AreaDir ad
        on s.StoreAreaDirID = ad.areadirid

        update #Results set
            OLOID = v.ID
        from #Results r
        join olo.dbo.oloVendors v
        on convert(varchar,r.storeid) = convert(varchar,v.extref)

        update #Results set
            BillingName = b.billingname,
            BillingEmail = b.billingemail,
            BillingPhone = dbo.fnFormatPhoneNumber(b.BillingPhone)
        from #Results r
        join contacts.dbo.store s
        on convert(varchar,r.storeid) = convert(varchar,s.storeid)
        join contacts.dbo.BillingContacts b
        on s.storebillingid = b.billingid

        update #Results set
        GeneralManager = gm.GeneralMgrName,
        GM_Email = gm.EmailAddress,
        GM_Cell_Phone = contacts.dbo.fnFormatPhoneNumber(gm.CellPhone)
        from #Results r
        join contacts.dbo.GeneralManagers gm
        on convert(varchar,r.storeid) = convert(varchar,gm.storeid)

        update #Results set
        ToastGUID = tr.GUID
        from #Results r
        join toast.dbo.restaurants tr
        on convert(varchar,r.storeid) = convert(varchar,tr.storeid)

        update #Results set
        SyscoMarket = sm.SyscoMarket
        from #Results r
        join contacts.dbo.StoreSysco ss
        on r.storeid = ss.storeid
        join contacts.dbo.SyscoMarket sm
        on ss.SyscoID = sm.SyscoID

        update #Results set
        DMA = d.DMAName
        from #Results r
        join contacts.dbo.store s
        on convert(varchar,r.storeid) = convert(varchar,s.storeid)
        join contacts.dbo.DMA d
        on s.StoreDMAID = d.DMAID

        select *
        from #Results
		order by StoreStatus desc, Ownership, StoreID

        DROP TABLE #storesincluded

        -- If the table build has no error, then commit the transaction
        if (@RunType = 'Tab') commit transaction;

        -- Log the successful completion
        exec Logging.dbo.Write_Procedure_Execution
        @RunType = @RunType
        ,@StartTime = @StartTime
        ,@DBName = @DBName
        ,@ProcName = @ProcName;

    END TRY
        BEGIN CATCH
        -- If there are errors and a transaction was started, roll it back
        IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

        -- Record the error details
        set @ErrorNumber  = ERROR_NUMBER();
        set @ErrorLine  = ERROR_LINE();
        set @ErrorMessage  = ERROR_MESSAGE();

        -- Log the error
        exec Logging.dbo.Write_Procedure_Execution
        @RunType = @RunType
        ,@StartTime = @StartTime
        ,@DBName = @DBName
        ,@ProcName = @ProcName
        ,@ErrorNumber = @ErrorNumber
        ,@ErrorMessage = @ErrorMessage
        ,@ErrorLine = @ErrorLine;
        THROW;
    END CATCH
END
GO

-- ============================================================
-- SECTION 2 — smoke test (same params the report uses; 9/243 =
-- the all-stores grouping used elsewhere; adjust if the report
-- passes something else)
-- Expect: no posKey column, DMA as the last column with names
-- ============================================================

EXEC contacts.dbo.sp_rpt_DSP_Restaurant_Location_Coverage_Check_Report
    @StoreGrouping = 9,
    @StoreGroup    = '243';
GO
