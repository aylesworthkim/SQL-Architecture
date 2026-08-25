/* =====================================================================
   Company Store Payroll Export - Toast   |   SOURCE-DATA EXTRACT
   ---------------------------------------------------------------------
   Reproduces dev_aloha.dbo.sp_rpt_Company_Payroll_Export_TOAST and
   exposes every intermediate layer, so the logic can be ported to
   Snowflake / Power BI and validated row-for-row against the SSRS xlsx.

   Read-only. Returns 7 result sets (save each grid as its own CSV):
     1  export_rows              - the 10 report columns (final output)
     2  employee_jobcode_detail  - one row per employee x jobcode x rate
     3  store_tip_pool           - the tip-share math, per store
     4  dim_store_adp            - store -> Batch ID / Batch Description
     5  dim_jobcode_map          - Toast job code -> Temp Dept
     6  dim_company_setup_adp    - Co Code + ADP earnings codes
     7  excluded_employees       - hours that DROP or export with blank File #

   Parameters below mirror the 2026-08-20 SSRS run of the report
   (PayPeriodStart=8/3/2026, PayPeriodEnd=8/16/2026, StoreGrouping=2,
   StoreGroup=0 -> all 102 stores).
   ===================================================================== */

SET NOCOUNT ON;

DECLARE @SDate         date          = '2026-08-03';
DECLARE @EDate         date          = '2026-08-16';
DECLARE @StoreGrouping int           = 2;      -- 2/'0' = all stores; 9/'79' = company; 9/'244' = corporate Toast
DECLARE @StoreGroup    varchar(1500) = '0';

IF OBJECT_ID('tempdb..#si')         IS NOT NULL DROP TABLE #si;
IF OBJECT_ID('tempdb..#HoursTips')  IS NOT NULL DROP TABLE #HoursTips;
IF OBJECT_ID('tempdb..#TipsPerDay') IS NOT NULL DROP TABLE #TipsPerDay;
IF OBJECT_ID('tempdb..#detail')     IS NOT NULL DROP TABLE #detail;

SELECT * INTO #si
FROM dev_aloha.dbo.get_StoresIncluded(@StoreGrouping, @StoreGroup, @EDate);

/* ---- store denominator: all non-salary hours in the period -----------
   NOTE (matches the proc, warts and all): there is no hs.Deleted = 0
   filter here, and WageFrequency <> 'salary' silently drops rows whose
   WageFrequency is NULL. */
CREATE TABLE #HoursTips (StoreID int, TotalHours float, TotalTips float, TipsPerHour float);

INSERT INTO #HoursTips (StoreID, TotalHours)
SELECT r.StoreID, SUM(hs.RegularHours + hs.OvertimeHOurs)
FROM #si si
JOIN toast.dbo.restaurants r  ON si.StoreID  = r.StoreID
JOIN toast.dbo.hstShift    hs ON r.GUID      = hs.Store
JOIN toast.dbo.JobCodes    jc ON hs.JobCode  = jc.GUID
WHERE hs.DateOfBusiness BETWEEN @SDate AND @EDate
  AND jc.WageFrequency <> 'salary'
GROUP BY r.StoreID;

/* ---- store numerator: non-cash tips actually captured ---------------- */
SELECT r.StoreID, SUM(p.TipAmount) AS Tips
INTO #TipsPerDay
FROM toast.dbo.hstPayment p
JOIN toast.dbo.restaurants r ON p.StoreID = r.GUID   -- hstPayment.StoreID holds the restaurant GUID
JOIN #si si                  ON r.StoreID = si.StoreID
WHERE p.DateOfBusiness BETWEEN @SDate AND @EDate
  AND p.PaymentType   NOT IN ('cash')
  AND p.PaymentStatus     IN ('CAPTURED','AUTHORIZED')
GROUP BY r.StoreID;

MERGE #HoursTips r
USING #TipsPerDay t ON r.StoreID = t.StoreID
WHEN MATCHED THEN UPDATE SET TotalTips = t.Tips
WHEN NOT MATCHED BY TARGET THEN INSERT (StoreID, TotalTips) VALUES (t.StoreID, t.Tips);

UPDATE #HoursTips SET TipsPerHour = TotalTips / TotalHours;

/* ---- employee x jobcode x rate grain (the grain the export is built on) */
SELECT
    r.StoreID,
    gs.Name                                   AS StoreName,
    cs.ADPCompanyCode                         AS CoCode,
    gs.ADPBatchID                             AS BatchID,
    gs.ADPBatchDescription                    AS BatchDescription,
    e.ExternalEmployeeId                      AS FileNum,
    e.First                                   AS FirstName,
    e.Last                                    AS LastName,
    hs.Employee                               AS EmployeeGUID,
    jc.Code                                   AS ToastJobCode,
    jc.Title                                  AS ToastJobTitle,
    jcm.ExportID                              AS TempDept,
    hs.HourlyWage                             AS TempRate,
    SUM(hs.RegularHours)                      AS RegHours,
    SUM(hs.OvertimeHOurs)                     AS OTHours,
    MAX(ht.TipsPerHour)                       AS StoreTipsPerHour,
    SUM(CONVERT(decimal(12,2),(hs.RegularHours + hs.OvertimeHOurs) * ht.TipsPerHour)) AS Earnings3Amount
INTO #detail
FROM toast.dbo.hstShift hs
JOIN toast.dbo.employees   e   ON hs.Employee = e.GUID
                              AND hs.Store    = e.StoreGUID   -- INNER JOIN: see result set 7
