-- =====================================================================
-- LOCATE the employee-master sync that populates toast.dbo.Employees
--
-- The app does NOT write this table; no stored proc writes it either
-- (only an audit trigger fires on writes). So it's filled by an external
-- puller (Don-era API script / SQL Agent job / SSIS). These queries find
-- it and show how stale it is. READ-ONLY.
-- =====================================================================

-- §1  Employees columns — find the freshness timestamp + see if there's
--     an ExternalEmployeeId / store / active flag we can lean on.
SELECT COLUMN_NAME, DATA_TYPE
FROM toast.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Employees'
ORDER BY ORDINAL_POSITION;

-- §2  How fresh is the table? (run after §1 tells you the date column;
--     common names below — uncomment the one that exists)
-- SELECT MAX(LastUpdated)  AS last_write FROM toast.dbo.Employees;
-- SELECT MAX(LastModified) AS last_write FROM toast.dbo.Employees;
-- SELECT MAX(ModifiedDate) AS last_write FROM toast.dbo.Employees;

-- §3  SQL Agent jobs whose STEP COMMAND mentions employees / a pull /
--     the Toast API — the most likely home of the sync.
SELECT j.name AS job_name, j.enabled, s.step_name, s.subsystem,
       LEFT(s.command, 300) AS command_preview
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
WHERE s.command LIKE '%Employee%'
   OR s.command LIKE '%employees%'
   OR s.command LIKE '%toast%employee%'
   OR (s.command LIKE '%employee%' AND (s.command LIKE '%api%' OR s.command LIKE '%pull%' OR s.command LIKE '%sync%' OR s.command LIKE '%import%'))
ORDER BY j.name, s.step_id;

-- §4  Job NAMES that look employee/payroll/Toast-pull related (catches
--     jobs whose step text didn't match §3).
SELECT j.name AS job_name, j.enabled, c.name AS category,
       SUSER_SNAME(j.owner_sid) AS owner, j.date_created, j.date_modified
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.syscategories c ON j.category_id = c.category_id
WHERE j.name LIKE '%mploye%'
   OR j.name LIKE '%payroll%'
   OR j.name LIKE '%toast%'
   OR j.name LIKE '%pull%'
   OR j.name LIKE '%sync%'
   OR j.name LIKE '%API%'
ORDER BY j.enabled DESC, j.name;

-- §5  Last run of any job found above (replace the name, or eyeball the
--     list). Shows whether the sync is even still running on schedule.
-- SELECT TOP 20 j.name, h.run_date, h.run_time, h.run_status,
--        CASE h.run_status WHEN 1 THEN 'Success' WHEN 0 THEN 'Failed'
--             WHEN 2 THEN 'Retry' WHEN 3 THEN 'Canceled' ELSE 'InProgress' END AS status
-- FROM msdb.dbo.sysjobs j
-- JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
-- WHERE j.name LIKE '%<paste job name from §3/§4>%' AND h.step_id = 0
-- ORDER BY h.run_date DESC, h.run_time DESC;

-- §6  When did Employees last actually change, per the audit trigger?
--     (trg_Employees_Identify_Updated_Columns writes to AuditDataChanges.)
--     Tells us the real last-sync moment + which login/process did it.
SELECT TOP 20 *
FROM toast.dbo.AuditDataChanges
WHERE TableName LIKE '%Employee%'
ORDER BY ChangeDate DESC;
