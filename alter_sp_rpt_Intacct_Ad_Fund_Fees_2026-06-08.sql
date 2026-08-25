/*
================================================================================
ALTER sp_rpt_Intacct_Ad_Fund_Fees
================================================================================
Purpose
    Add 12 stores to the bank-1002 list. Original "1000–1019 / 1002–1019"
    request from accounting (Ron) on 2026-06-08 — the bank account that
    drafts Ad Fund Fees changed for these stores from 1000 to 1002.

Stores added to bank 1002 (originally on bank 1000):
    1019, 1023, 1034, 1037, 1051, 1056, 1061, 1075, 1104, 1118, 1130, 1176

Stores already on bank 1002 (unchanged, kept in the IN list):
    1054, 1148

How to apply
    1. Open SSMS, connect to sql-prod
    2. Switch context to the dev_aloha database
    3. Paste this entire script and hit F5
    4. Verify by re-running the report for any week that includes one of
       the listed stores and confirm the credit-line ACCT_NO shows 1002-XXXX

Author / Date: Kim Aylesworth / 2026-06-08
================================================================================
*/

USE [dev_aloha]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[sp_rpt_Intacct_Ad_Fund_Fees]
    (
        @StartDate date = '20230522',
        @EndDate date = '20230528',
        @StoreGrouping int = 9,
        @StoreGroup varchar(1500) = '79'
    )
AS
/**
## Procedure Name       *[dev_aloha].[dbo].[sp_rpt_Intacct_Ad_Fund_Fees]*
**Procedure Type**      *stored procedure*
**Author**              Wilson, Don < dwilson@newks.com >
**Version**             2
**Created**             20230531

### Change History
**Change Date:**        20260608
**Author:**             Aylesworth, Kim < kaylesworth@newks.com >
**Version**:            2
**Change:**
Added 12 stores to the bank-1002 list per accounting request — bank
account change for ad-fund draft (was 1000, now 1002):
1019, 1023, 1034, 1037, 1051, 1056, 1061, 1075, 1104, 1118, 1130, 1176.
Existing 1002 stores (1054, 1148) unchanged.
 **/
