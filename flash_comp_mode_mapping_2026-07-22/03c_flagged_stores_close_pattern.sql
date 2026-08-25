/* ============================================================================
   03c_flagged_stores_close_pattern.sql  (2026-07-22)  -- read-only
   For the stores Q3b flagged, show net sales + checks + latest close time for
   EACH of the last 14 days. This distinguishes:
     * "closes early every day"  (7/20-7/21 close time ~ its other days)  = NORMAL
     * "truncated on 7/20-7/21"  (those two days close hours earlier than usual,
        and/or net is short vs the store's other recent days)             = TRUNCATION
   Watch especially 1188 (closes mid-afternoon) -- is that every day, or new?
   ============================================================================ */
USE dev_aloha;

DECLARE @End date = '2026-07-21';
DECLARE @Start date = DATEADD(DAY,-13,@End);

SELECT
    c.StoreNum,
    c.DateOfBusiness,
    DOW             = LEFT(DATENAME(WEEKDAY, c.DateOfBusiness),3),
    Checks          = COUNT(*),
    LatestClose_CDT = DATEADD(HOUR,-5, MAX(c.ClosedTime))
FROM toast.dbo.hstCheck c WITH (NOLOCK)
WHERE c.StoreNum IN (1188, 1017, 1061, 1187, 1037, 1090, 1051)   -- Q3b bucket-2/3 stores
  AND c.DateOfBusiness BETWEEN @Start AND @End
  AND c.Voided = 0 AND c.Deleted = 0
GROUP BY c.StoreNum, c.DateOfBusiness
ORDER BY c.StoreNum, c.DateOfBusiness;
