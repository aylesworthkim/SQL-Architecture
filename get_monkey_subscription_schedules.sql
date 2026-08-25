/* ===================================================================
   Exact SSRS subscription schedule + recipients for the 4 reports
   moving to the Cloudways app.

   Run on: SQL-PROD  ->  database [ReportServer]   (SSMS, results to grid)
   Read-only. Paste the grid back to Claude.
   =================================================================== */

SELECT
    c.Path                                            AS ReportPath,
    s.Description                                     AS SubDescription,
    s.EventType                                       AS EventType,      -- TimedSubscription / DataDriven
    s.LastStatus                                      AS LastStatus,
    s.LastRunTime                                     AS LastRunTime,

    /* --- recipients / render format (static subs) --- */
    CAST(s.ExtensionSettings AS NVARCHAR(MAX))        AS ExtensionSettings,

    /* --- data-driven recipient query (per-store subs) --- */
    CAST(s.DataSettings AS NVARCHAR(MAX))             AS DataSettings,

    /* --- the actual schedule --- */
    sch.Name                                          AS ScheduleName,
    CONVERT(varchar(8), sch.StartDate, 108)           AS RunsAtTime,
    sch.StartDate                                     AS StartDate,
    sch.RecurrenceType                                AS RecurrenceType, -- 1=once 2=hourly 3=daily/weekly 4=monthly 5=monthlyDOW
    sch.DaysInterval                                  AS EveryNDays,
    sch.WeeksInterval                                 AS EveryNWeeks,
    sch.DaysOfWeek                                    AS DaysOfWeekBitmask, -- 1=Sun 2=Mon 4=Tue 8=Wed 16=Thu 32=Fri 64=Sat
    sch.DaysOfMonth                                   AS DaysOfMonthBitmask,
    sch.MonthlyWeek                                   AS MonthlyWeek,
    sch.Month                                         AS MonthBitmask,

    /* --- human-readable day list --- */
    STUFF(
        CASE WHEN sch.DaysOfWeek &  1 = 1  THEN ',Sun' ELSE '' END +
        CASE WHEN sch.DaysOfWeek &  2 = 2  THEN ',Mon' ELSE '' END +
        CASE WHEN sch.DaysOfWeek &  4 = 4  THEN ',Tue' ELSE '' END +
        CASE WHEN sch.DaysOfWeek &  8 = 8  THEN ',Wed' ELSE '' END +
        CASE WHEN sch.DaysOfWeek & 16 = 16 THEN ',Thu' ELSE '' END +
        CASE WHEN sch.DaysOfWeek & 32 = 32 THEN ',Fri' ELSE '' END +
        CASE WHEN sch.DaysOfWeek & 64 = 64 THEN ',Sat' ELSE '' END,
        1, 1, '')                                     AS RunsOnDays
FROM dbo.Subscriptions       s
JOIN dbo.[Catalog]           c   ON c.ItemID         = s.Report_OID
LEFT JOIN dbo.ReportSchedule rs  ON rs.SubscriptionID = s.SubscriptionID
LEFT JOIN dbo.Schedule       sch ON sch.ScheduleID    = rs.ScheduleID
WHERE c.Path LIKE '%Monkey%'
   OR c.Path LIKE '%Period Catering%'
ORDER BY c.Path, s.Description;
