/* ============================================================================
   03_recent_days_completeness.sql   (2026-07-22)  -- read-only

   CONTEXT: All-stores Flash shows R-Net Daily 7/21 = -7.69% and WTD (7/20-7/21)
   = -6.58%, but PTD = -1.23% and YTD = +0.07% (flat). The decline is confined
   to the newest 1-2 days. This pack decides whether 7/20-7/21 are genuinely
   soft or whether the recent data is INCOMPLETE/UNDERSTATED (truncated pull,
   missing store, NULL daypart) -- which would make the "decline" an artifact.
   ============================================================================ */
USE dev_aloha;
DECLARE @AsOf date = '2026-07-21';

/* --- Q1: company R-Net by day, last 3 weeks, with day-of-week ---
   Compare 7/20 & 7/21 to the SAME weekday over the prior weeks (not just LY).
   If they sit well below the trailing same-DOW level -> either a real dip or
   incomplete data. If they're in line -> the LY comp is the odd one, not CY. */
SELECT
    DateOfBusiness,
    DOW = DATENAME(WEEKDAY, DateOfBusiness),
    RNet = SUM(NetSales),
    Checks = SUM(CheckCount)
FROM dev_aloha.dbo.tbl_SalesDataByDayPart
WHERE DateOfBusiness BETWEEN DATEADD(DAY,-20,@AsOf) AND @AsOf
  AND RestaurantID IN (SELECT storeid FROM dev_aloha.dbo.get_StoresIncluded(9,'4',@AsOf))
GROUP BY DateOfBusiness
ORDER BY DateOfBusiness;
GO

/* --- Q2: per-store, did every store report on 7/20 and 7/21? ---
   Flags stores whose recent day is missing or a fraction of their own recent
   norm (dropped/truncated pull). trailing_avg = that store's mean daily net
   over 7/7-7/19; recent days compared against it. */
DECLARE @AsOf2 date = '2026-07-21';
;WITH d AS (
    SELECT RestaurantID, RestaurantName, DateOfBusiness, DayNet = SUM(NetSales)
    FROM dev_aloha.dbo.tbl_SalesDataByDayPart
    WHERE DateOfBusiness BETWEEN DATEADD(DAY,-14,@AsOf2) AND @AsOf2
      AND RestaurantID IN (SELECT storeid FROM dev_aloha.dbo.get_StoresIncluded(9,'4',@AsOf2))
    GROUP BY RestaurantID, RestaurantName, DateOfBusiness
),
base AS (
    SELECT RestaurantID,
           TrailingAvg = AVG(CASE WHEN DateOfBusiness < DATEADD(DAY,-1,@AsOf2) THEN DayNet END)
    FROM d GROUP BY RestaurantID
)
SELECT
    d.RestaurantID, d.RestaurantName,
    Net_0720 = SUM(CASE WHEN d.DateOfBusiness = DATEADD(DAY,-1,@AsOf2) THEN d.DayNet END),
    Net_0721 = SUM(CASE WHEN d.DateOfBusiness = @AsOf2 THEN d.DayNet END),
    TrailingAvg = MAX(b.TrailingAvg),
    Pct_0721_vs_Avg = CASE WHEN MAX(b.TrailingAvg) > 0
        THEN 100.0 * SUM(CASE WHEN d.DateOfBusiness = @AsOf2 THEN d.DayNet END) / MAX(b.TrailingAvg) END
FROM d JOIN base b ON b.RestaurantID = d.RestaurantID
GROUP BY d.RestaurantID, d.RestaurantName
HAVING SUM(CASE WHEN d.DateOfBusiness = @AsOf2 THEN d.DayNet END) IS NULL          -- missing 7/21 entirely
    OR SUM(CASE WHEN d.DateOfBusiness = @AsOf2 THEN d.DayNet END)
       < 0.6 * MAX(b.TrailingAvg)                                                  -- 7/21 < 60% of own norm
ORDER BY Pct_0721_vs_Avg;
GO

/* --- Q3: truncated-pull fingerprint (Toast source) for 7/20-7/21 ---
   A store whose latest check closes early in local time = pull cut off by a 504.
   (ClosedTime is UTC; -5 ~ CDT.) Investigate any store closing before ~7pm. */
SELECT
    c.DateOfBusiness, c.StoreNum,
    Checks = COUNT(*),
    LatestClose_CDT = DATEADD(HOUR,-5, MAX(c.ClosedTime))
FROM toast.dbo.hstCheck c WITH (NOLOCK)
WHERE c.DateOfBusiness IN (DATEADD(DAY,-1,@AsOf), @AsOf)
  AND c.Voided = 0 AND c.Deleted = 0
GROUP BY c.DateOfBusiness, c.StoreNum
HAVING DATEPART(HOUR, DATEADD(HOUR,-5, MAX(c.ClosedTime))) < 19
   AND COUNT(*) > 20
ORDER BY c.DateOfBusiness, LatestClose_CDT;
GO
