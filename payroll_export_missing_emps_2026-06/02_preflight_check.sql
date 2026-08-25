-- =====================================================================
-- PAYROLL EXPORT PRE-FLIGHT CHECK  (run BEFORE submitting each period)
--
-- Flags every employee with shifts in the pay period who will DROP from
-- or BLANK-OUT in sp_rpt_Company_Payroll_Export_TOAST, chain-wide. Run
-- this, fix the flagged people in Toast, THEN generate/submit the export.
--
-- Reproduces the export's own join logic but with LEFT JOINs so failures
-- surface instead of silently vanishing. READ-ONLY.
--
-- Two failure modes detected:
--   WILL DROP    - shift's (employee GUID + store) has no matching row in
--                  toast.dbo.Employees. Covers brand-new hires (no record)
--                  AND cross-store workers (record exists at their HOME
--                  store, but they worked a shift elsewhere; Toast uses a
--                  per-location employee GUID so the away-store shift GUID
--                  isn't in Employees). Their hours export NOWHERE.
--   BLANK FILE#  - record exists but ExternalEmployeeId (the ADP File #)
--                  is empty -> exports with a blank File #, can't post.
--
-- Adjust @StoreGrouping/@StoreGroup to match how the payroll export is
-- actually run. Defaults mirror the export proc (9 / 244 = corporate
-- Toast stores). Set the dates to the pay period.
-- =====================================================================

DECLARE @SDate date = '2026-06-01';
DECLARE @EDate date = '2026-06-14';
DECLARE @StoreGrouping int = 9;
DECLARE @StoreGroup varchar(1500) = '244';

IF OBJECT_ID('tempdb..#si')    IS NOT NULL DROP TABLE #si;
IF OBJECT_ID('tempdb..#shift') IS NOT NULL DROP TABLE #shift;

SELECT * INTO #si
FROM dev_aloha.dbo.get_StoresIncluded(@StoreGrouping, @StoreGroup, @EDate);

-- qualifying (non-salary, non-deleted) shift hours per store + employee GUID
SELECT
    r.StoreID,
    hs.Store          AS store_guid,
    hs.Employee       AS shift_employee_guid,
    SUM(hs.RegularHours + hs.OvertimeHours) AS hours
INTO #shift
FROM toast.dbo.hstShift hs
JOIN toast.dbo.restaurants r ON hs.Store = r.GUID
JOIN #si si                  ON si.StoreID = r.StoreID
JOIN toast.dbo.JobCodes jc   ON hs.JobCode = jc.GUID
WHERE hs.DateOfBusiness BETWEEN @SDate AND @EDate
  AND hs.Deleted = 0
  AND ISNULL(jc.WageFrequency,'') != 'salary'
GROUP BY r.StoreID, hs.Store, hs.Employee;

-- ============================================================
-- RESULT 1 — SUMMARY: stores with export problems (the alarm)
-- ============================================================
SELECT
    s.StoreID,
    SUM(CASE WHEN e.GUID IS NULL THEN s.hours ELSE 0 END)                                AS hours_will_drop,
    COUNT(CASE WHEN e.GUID IS NULL THEN 1 END)                                           AS emps_will_drop,
    COUNT(CASE WHEN e.GUID IS NOT NULL AND ISNULL(e.ExternalEmployeeId,'')='' THEN 1 END) AS emps_blank_filenum
FROM #shift s
LEFT JOIN toast.dbo.Employees e
       ON s.shift_employee_guid = e.GUID AND s.store_guid = e.StoreGUID
GROUP BY s.StoreID
HAVING SUM(CASE WHEN e.GUID IS NULL THEN s.hours ELSE 0 END) > 0
    OR COUNT(CASE WHEN e.GUID IS NOT NULL AND ISNULL(e.ExternalEmployeeId,'')='' THEN 1 END) > 0
ORDER BY hours_will_drop DESC, emps_blank_filenum DESC;

-- ============================================================
-- RESULT 2 — DETAIL: each employee that will drop / blank out
--   First/Last are NULL for the DROP cases (no record to name
--   them) -> identify that GUID in Toast Web. For BLANK cases the
--   record exists so the name shows.
-- ============================================================
SELECT
    s.StoreID,
    s.shift_employee_guid,
    e.First, e.Last,
    e.ExternalEmployeeId AS file_num,
    s.hours,
    CASE
        WHEN e.GUID IS NULL THEN 'WILL DROP - no employee record at this store (new hire or cross-store worker)'
        ELSE 'BLANK FILE# - set ExternalEmployeeId in Toast'
    END AS export_status
FROM #shift s
LEFT JOIN toast.dbo.Employees e
       ON s.shift_employee_guid = e.GUID AND s.store_guid = e.StoreGUID
WHERE e.GUID IS NULL
   OR ISNULL(e.ExternalEmployeeId,'') = ''
ORDER BY s.StoreID,
         CASE WHEN e.GUID IS NULL THEN 0 ELSE 1 END,
         s.hours DESC;
