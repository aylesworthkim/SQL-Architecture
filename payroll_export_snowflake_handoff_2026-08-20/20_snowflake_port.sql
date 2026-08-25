/* =====================================================================
   Company Store Payroll Export - Toast   |   SNOWFLAKE PORT
   ---------------------------------------------------------------------
   ANSI/Snowflake rewrite of dev_aloha.dbo.sp_rpt_Company_Payroll_Export_TOAST.
   Produces exactly the 10 columns of the SSRS/Excel export.

   Assumes the SQL Server tables have been landed in Snowflake as:
     TOAST.HSTSHIFT, TOAST.HSTPAYMENT, TOAST.RESTAURANTS, TOAST.EMPLOYEES,
     TOAST.JOBCODES, TOAST.JOBCODETOASTTOALOHAMAP,
     DEV_ALOHA.GBLSTORE, CONTACTS.COMPANYSETUP
   ...and that STORE_LIST below is replaced with however the store set is
   modelled in Snowflake. The SQL Server original calls
   dev_aloha.dbo.get_StoresIncluded(@StoreGrouping, @StoreGroup, @EDate):
     StoreGrouping = 2, StoreGroup = '0'   -> all stores (95 in Aug 2026)
     StoreGrouping = 9, StoreGroup = '79'  -> * All - Company Restaurants (28)
     StoreGrouping = 9, StoreGroup = '244' -> corporate Toast stores (28, proc default)
     StoreGrouping = 8, StoreGroup = '<n>' -> a single store
   Payroll only cares about the company stores; run 9/'79' for that.
   ===================================================================== */

WITH params AS (
    SELECT DATE '2026-08-03' AS sdate,
           DATE '2026-08-16' AS edate
),

store_list AS (          -- <<< replace with the Snowflake store dimension
    SELECT store_id
    FROM   dev_aloha.store_group_member
    WHERE  store_group_id = 79
),

/* ---- denominator: every non-salary hour the store paid in the period.
   Deliberately mirrors the T-SQL: no Deleted filter, and
   wage_frequency <> 'salary' drops NULL wage_frequency rows.        ---- */
store_hours AS (
    SELECT r.storeid                                    AS store_id,
           SUM(hs.regularhours + hs.overtimehours)       AS total_hours
    FROM   toast.hstshift hs
    JOIN   toast.restaurants r ON r.guid    = hs.store
    JOIN   store_list      sl  ON sl.store_id = r.storeid
    JOIN   toast.jobcodes  jc  ON jc.guid   = hs.jobcode
    CROSS JOIN params p
    WHERE  hs.dateofbusiness BETWEEN p.sdate AND p.edate
      AND  LOWER(jc.wagefrequency) <> 'salary'
    GROUP BY r.storeid
),

/* ---- numerator: non-cash tips actually captured at the store ------- */
store_tips AS (
    SELECT r.storeid              AS store_id,
           SUM(pm.tipamount)      AS total_tips
    FROM   toast.hstpayment pm
    JOIN   toast.restaurants r ON r.guid = pm.storeid   -- hstPayment.StoreID holds the restaurant GUID
    JOIN   store_list      sl  ON sl.store_id = r.storeid
    CROSS JOIN params p
    WHERE  pm.dateofbusiness BETWEEN p.sdate AND p.edate
      AND  LOWER(pm.paymenttype) <> 'cash'
      AND  UPPER(pm.paymentstatus) IN ('CAPTURED','AUTHORIZED')
    GROUP BY r.storeid
),

tip_pool AS (
    SELECT COALESCE(h.store_id, t.store_id)         AS store_id,
           h.total_hours,
           t.total_tips,
           t.total_tips / NULLIF(h.total_hours, 0)  AS tips_per_hour
    FROM   store_hours h
    FULL OUTER JOIN store_tips t ON t.store_id = h.store_id
),

/* ---- employee x job code x rate grain ------------------------------ */
detail AS (
    SELECT cs.adpcompanycode                        AS co_code,
           gs.adpbatchid                            AS batch_id,
           gs.adpbatchdescription                   AS batch_description,
           e.externalemployeeid                     AS file_num,
           e.first                                  AS first_name,
           e.last                                   AS last_name,
           jcm.exportid                             AS temp_dept,
           hs.hourlywage                            AS temp_rate,
           SUM(hs.regularhours)                     AS reg_hours,
           SUM(hs.overtimehours)                    AS ot_hours,
           SUM(ROUND((hs.regularhours + hs.overtimehours) * tp.tips_per_hour, 2)) AS earnings3_amount
    FROM   toast.hstshift hs
    JOIN   toast.employees e   ON e.guid     = hs.employee
                              AND e.storeguid = hs.store      -- INNER: hours for an
                                                              -- employee with no row at
                                                              -- that store vanish entirely
    JOIN   toast.restaurants r ON r.guid     = e.storeguid
    JOIN   store_list sl       ON sl.store_id = r.storeid
    JOIN   tip_pool  tp        ON tp.store_id = r.storeid
    JOIN   dev_aloha.gblstore gs ON gs.storeid = r.storeid
    JOIN   toast.jobcodes jc   ON jc.guid    = hs.jobcode
    JOIN   toast.jobcodetoasttoalohamap jcm ON jcm.toastjc = jc.code
    CROSS JOIN contacts.companysetup cs                        -- single row
    CROSS JOIN params p
    WHERE  hs.dateofbusiness BETWEEN p.sdate AND p.edate
      AND  LOWER(jc.wagefrequency) <> 'salary'
      AND  hs.deleted = 0
    GROUP BY cs.adpcompanycode, gs.adpbatchid, gs.adpbatchdescription,
             e.externalemployeeid, e.first, e.last, jcm.exportid, hs.hourlywage
)

/* ---- final export rows --------------------------------------------
   NOTE: first_name / last_name are intentionally NOT in this GROUP BY,
   because the T-SQL original drops them here. Two different employees
   who share a File # (i.e. both blank) at the same job code and rate
   therefore merge into one row.                                    ---- */
SELECT co_code            AS "Co Code",
       batch_id           AS "Batch ID",
       file_num           AS "File #",
       batch_description  AS "Batch Description",
       SUM(reg_hours)     AS "Reg Hours",
       SUM(ot_hours)      AS "OT Hours",
       'tip01'            AS "Earnings 3 Code",
       SUM(earnings3_amount) AS "Earnings 3 Amount",
       temp_dept          AS "Temp Dept",
       temp_rate          AS "Temp Rate"
FROM   detail
WHERE  temp_dept <> 'NOREPORT'
GROUP BY co_code, batch_id, file_num, batch_description, temp_dept, temp_rate
ORDER BY batch_id, file_num, temp_dept;
