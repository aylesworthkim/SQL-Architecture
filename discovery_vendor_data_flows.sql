/*
================================================================================
DISCOVERY: where does vendor data come from?
================================================================================
Purpose
    Map the actual data flows for each vendor DB on SQL-PROD. The
    high-level SQL Agent Jobs documentation only shows ONE vendor pull
    ("Update Monkey local from linked server"), but Newk's has separate
    databases for 7shifts, CrunchTime, OLO, Paytronix, Punchh — and
    nobody's sure how they're being kept fresh.

How to use
    1. Open SSMS, connect to sql-prod
    2. Paste this whole script and hit F5
    3. Each of the 5 sections returns a result set. Save them all.
    4. Send me the output (screenshots or paste-back) and we'll know
       exactly which vendors are alive, dead, or via what pipeline.

Author / Date: Kim + Claude / 2026-06-08
================================================================================
*/


-- ─────────────────────────────────────────────────────────────────────
-- §1. WHEN was each vendor DB last written to?
--     Looks at the biggest 5 tables per DB and reports the most recent
--     "last_user_update" — that's SQL Server's own tracking of when any
--     INSERT/UPDATE/DELETE last touched the table. Tells us if the DB
--     is alive (recent) or stale (months/years old).
-- ─────────────────────────────────────────────────────────────────────
PRINT '=== §1. Last-update timestamp per vendor DB ===';

DECLARE @vendor_dbs TABLE (db_name sysname);
INSERT @vendor_dbs VALUES
    ('7shifts'), ('crunchtime'), ('olo'),
    ('paytronix'), ('punchh'), ('contacts'),
    ('toast'), ('dev_aloha');

DECLARE @sql nvarchar(max) = N'';
SELECT @sql = @sql + N'
SELECT TOP 5
    DB_NAME() AS db_name,
    OBJECT_SCHEMA_NAME(s.object_id) + ''.'' + OBJECT_NAME(s.object_id) AS table_name,
    SUM(p.rows) AS row_count,
    MAX(s.last_user_update) AS last_write,
    MAX(s.last_user_seek)   AS last_read
FROM ' + QUOTENAME(db_name) + N'.sys.dm_db_index_usage_stats s
INNER JOIN ' + QUOTENAME(db_name) + N'.sys.partitions p
    ON s.object_id = p.object_id AND s.index_id = p.index_id
WHERE OBJECTPROPERTY(s.object_id, ''IsUserTable'') = 1
  AND s.database_id = DB_ID(''' + db_name + N''')
GROUP BY s.object_id
ORDER BY MAX(s.last_user_update) DESC;'
FROM @vendor_dbs;

EXEC sp_executesql @sql;


-- ─────────────────────────────────────────────────────────────────────
-- §2. WHAT linked servers are configured?
--     If 7shifts/CrunchTime/etc. is being pulled via a linked server,
--     that server will be listed here.
-- ─────────────────────────────────────────────────────────────────────
PRINT '=== §2. Linked servers configured ===';

SELECT
    name AS LinkedServerName,
    product,
    provider,
    data_source,
    is_linked,
    modify_date
FROM sys.servers
WHERE is_linked = 1
ORDER BY name;


-- ─────────────────────────────────────────────────────────────────────
-- §3. SSIS packages stored on this SQL Server
--     SSIS packages get scheduled via SQL Agent jobs but the package
--     itself is the data-flow definition. If any of these mention a
--     vendor name, that's where the pipeline lives.
-- ─────────────────────────────────────────────────────────────────────
PRINT '=== §3. SSIS packages in msdb ===';

SELECT
    f.foldername      AS folder,
    p.name            AS package_name,
    p.description,
    p.createdate,
    p.ownersid
FROM msdb.dbo.sysssispackages p
INNER JOIN msdb.dbo.sysssispackagefolders f ON p.folderid = f.folderid
ORDER BY f.foldername, p.name;


-- ─────────────────────────────────────────────────────────────────────
-- §4. ALL SQL Agent jobs (incl. ones we may have missed)
--     Sometimes vendor pulls are scheduled via SQL Agent but didn't
--     show up in the high-level Excel doc because they're categorized
--     differently. This is a flat dump.
-- ─────────────────────────────────────────────────────────────────────
PRINT '=== §4. All SQL Agent jobs (every category) ===';

SELECT
    j.name                                    AS job_name,
    j.enabled,
    c.name                                    AS category,
    SUSER_SNAME(j.owner_sid)                  AS owner,
    j.date_created,
    j.date_modified,
    j.description
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.syscategories c ON j.category_id = c.category_id
ORDER BY j.enabled DESC, c.name, j.name;


-- ─────────────────────────────────────────────────────────────────────
-- §5. SQL Agent job STEPS that mention 3rd-party vendors
--     Even if a job's name doesn't say "Paytronix", a step inside it
--     might. This searches the step command text for vendor names.
-- ─────────────────────────────────────────────────────────────────────
PRINT '=== §5. Job steps referencing vendor names ===';

SELECT
    j.name AS job_name,
    s.step_name,
    s.subsystem,
    LEFT(s.command, 200) AS command_preview
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
WHERE s.command LIKE '%7shifts%'
   OR s.command LIKE '%crunchtime%'
   OR s.command LIKE '%punchh%'
   OR s.command LIKE '%paytronix%'
   OR s.command LIKE '%olo.%'
   OR s.command LIKE '%[olo]%'
   OR s.command LIKE '%monkey%'
   OR s.command LIKE '%tattle%'
   OR s.command LIKE '%domo%'
   OR s.command LIKE '%hotsched%'
   OR s.command LIKE '%yext%'
ORDER BY j.name, s.step_id;


PRINT '=== Discovery complete ===';