JOIN toast.dbo.restaurants r   ON e.StoreGUID = r.GUID
JOIN #si si                    ON si.StoreID  = r.StoreID
JOIN #HoursTips ht             ON r.StoreID   = ht.StoreID
JOIN dev_aloha.dbo.gblstore gs ON ht.StoreID  = gs.StoreId
JOIN toast.dbo.JobCodes jc     ON hs.JobCode  = jc.GUID
JOIN toast.dbo.JobCodeToastToAlohaMap jcm ON jc.Code = jcm.ToastJC
CROSS JOIN contacts.dbo.companysetup cs
WHERE hs.DateOfBusiness BETWEEN @SDate AND @EDate
  AND jc.WageFrequency <> 'salary'
  AND hs.Deleted = 0
GROUP BY r.StoreID, gs.Name, cs.ADPCompanyCode, gs.ADPBatchID, gs.ADPBatchDescription,
         e.ExternalEmployeeId, e.First, e.Last, hs.Employee, jc.Code, jc.Title,
         jcm.ExportID, hs.HourlyWage;

/* =====================  1  export_rows  ============================== */
SELECT
    @SDate                       AS PayStart,
    @EDate                       AS PayEnd,
    CoCode                       AS [Co Code],
    BatchID                      AS [Batch ID],
    FileNum                      AS [File #],
    BatchDescription             AS [Batch Description],
    SUM(RegHours)                AS [Reg Hours],
    SUM(OTHours)                 AS [OT Hours],
    'tip01'                      AS [Earnings 3 Code],
    SUM(Earnings3Amount)         AS [Earnings 3 Amount],
    TempDept                     AS [Temp Dept],
    TempRate                     AS [Temp Rate]
FROM #detail
WHERE TempDept <> 'NOREPORT'
GROUP BY CoCode, BatchID, FileNum, BatchDescription, TempDept, TempRate
ORDER BY BatchID, FileNum, TempDept;

/* =====================  2  employee_jobcode_detail  ================== */
SELECT * FROM #detail ORDER BY StoreID, LastName, FirstName, TempDept, TempRate;

/* =====================  3  store_tip_pool  =========================== */
SELECT ht.StoreID, gs.Name AS StoreName, gs.ADPBatchID, gs.ADPBatchDescription,
       ht.TotalHours, ht.TotalTips, ht.TipsPerHour
FROM #HoursTips ht
LEFT JOIN dev_aloha.dbo.gblstore gs ON ht.StoreID = gs.StoreId
ORDER BY ht.StoreID;

/* =====================  4  dim_store_adp  ============================ */
SELECT gs.StoreId, gs.Name AS StoreName, gs.ShortStoreName, gs.ADPBatchID,
       gs.ADPBatchDescription, gs.ADPCompanyCode AS Store_ADPCompanyCode_UNUSED,
       gs.DeleteStore, CASE WHEN si.StoreID IS NULL THEN 0 ELSE 1 END AS InThisRun
FROM dev_aloha.dbo.gblstore gs
LEFT JOIN #si si ON si.StoreID = gs.StoreId
ORDER BY gs.StoreId;

/* =====================  5  dim_jobcode_map  ========================== */
SELECT jcm.ToastJC, jcm.JobCode AS ToastJobName, jcm.TrimmedJC, jcm.ExportID AS TempDept,
       COUNT(jc.GUID) AS JobCodeRowsInToast,
       MAX(jc.WageFrequency) AS SampleWageFrequency
FROM toast.dbo.JobCodeToastToAlohaMap jcm
LEFT JOIN toast.dbo.JobCodes jc ON jc.Code = jcm.ToastJC
GROUP BY jcm.ToastJC, jcm.JobCode, jcm.TrimmedJC, jcm.ExportID
ORDER BY jcm.ExportID;

/* =====================  6  dim_company_setup_adp  ==================== */
SELECT CompanyName, ADPCompanyCode AS CoCode, ADPTippedEarningsCode,
       ADPRegHoursEarningCode, ADPOTHoursEarningCode, ADPCreditCardTipCode,
       ADPIncludeCreditCardTipsInExport, ADPIncludeTempDepartmentInExport,
       ADPIncludePayRateInExport, PayPeriod, PayrollStartDate
FROM contacts.dbo.companysetup;

/* =====================  7  excluded_employees  ======================= */
SELECT
    r.StoreID,
    hs.Employee                             AS EmployeeGUID,
    e.First                                 AS FirstName,
    e.Last                                  AS LastName,
    e.ExternalEmployeeId                    AS FileNum,
    SUM(hs.RegularHours + hs.OvertimeHOurs) AS Hours,
    CASE WHEN e.GUID IS NULL
         THEN 'DROPPED - no toast.dbo.employees row for (Employee GUID + Store)'
         ELSE 'BLANK FILE # - ExternalEmployeeId not set in Toast' END AS Issue
FROM toast.dbo.hstShift hs
JOIN toast.dbo.restaurants r ON hs.Store    = r.GUID
JOIN #si si                  ON si.StoreID  = r.StoreID
JOIN toast.dbo.JobCodes jc   ON hs.JobCode  = jc.GUID
LEFT JOIN toast.dbo.employees e ON hs.Employee = e.GUID AND hs.Store = e.StoreGUID
WHERE hs.DateOfBusiness BETWEEN @SDate AND @EDate
  AND hs.Deleted = 0
  AND jc.WageFrequency <> 'salary'
  AND (e.GUID IS NULL OR ISNULL(e.ExternalEmployeeId,'') = '')
GROUP BY r.StoreID, hs.Employee, e.First, e.Last, e.ExternalEmployeeId, e.GUID
ORDER BY r.StoreID, Issue, Hours DESC;

DROP TABLE #si; DROP TABLE #HoursTips; DROP TABLE #TipsPerDay; DROP TABLE #detail;
