-- =====================================================================
-- Payroll ADP export — 6 employees missing/blank for Flowood (1003)
-- Pay period 2026-06-01 .. 2026-06-14 (pay date 6/19/26)
--
-- Symptom: ADP export (sp_rpt_Company_Payroll_Export_TOAST) is short
-- ~126 hrs vs Toast. The 43 included employees match Toast to the penny,
-- so it's not a date-range issue — it's 6 specific employees:
--   ABSENT:  Horton (9104069), Hunt (9104067), Phillips (9102633),
--            Salas (9104105), Stucky (9098531)
--   BLANK File#: Nichols, Amiaya (9103941)
--
-- The export's #ShiftTemp join chain is the suspect:
--   join employees e on hs.Employee=e.GUID AND hs.Store=e.StoreGUID  (INNER)
--   join JobCodeToastToAlohaMap jcm on jc.code=jcm.ToastJC           (INNER)
--   File# = e.ExternalEmployeeId ;  filter TempDept != 'NOREPORT'
--
-- This script reproduces that chain with LEFT JOINs so we can see WHICH
-- link drops each employee. READ-ONLY.
-- =====================================================================

DECLARE @SDate date = '2026-06-01', @EDate date = '2026-06-14';

-- Flowood's Toast restaurant GUID
DECLARE @FlowoodGUID varchar(50) =
    (SELECT GUID FROM toast.dbo.restaurants WHERE StoreID = 1003);
SELECT @FlowoodGUID AS FlowoodGUID;

-- ============================================================
-- §1  Per-employee diagnosis: every employee with Flowood shifts
--     in the period, LEFT-joined down the export chain so the
--     failing link shows as NULL.
-- ============================================================
SELECT
    e.Last, e.First,
    hs.Employee                         AS shift_employee_guid,
    e.GUID                              AS emp_record_guid,     -- NULL = no employees row matched
    e.ExternalEmployeeId               AS file_num,            -- NULL/'' = blank File# (Nichols case)
    e.StoreGUID                        AS emp_store_guid,
    CASE WHEN hs.Store = e.StoreGUID THEN 'match' ELSE 'MISMATCH' END AS store_match,
    SUM(hs.RegularHours + hs.OvertimeHours) AS hours,
    COUNT(DISTINCT jc.code)            AS distinct_jobcodes,
    COUNT(DISTINCT CASE WHEN jcm.ToastJC IS NULL THEN jc.code END) AS unmapped_jobcodes,
    COUNT(DISTINCT CASE WHEN jcm.ExportID = 'NOREPORT' THEN jc.code END) AS noreport_jobcodes
FROM toast.dbo.hstShift hs
LEFT JOIN toast.dbo.employees e
       ON hs.Employee = e.GUID AND hs.Store = e.StoreGUID
LEFT JOIN toast.dbo.JobCodes jc
       ON hs.JobCode = jc.GUID
LEFT JOIN toast.dbo.JobCodeToastToAlohaMap jcm
       ON jc.code = jcm.ToastJC
WHERE hs.Store = @FlowoodGUID
  AND hs.DateOfBusiness BETWEEN @SDate AND @EDate
  AND hs.Deleted = 0
  AND ISNULL(jc.WageFrequency,'') != 'salary'
GROUP BY e.Last, e.First, hs.Employee, e.GUID, e.ExternalEmployeeId,
         e.StoreGUID, CASE WHEN hs.Store = e.StoreGUID THEN 'match' ELSE 'MISMATCH' END
ORDER BY (CASE WHEN e.GUID IS NULL THEN 0
               WHEN e.ExternalEmployeeId IS NULL OR e.ExternalEmployeeId = '' THEN 1
               ELSE 2 END), e.Last;

-- ============================================================
-- §2  Direct look at the 6 in the employee master, by name.
--     Shows whether the record exists at all and what its
--     ExternalEmployeeId / StoreGUID are. (Employees who work
--     multiple stores can have a record whose StoreGUID isn't
--     Flowood — that breaks the hs.Store = e.StoreGUID join.)
-- ============================================================
SELECT GUID, First, Last, ExternalEmployeeId, StoreGUID
FROM toast.dbo.employees
WHERE Last IN ('Horton','Hunt','Phillips','Salas','Stucky','Nichols')
ORDER BY Last, First;

-- ============================================================
-- §3  Do these 6 have shifts under a DIFFERENT StoreGUID than
--     their employee record? (Catches the transfer / multi-store
--     setup that fails hs.Store = e.StoreGUID.) Compares each
--     employee's shift-store vs their master-record store.
-- ============================================================
SELECT DISTINCT
    e.Last, e.First, e.ExternalEmployeeId,
    e.StoreGUID            AS master_store,
    hs.Store               AS shift_store,
    rr.StoreID             AS shift_store_num
FROM toast.dbo.employees e
JOIN toast.dbo.hstShift hs ON hs.Employee = e.GUID
LEFT JOIN toast.dbo.restaurants rr ON hs.Store = rr.GUID
WHERE e.Last IN ('Horton','Hunt','Phillips','Salas','Stucky','Nichols')
  AND hs.DateOfBusiness BETWEEN @SDate AND @EDate
  AND hs.Deleted = 0
ORDER BY e.Last, e.First;