BEGIN
    SET NOCOUNT ON;

    declare
         @RunType varchar(4) = 'Proc'
        ,@StartTime datetime = getdate()
        ,@DBName varchar(150) = DB_NAME()
        ,@ProcName varchar(150) = OBJECT_NAME(@@PROCID)
        ,@ErrorNumber int = 0
        ,@ErrorMessage varchar(250) = ''
        ,@ErrorLine int = 0

    BEGIN TRY
        if (@RunType = 'Tab') begin transaction;

        DECLARE @SDate date
        DECLARE @EDate date

        SET @SDate =
            CASE
                WHEN @StartDate IS NULL THEN convert(date,getdate()-7)
                ELSE @StartDate
            END

        SET @EDate =
            CASE
                WHEN @EndDate IS NULL THEN convert(date,getdate()-1)
                ELSE @EndDate
            END

        select *
        into #StoresIncluded
        from dev_aloha.dbo.get_StoresIncluded (@StoreGrouping, @StoreGroup, @EDate)

        create table #Results
        (
            Sort int,
            [0] varchar(100),
            LINE_NO varchar(100),
            [DATE] varchar(100),
            [DESCRIPTION] varchar(100),
            LOCATION_ID varchar(100),
            ACCT_NO varchar(15),
            DEBIT varchar(100),
            CREDIT varchar(100),
            DEPT_ID varchar(100),
            MEMO varchar(100),
            JOURNAL varchar(100),
            REVERSEDATE varchar(100),
            REFERENCE_NO varchar(100),
            DOCUMENT varchar(100),
            SOURCEENTITY varchar(100),
            CURRENCY varchar(100),
            EXCH_RATE_DATE varchar(100),
            EXCH_RATE_TYPE_ID varchar(100),
            EXCHANGE_RATE varchar(100),
            STATE varchar(100),
            ALLOCATION_ID varchar(100),
            GLENTRY_CUSTOMERID varchar(100),
            GLENTRY_VENDORID varchar(100)
        )

        create table #Final
        (
            Sort int,
            [0] varchar(100),
            LINE_NO varchar(100),
            [DATE] varchar(100),
            [DESCRIPTION] varchar(100),
            LOCATION_ID varchar(100),
            ACCT_NO varchar(15),
            DEBIT varchar(100),
            CREDIT varchar(100),
            DEPT_ID varchar(100),
            MEMO varchar(100),
            JOURNAL varchar(100),
            REVERSEDATE varchar(100),
            REFERENCE_NO varchar(100),
            DOCUMENT varchar(100),
            SOURCEENTITY varchar(100),
            CURRENCY varchar(100),
            EXCH_RATE_DATE varchar(100),
            EXCH_RATE_TYPE_ID varchar(100),
            EXCHANGE_RATE varchar(100),
            STATE varchar(100),
            ALLOCATION_ID varchar(100),
            GLENTRY_CUSTOMERID varchar(100),
            GLENTRY_VENDORID varchar(100)
        )

        insert into #Final
        select '1', '0', 'LINE_NO', 'DATE', 'DESCRIPTION', 'LOCATION_ID', 'ACCT_NO', 'DEBIT', 'CREDIT', 'DEPT_ID', 'MEMO', 'JOURNAL', 'REVERSEDATE', 'REFERENCE_NO', 'DOCUMENT', 'SOURCEENTITY', 'CURRENCY', 'EXCH_RATE_DATE', 'EXCH_RATE_TYPE_ID', 'EXCHANGE_RATE', 'STATE', 'ALLOCATION_ID', 'GLENTRY_CUSTOMERID', 'GLENTRY_VENDORID'

        insert into #Results
        select
            2,
            '',
            '',
            @EDate,
            'Ad Fund Fees ' + format (@EDate, 'MM.dd.yy'),
            si.StoreID,
            '8235' ,
            convert(decimal(12,2),sum(r.MarketingAdFund)),
            '',
            '',
            'Ad Fund Fees ' + format (@EDate, 'MM.dd.yy'),
            'CDJ',
            '',
            '',
            '',
            'NEW',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            ''
        from dev_aloha.dbo.Royalty r
        join #StoresIncluded si
        on r.StoreID = si.StoreID
        where r.DateOfbusiness between @SDate and @EDate
        group by si.StoreID

        insert into #Results
        select
            3,
            '',
            '',
            @EDate,
            'Ad Fund Fees ' + format (@EDate, 'MM.dd.yy'),
            'NEW',
            -- 2026-06-08 (Kim): added 1019, 1023, 1034, 1037, 1051, 1056,
            -- 1061, 1075, 1104, 1118, 1130, 1176 to the bank-1002 list per
            -- accounting request (was 1000, now 1002). Sorted ascending so
            -- adding more later stays readable.
            case
                when si.StoreID in (
                    1019, 1023, 1034, 1037, 1051, 1054, 1056, 1061,
                    1075, 1104, 1118, 1130, 1148, 1176
                ) then '1002-' + CONVERT(char(4),si.StoreID)
                else '1000-' + CONVERT(char(4),si.StoreID)
            end,
            '',
            convert(decimal(12,2),sum(r.MarketingAdFund)),
            '',
            'Ad Fund Fees ' + format (@EDate, 'MM.dd.yy'),
            'CDJ',
            '',
            '',
            '',
            'NEW',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            ''
        from dev_aloha.dbo.Royalty r
        join #StoresIncluded si
        on r.StoreID = si.StoreID
        where r.DateOfbusiness between @SDate and @EDate
        group by si.StoreID

        insert into #Final
        select
            Sort,
            [0],
            ROW_NUMBER() OVER (order by Sort, [DATE], ACCT_NO, location_id) AS LINE_NO,
            DATE,
            DESCRIPTION,
            LOCATION_ID,
            ACCT_NO,
            DEBIT,
            CREDIT,
            DEPT_ID,
            MEMO,
            JOURNAL,
            REVERSEDATE,
            REFERENCE_NO,
            DOCUMENT,
            SOURCEENTITY,
            CURRENCY,
            EXCH_RATE_DATE,
            EXCH_RATE_TYPE_ID,
            EXCHANGE_RATE,
            STATE,
            ALLOCATION_ID,
            GLENTRY_CUSTOMERID,
            GLENTRY_VENDORID
        from #Results

        select *
        from #Final
        order by Sort, [DATE], ACCT_NO, location_id

        drop table #StoresIncluded
        drop table #Results

        if (@RunType = 'Tab') commit transaction;

        exec Logging.dbo.Write_Procedure_Execution
             @RunType = @RunType
            ,@StartTime = @StartTime
            ,@DBName = @DBName
            ,@ProcName = @ProcName;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        set @ErrorNumber  = ERROR_NUMBER();
        set @ErrorLine    = ERROR_LINE();
        set @ErrorMessage = ERROR_MESSAGE();

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
