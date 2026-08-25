CREATE PROCEDURE [dbo].[sp_rpt_Company_Payroll_Export_TOAST]
-- Add the parameters for the stored procedure here
	(
		@PayPeriodStart date,
		@PayPeriodEnd date,
		@StoreGrouping int = 9,
		@StoreGroup varchar(1500) = 244,
        @OutputType int = 1 -->>>>>> 1 = File Share;  2 = Email
	)
AS
/**
## Procedure Name       *[dev_aloha].[dbo].[sp_rpt_Company_Payroll_Export_TOAST]*  
**Procedure Type**      *stored procedure*  
**Author**              Wilson, Don < dwilson@newks.com >  
**Version**             1  
**Created**             20200122  
**Report Name**         *Company Store Payroll Export*  
**Summary**  
*This an internal version of the Aloha Enterprise ADP Payforce Payroll Export V2, with the company's Tip Share added.  
This version runs for the Corporate stores on the TOAST POS*  
  
### Parameters  
```sql  
PayPeriodEnd date           Start date of the range  
StoreGrouping int           The grouping type of stores  
StoreGroup varchar(1500)    The store / store group / dma / etc to run for  
OutputType bit              Whether this run is for emailing (verification) or ftping (sending on to payroll processor)  
```  
  
### Output   
*SDate -- Start of the Pay Period this export is for  
EDate -- End of the Pay Period this export is for  
CoCode -- The Payroll Company Code as defined in Aloha Enterprise Company Setup  
BatchID -- The Batch ID as defined in Aloha Enterprise Site Setup  
File# -- The Export ID for the eployee as defined in CFC  
BatchDescription -- The Batch Description as defined in Aloha Enterprise Site Setup
RegHours -- The total of regular hours polled for this employee  
OTHours -- The total of over time hours polled for this employee  
Earnings3Code -- This label is defined in Aloha Enterprise Company Setup  
Earnings3Amount -- The sum of tips earned for this employee; See above for how this calculates  
TempDept -- The job code this row for this employee is for  
Rate -- The pay rate for this employee for this job code*  
  
### Change History  
**Change Date:**            *YYYYMMDD*  
**Author:**                 *Last, First < email address >*  
**Version**:                ##  
**Change:**  
*detail change here*  
  
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

        declare @SDate date = convert(date,@PayPeriodStart)
        declare @EDate date = convert(date,@PayPeriodEnd)

        select *
        into #StoresIncluded
        from dev_aloha.dbo.get_StoresIncluded (@StoreGrouping, @StoreGroup, @EDate)

        create table #HoursTips
        (
            StoreID int,
            TotalHours float,
            TotalTips float,
            TipsPerHour float
        )

        insert into #HoursTips (StoreID, TotalHours)
        select
            r.StoreID,
            sum(hs.RegularHours + hs.OvertimeHours)
        from #StoresIncluded si
        join toast.dbo.restaurants r
        on si.storeid = r.StoreID
        join toast.dbo.hstShift hs
        on r.GUID = hs.Store
        join toast.dbo.JobCodes jc
        on hs.JobCode = jc.GUID
        where DateOfBusiness between @SDate and @EDate
        and WageFrequency != 'salary'
        group by r.StoreID

        select
            r.storeid,
            sum(p.tipamount) Tips
        into #TipsPerDay
        from toast.dbo.hstPayment p
        join toast.dbo.restaurants r
        on p.storeid = r.guid
        join #StoresIncluded si
        on r.storeid = si.storeid
        where DateOfBusiness between @SDate and @EDate
        and p.PaymentType not in ('cash')
        and p.PaymentStatus in ('CAPTURED','AUTHORIZED')
        group by r.storeid

        merge #HoursTips r
        using #TipsPerDay t
        on r.StoreID = t.StoreID
        when matched then update
            set TotalTips = t.Tips
        when not matched by target then
            insert (StoreID, TotalTips)
            values (t.StoreID, t.Tips);

        update #HoursTips
        set TipsPerHour = TotalTips / TotalHours

        select
            cs.ADPCompanyCode,
            gs.ADPBatchID,
            gs.ADPBatchDescription,
            e.First 'FirstName',
            e.Last 'LastName',
            e.ExternalEmployeeId 'SecurityNum',
            jcm.ExportID as 'TempDept',
            sum(hs.regularhours) RegularHours,
            sum(hs.overtimehours) OTHours,
            hs.HourlyWage 'Rate',
            sum(ht.TipsPerHour) TipsPerHour,
            sum(convert(decimal(12,2),(hs.RegularHours + hs.OvertimeHOurs) * ht.TipsPerHour)) EmployeeTips
        into #ShiftTemp
        from toast.dbo.hstshift hs
        join toast.dbo.employees e
        on hs.Employee = e.GUID
        and hs.Store = e.StoreGUID
        join toast.dbo.restaurants r
        on e.StoreGUID = r.GUID
        join #StoresIncluded si
        on si.StoreID = r.StoreID
        join #HoursTips ht
        on r.StoreID = ht.StoreID
        join dev_aloha.dbo.gblstore gs
        on ht.StoreID = gs.StoreId
        join toast.dbo.JobCodes jc
        on hs.JobCode = jc.GUID
        join toast.dbo.JobCodeToastToAlohaMap jcm
        on jc.code = jcm.ToastJC
        join contacts.dbo.companysetup cs
        on 1 = 1
        where hs.dateofbusiness between  @SDate and @EDate
        and jc.WageFrequency != 'salary'
        and hs.Deleted =0
        group by cs.ADPCompanyCode, gs.ADPBatchID, gs.ADPBatchDescription, e.First, e.Last, e.ExternalEmployeeId, jcm.ExportID, hs.HourlyWage

        select
            adpcompanycode, adpbatchid, ADPBatchDescription, FirstName, LastName, SecurityNum, TempDept, sum(RegularHours) RegularHours, sum(OTHours) OTHours, Rate, sum(EmployeeTips) EmployeeTips
        into #TempShift2
        from #ShiftTemp
        group by adpcompanycode, adpbatchid, ADPBatchDescription, FirstName, LastName, SecurityNum, TempDept, Rate
        order by adpcompanycode, adpbatchid, ADPBatchDescription, FirstName, LastName, SecurityNum, TempDept, Rate
                
        if (@OutputType = 2)
            begin
                select
                    @SDate 'PayStart',
                    @EDate 'PayEnd',
                    ADPCompanyCode [CoCode],
                    ADPBatchID [BatchID],
                    SecurityNum [File#],
                    ADPBatchDescription [BatchDescription],
                    sum(RegularHours) [RegHours],
                    sum(othours) [OTHours],
                    'tip01' 'Earnings3Code',
                    sum(employeeTips) [Earnings3Amount],
                    TempDept,
                    Rate 'TempRate'
                from #TempShift2
                where TempDept != 'NOREPORT'
                group by ADPCompanyCode, ADPBatchID, SecurityNum, FirstName, LastName, ADPBatchDescription, TempDept, Rate
                order by ADPBatchID, SecurityNum, FirstName, LastName, TempDept
                
            end
        else if (@OutputType = 1)
            begin
                (select
                    '1' [Sort],
                    convert(varchar,'Co Code') CoCode,
                    convert(varchar,'Batch ID') BatchID,
                    convert(varchar,'File #') [File#],
                    convert(varchar,'Batch Description') BatchDescription,
                    convert(varchar,'Reg Hours') RegHours,
                    convert(varchar,'OT Hours') OTHours,
                    convert(varchar,'Earnings 3 Code') Earnings3Code,
                    convert(varchar,'Earnings 3 Amount') Earnings3Amount,
                    convert(varchar,'Temp Dept') TempDept,
                    convert(varchar,'Temp Rate') TempRate
                    
                union all 

                select
                    '2' [Sort],
                    convert(varchar,ADPCompanyCode) [CoCode],
                    convert(varchar,ADPBatchID) [BatchID],
                    convert(varchar,SecurityNum) [File#],
                    convert(varchar,ADPBatchDescription) [BatchDescription],
                    convert(varchar,sum(RegularHours)) [RegHours],
                    convert(varchar,sum(othours)) [OTHours],
                    'tip01' 'Earnings3Code',
                    convert(varchar,sum(employeeTips)) [Earnings3Amount],
                    convert(varchar,TempDept) TempDept,
                    convert(varchar,Rate) 'TempRate'
                from #TempShift2
                where TempDept != 'NOREPORT'
                group by ADPCompanyCode, ADPBatchID, SecurityNum, ADPBatchDescription, TempDept, Rate)
                order by [Sort], [BatchID], [File#], TempDept
            end

        drop table #Hourstips
        drop table #StoresIncluded
        drop table #TipsPerDay
        drop table #TempShift2
        drop table #ShiftTemp
        
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