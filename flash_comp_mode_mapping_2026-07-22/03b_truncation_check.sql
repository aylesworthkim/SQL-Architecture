/* ============================================================================
   03b_truncation_check.sql  (2026-07-22)  -- read-only, self-contained
   Standalone re-run of Q3 (the earlier one errored: @AsOf was dropped by GO).
   Truncated-pull fingerprint for 7/20 & 7/21: a store whose LAST check closes
   early in local time = its overnight pull was cut off (504) and the rest of
   that day's sales never loaded.  ClosedTime is UTC; -5h ~ CDT.
   ============================================================================ */
USE dev_aloha;

DECLARE @D1 date = '2026-07-20';
DECLARE @D2 date = '2026-07-21';

SELECT
    c.DateOfBusiness,
    c.StoreNum,
    Checks          = COUNT(*),
    LatestClose_CDT = DATEADD(HOUR,-5, MAX(c.ClosedTime))
FROM toast.dbo.hstCheck c WITH (NOLOCK)
WHERE c.DateOfBusiness IN (@D1, @D2)
  AND c.Voided = 0 AND c.Deleted = 0
GROUP BY c.DateOfBusiness, c.StoreNum
HAVING DATEPART(HOUR, DATEADD(HOUR,-5, MAX(c.ClosedTime))) < 19   -- closes before ~7pm local
   AND COUNT(*) > 20
ORDER BY c.DateOfBusiness, LatestClose_CDT;
