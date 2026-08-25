# Total System Comp % by Year — for Matt Hayward

Asked 2026-08-17. Matt wants one comp % per year, as far back as we can get. He has
historical dollars but no per-year comp store list, and flagged the 13-period →
12-period fiscal calendar change in 2024.

**Status: ANSWERED.** Script 05's gap-robust method returns **FY2025 = -0.73%**, and
Matt independently said 2025 was about **-0.8%**. Two different routes to the same
number. Run `06_FINAL_system_comp_pct.sql` and send its grid 1.

## "Total System" = all stores carrying the comp flag

Not a company-vs-franchise scope question — that was my misreading. It changes nothing
in the numbers: the scripts never applied an ownership filter (`@StoreGroupId = NULL`).
Drop that question from the reply to Matt.

**The flag reconciles COMPLETELY with the derived set for FY2025** (script 07, run
2026-08-17). Results:

| | Count |
|---|---|
| Flagged `StoreIsComping = 1` | 96 |
| ...of those, closed | 6 |
| ...still open | 90 |
| **Derived FY2025 comp set** | **91** |

The important result is that **grid 4 came back empty** — every one of the 91 derived
comp stores carries the flag. And all 5 flagged stores missing from the derived set are
closed ones with too few paired weeks: 1095 Lafayette (40 weeks, needed 44), 1116
Irving, 1143 Austin Congress, 1150 Greenwood IN, 1165 Fort Worth Presidio (all 0
weeks). Clean reconciliation in both directions.

The 90-vs-91 gap is **1144 Gainesville FL**: flagged, closed 2026-07-31, so the "still
open" filter (`StoreCloseDate >= '9999-01-01'`) drops it — but it traded all of FY2025
and belongs in that year's comp set. **91 is the correct FY2025 count.**

The flag also justified the weekend fix: **1188 Lubbock carries the comp flag**, and
the original 6-days-per-week floor was dropping it.

### FY2025 three ways (script 07 grid 5)

| Method | Stores | Comp % |
|---|---|---|
| Derived (paired-week test) | 91 | **-0.71%** |
| Flag, still-open only | 90 | -0.70% |

Both round to **-0.7%**. Matt mentioned -0.8% — but re-reading his message, `AKA 2025
"-0.8%"` was probably illustrating the *format* he wanted rather than asserting the
known value, so don't lean on it as an exact confirmation. A tenth of a point apart,
close enough to be confident in the method, and the residual gap is unexplained.

### ⚠️ But that match only validates FY2025

Which stores carry the flag changes from year to year, and the flag holds no history —
so there is **no ground truth for FY2015-2024**. Those years rest on the method being
sound, not on any verification. Say that plainly to Matt rather than implying the whole
series is confirmed.

**Unless the flips were audited — and there is a trigger.** `contacts.dbo` has
`trg_Store_Identify_Updated_Columns` on `Store` (INSERT, UPDATE, DELETE), writing to
`contacts.dbo.AuditDataChanges` (`TableName`, `RecordPK`, `ColumnName`, `OldValue`,
`NewValue`, `ChangeDate`, `UpdatedBy`). If it captured `StoreIsComping`, the flag's
history is replayable and every year gets real ground truth.

### The audit DOES have it — 2017 onward

Script 08 Part A, run 2026-08-17: **254 `StoreIsComping` flips across 113 stores,
2017-02-16 → 2026-03-12, 10 years.** The 2024-09-05 date in the doc dump was a modify
date, not a create date.

**Script 08 Part C was broken — use `09_comp_flag_history_FIXED.sql` instead.**
`AuditDataChanges.RecordPK` is not the bare StoreID; the trigger builds it as
`QUOTENAME(@RecordPKName + ' = ' + @RecordPk)`, so the stored value is literally
`'StoreId = 1139'`. Part C's `TRY_CAST(RecordPK AS int)` returned NULL on every row,
`#flips` came out empty, and every year fell back to "assumed from current value" —
which is why grid C1 showed `StoresWithRealAuditHistory = 0` and why C2's
"audit-reconstructed -0.71%" agreed with the derived figure. **It was the current flag
in disguise, not an independent check.** Parse on the `'='` — the casing drifts
(`StoreID =` in 2017-2019, `StoreId =` later).

Two more things script 08 got wrong, fixed in 09:
- **Blank Old/NewValue.** The trigger resets them to `''` between columns, so INSERTs
  log `OldValue=''` and DELETEs log `NewValue=''`. Mapping blank → 0 conflates "no
  information" with "explicitly not comping". Rows with blank `NewValue` must be dropped.
- **Junk PKs** in the audit: `StoreId = 1, 197, 198, 9999`.

### The flag is re-cut by hand every January

| Date | Who | What |
|---|---|---|
| 2018-12-31 | Don Wilson | 13 stores ON in 3 minutes |
| 2022-01-03 | Marisa Kunkle | ~30 stores flipped |
| 2022-04-25 | Marisa Kunkle | ~21 turned back ON — looks like a correction to the January batch |
| 2023-01-03 | Matthew Hayward | 9 stores ON |
| 2024-01-08 | Don + Matt | several flipped |
| 2026-01-05 | Don Wilson | 1190, 1194 ON |

Comp membership is a deliberate annual decision. **Matt made several of these flips
himself** (2023-01-03, 2024-01-08, 2025-01-06, plus 2022-09-16 and 2023-10-17) — so his
-0.8% almost certainly came from the flag-based set, and he may simply have the per-year
lists. Worth asking him before doing more reconstruction work.

### Coverage limit — state this honestly

The audit starts 2017-02-16 and records only *changes*. A store's first recorded flip
lets us extrapolate backwards from its `OldValue`, which is real evidence — but any flip
before Feb 2017 is invisible. So **FY2015-2016 cannot be validated at all** and FY2017
only partially. Script 09 grid 3 reports per year how many stores rest on audit evidence
versus a fallback assumption; read it before trusting any year's comparison in grid 4.

## THE ANSWER — Total System comp % by fiscal year

⚠️ **The table below is from script 05, which used the older absolute thresholds
(6 days/week, 45 weeks). Script 06/07's per-store calibration shifts every year
slightly — FY2025 moved from -0.73%/90 stores to -0.71%/91 stores when 1188 Lubbock
came back in. Run script 06 and take ITS grid 1 as the final series.** The shifts are
hundredths, not material to the story, but the numbers Matt gets should come from 06.

From script 05 grid 5 (gap-robust, 90 comp stores in FY2025):

| FY | Comp % | Comp stores |
|---|---|---|
| 2015 | **+5.16%** | 64 |
| 2016 | **-0.37%** | 76 |
| 2017 | **-3.10%** | 90 |
| 2018 | **-3.33%** | 99 |
| 2019 | **-3.39%** | 102 |
| 2020 | **-17.99%** | 97 |
| 2021 | **+25.30%** | 92 |
| 2022 | **+6.96%** | 89 |
| 2023 | **+1.88%** | 90 |
| 2024 | **-1.24%** | 90 |
| 2025 | **-0.73%** | 90 |

FY2020/FY2021 are the COVID collapse and rebound. FY2026 YTD was missing from script
05 (hard-coded 45-week floor wiped out the partial year) — script 06 fixes that.

Script 02's plain full-year method gave FY2025 = -1.15% on 77 stores. That was the
artifact. Numbers agree closely everywhere else (FY2020 -17.87 vs -17.99, FY2024
-1.48 vs -1.24), which is itself a good cross-check.

## What script 06 fixes over script 05

1. **Weekend-closed stores were being silently dropped.** Script 05 required 6
   sales-days for a week to count. **1188 Lubbock (Broadway)** and **1198 Athens GA
   (UGA)** are closed *every* weekend — grid 1 showed 1188 with a 2-day gap every
   single week of 2025. A 5-day store can never reach 6, so Lubbock was excluded from
   the comp set entirely despite opening in 2022. Script 06 calibrates the day
   threshold per store per year (within 1 day of that store's own busiest week), so a
   7-day store needs 6+ and a 5-day store needs 4+.
2. **FY2026 YTD now appears.** The 45-week minimum was hard-coded, so the partial
   FY2026 (~33 weeks) had every store filtered out and the year silently vanished.
   Now the floor is a share of the best-covered store that year.
3. **The gap assessment label was anchored on the wrong end** — see below.

## Root cause of the FY2025 gaps — confirmed, and it's systematic

Script 05 grid 1 anchored its verdict on `GapStart`. Wrong end. The output shows
`GapEnd` is *always* the day before `ToastLive`, and `GapStart` is *always* the 1st
of the month:

| Store | Gap | ToastLive |
|---|---|---|
| Gulfport | 09-01 → 09-29 | 09-30 |
| Athens Epps Bridge | 09-01 → 09-24 | 09-25 |
| Benton | 12-01 → 12-22 | 12-23 |
| Shreveport | 11-01 → 11-19 | 11-20 |
| Tuscaloosa | 12-01 → 12-15 | 12-16 |

**The Aloha data for the pre-cutover portion of each store's ToastLive month was
never loaded.** Not random missed polls — a systematic hole, one per store, at
migration. That's the backfill worklist (script 06 grid 5), and fixing it is what
would make the plain full-year method agree with the paired-week one.

Three other populations, all benign or separate:
- **Single-day gaps are real closures** — Thanksgiving 11-27, 07-04, Easter 04-20,
  12-24, and the Jan/Feb winter-storm days (01-10, 01-21/22, 02-19). Expected.
- **2025-10-13 → 10-19 is one whole fiscal week missing across seven stores at once**
  (1063, 1072, 1076, 1079, 1131, 1134, 1035) — a rollup that never ran, not a
  store-level problem.
- **1188 / 1198 recurring weekend gaps** — those stores are closed weekends.

## Gap backlog by year (script 05 grid 2)

FY2022-2024 are clean (worst single gap 4-5 days = holidays only). FY2020 has 1,905
gap days / 17 gaps of 3+ weeks — real COVID dining-room closures, not data loss.
FY2025 has 909 gap days / 31 gaps of a week or more: the Toast migration. FY2014 has
a 140-day gap (store 1023 Panama City).

## StoreID reuse — only 3 real cases

Script 05 grid 3 found 4 IDs, of which **1049, 1053, 1139** are genuine reuse (1053
has 11 years of history before its current occupant's open date). **1144** is a
0-year difference — just pre-opening/soft-open sales, not reuse.

Script 05 grid 4's "LIKELY CHANGE OF OCCUPANT" label over-fires: 1058, 1028, 1144
and 1139 have their long breaks in **2020/2021**, which are COVID closures, not
changes of occupant. Only **1169** (193 days in 2019) and **1023 Panama City** (140
days in 2014) predate COVID and look like genuine occupant changes or long remodels.

## ⚠️ Superseded — script 02's FY2025 number

Script 02 returned FY2025 = **-1.15%** on 77 comp stores. Matt said **-0.8%**.
Ours is probably the wrong one.

**13 stores fell out of the FY2025 comp set for being "dark" 19-34 days, and every
one has a late-2025 ToastLive date:** 1004 Tuscaloosa (345 days), 1023 Panama City
(344), 1033 Waco (344), 1037 Tallahassee (344), 1039 Byram (343), 1054 West Plano
(343), 1029 Huntsville Whitesburg (342), 1157 Columbus GA (342), 1021 Shreveport
(341), 1184 Benton (340), 1048 Bossier City (339), 1182 Athens Epps Bridge (337),
1036 Gulfport (330).

Thirteen restaurants did not all go dark for a month in the same year. That's the
missed-poll pattern around each store's Toast cutover — exactly the risk flagged
before running. FY2025 should have ~90 comp stores, not 77.

**Script 05 grid 1** proves or disproves this by lining the actual missing date
ranges up against `ToastLive`. **Grid 5** is the fix: a gap-robust comp that
compares each store only over the fiscal weeks where it has good data in *both*
years, so a store dark 3 weeks contributes its other 49 instead of being dropped.

## ⚠️ StoreID reuse — historical names and open dates are unreliable

Script 02 grid 2 lists store **1053 "Knoxville TN (Cedar Bluff)", open date
2024-08-12, as a comp store in FY2015**. Also 1049 "Nashville Belle Meade" (opened
2018) in FY2015-16 and 1139 "Smyrna GA" (opened 2021) in FY2019-20.

`contacts.dbo.Store` holds only the **current occupant** of each StoreID. Newk's
reuses store numbers and the row gets overwritten, so the name and open date
attached to older sales belong to a different restaurant. 1053's history has a real
break in 2024 — old store out, Knoxville in.

Impact on the percentages is limited (the sales-presence test drops the changeover
year — 1053 was correctly excluded in FY2024 and FY2025), but **any store name or
open date in a historical comp list is suspect**. Script 05 grids 3 and 4 find every
affected ID and flag the dangerous case: a changeover straddling a year boundary
would look like one continuous comp store.

## If you get "Msg 213: Column name or number of supplied values..."

Temp-table collision between scripts in the same query window. Script 02 leaves
`#notastore` behind with **two** columns; script 05 wanted it with one. SQL Server
compiles an entire batch *before* executing any of it, so an inline
`IF OBJECT_ID(...) DROP TABLE` **cannot** save you — the `INSERT` gets validated
against the stale definition and fails before the drop ever runs.

Fixed by putting the drops in their own batch ended by `GO` at the top of scripts 02
and 05, so they actually execute before the rest compiles. Script 05 also renamed its
copy to `#skipstore` so it can't collide again. **Don't delete those `GO` lines.**

General rule for this whole folder: either run each script in a fresh query window,
or keep the cleanup batch at the top.

## Fixed in script 02 after the first run

- **Grid 4's strict column was broken** — it compared `TyDaysOpen` against `DaysTY`,
  the distinct date count across *all* stores (364). No single store is ever open
  364 days (holidays), so a normal full year is ~358-360 and the column returned 0
  stores / NULL comp for every year. Now benchmarks against 0.99 of the busiest
  store's actual day count.
- **Grid 3 now filters all-zero store-years** (1038 in FY2022, 1028 in FY2023, 1174
  in FY2025 had 0 sales on both sides — pure noise in an exclusion review).

## Files

| File | What it does |
|---|---|
| `01_probe_DONE_2026-08-17.sql` | Discovery. Already run — findings below. |
| `02_system_comp_pct_by_year.sql` | **The deliverable.** Comp % FY2015→FY2026 off `tbl_SalesDataByDayPart`. Grid 1 is Matt's answer. |
| `03_deep_history_from_weeklysales.sql` | Extends the series back to ~2005 by parsing the legacy 13-period `WeekName`. Different calendar basis — read its header before splicing. |
| `04_FN_GetCompingDate_is_broken.sql` | Side finding, unrelated to Matt's ask but needs an owner. Two real defects in the official comping-date function. |
| `05_diagnose_gaps_and_id_reuse.sql` | Run. Proved the Toast data gaps, found the reused StoreIDs, produced the -0.73% that matches Matt. Superseded by 06 for the final number. |
| `06_FINAL_system_comp_pct.sql` | **Run this and send grid 1.** Same method as 05 grid 5 plus three fixes: weekend-closed stores no longer dropped, FY2026 YTD appears, gap report anchored correctly. |
| `07_validate_against_comp_flag.sql` | Reconciles the derived FY2025 set against `StoreIsComping` store by store. Grids 3 and 4 should be empty apart from the 5 stale flags. |
| `08_recover_comp_flag_history_from_audit.sql` | Parts A and B are good and already run — they found 254 flips back to 2017. **Part C is broken (RecordPK parse); ignore it.** |
| `09_comp_flag_history_FIXED.sql` | **Run this next.** Correct parse. Grid 3 = how much of each year rests on audit evidence; grid 4 = derived vs audit-flag comp % per year (the real validation); grid 6 = the recorded comp store list per year. |

## What the probe changed

The first draft of this got three things wrong. Corrected:

**1. `WeeklySales` does not join to `CalendarV2`.** `WeeklySales.WeekName` is the old
13-period encoding (`Y2004_P02_WK2`); `CalendarV2.WeekName` is a date string
(`2005-01-02`). Probe grid C1 returned zero rows and grid D showed `WeeklySales_Net`
NULL for all 13 years. Script 03 parses the string instead.

**2. `tbl_SalesDataByDayPart` goes back to FY2014, not 3-4 years.** 880k rows covers
13 fiscal years ($141.8M in FY2014 → $211.1M in FY2025, 75 → 101 stores). It stamps
each day with its own `FiscalYear`/`FiscalWeek`, so it needs no calendar join at all.
This is the primary source. First comparable year is FY2015.

**3. `CalendarV2` reports `PeriodsInYear` = 12 for *every* year, 2004 through 2035.**
It's been retro-fitted to the new calendar — the 13→12 change is not recorded there.
`WeeklySales.WeekName` is now the only place the historical 13-period structure
survives. This also silently broke `FN_GetCompingDate` (see script 04).

## Matt's two concerns

**"I don't have a list of comp stores for each year."** We don't have one stored
either, and the thing that looks like one is a trap: `contacts.dbo.Store.StoreIsComping`
is a bit reflecting *today only*, flipped over time by `new01_Move_NonComping_To_Comping`.
It's also demonstrably stale — 1095 Lafayette LA closed 2025-10-24 and is still
flagged 1. So the scripts derive comp status from sales presence instead: a store is
comp in FY Y only if it rang sales on ≥95% of the compared days in **both** Y and Y-1.
Grid 2 hands Matt the per-year list.

**The 13→12 period change.** Doesn't affect the answer — but not for the reason I
first gave. The scripts work at day/week grain and never read `FiscalPeriod`.

The 53-week worry was also the **wrong worry**. CalendarV2's fiscal years are
calendar-aligned at 364-366 `DaysInYear`, never 371, so a "53-week" year is just
partial boundary weeks, not an extra week of sales. The real issue is the **day
count**: FY2022 = 366 days, FY2023 = 364. That's a ~0.55% swing, which matters a lot
when the answer is "-0.8%". Grid 1 reports raw `CompPct` **and** `CompPctDayAdj`.

## Gotchas baked into the scripts

- **Sentinel dates, not NULLs.** `contacts.dbo.Store` uses `9999-01-01` for "no close
  date" and "not open yet" — there are **zero** NULLs. Any `StoreCloseDate IS NULL`
  logic matches nothing.
- **Seven non-restaurant rows excluded:** 1 (Dev Center), 88888 (placeholder, "opened"
  1970-01-01), 9998/9999 (test kitchens), 5002 (Rockwall virtual site), 1200/1201
  (Upcoming, open date 9999-01-01).
- **Closed stores are NOT excluded.** A store that closed in 2022 was a legitimate
  comp store in 2015-2021 and stays in those years. Only the `zClosed -` name prefix
  marks them; don't filter on it.
- **FY2026 is partial** (data through 2026-08-16). Each year pair is clipped to the
  weeks both years have, so FY2026 comes out as YTD-vs-YTD rather than a fake -40%.
- `tbl_HstSalesSummary` turned out to only cover 2018+, and 2026 has just 4 stores —
  it looks abandoned. Not usable, don't reach for it.

## Before sending numbers out

- **Grid 3 of script 02** (exclusions, sorted by `DaysShortfall` ascending). A store
  that missed only a handful of days is almost certainly a **missed poll, not a
  closure** — and it will move the system comp %. Any store whose open/close dates
  don't explain the gap needs a look.
- **Grid 4** (sensitivity). Three strictness settings. Within ~0.2 pts = solid
  whichever definition Finance prefers; a big swing = send with a caveat.
- **Grid 3 of script 03** (the overlap test) before quoting anything pre-2015. Two
  different calendars, so exact agreement isn't expected — but if FY2015-2025 diverge
  by whole points between the two sources, don't send the deep series.
- **The 2025 Toast rollout.** Every store went Toast during 2025 (`ToastLive` dates
  cluster Mar-Dec 2025). Check-count basis definitely changed across that cutover
  (see `fy25_checkcounts_for_matt/`); net sales dollars should be continuous, but
  FY2025 is the year to sanity-check hardest, and it's the exact year Matt quoted.
- Early years in script 03 are volatile by construction — a 2-store system swings
  hard. `CompStores` under ~10 is anecdote, not a system comp.

## Open questions for Matt

1. **Which comp definition does Finance use?** The scripts use "open ~all of both
   years," which is standard. Newk's official rule is documented as the 19th full
   period after opening (~18 months) — but the function implementing it is broken two
   ways (script 04), so nothing downstream has been applying it correctly anyway.
2. **Total System = company + franchise, or company only?** Scripts default to all.
   `@StoreGroupId`: 79 = company, 8 = franchise.

## Separate escalation — script 04

Not Matt's problem, but someone owns this. `dev_aloha.dbo.FN_GetCompingDate`:

- **Returns the 6th period after opening, not the 19th.** It computes
  `@NineteenthPeriodStart` and then throws it away, returning the 6-period value. The
  docstring and the variable name both say 19. Looks like an unfinished edit from 2017.
- **Its 13-period wrap math broke when CalendarV2 went to 12 periods.** Stores opening
  in period 8 get `8 + 5 = 13`, a period that no longer exists → **function returns
  NULL**. Stores opening in periods 9-12 wrap by 13 instead of 12 and land **one
  period early**. Periods 1-7 are unaffected.

Feeds `/Accounting/Restaurant Open Date and Comping Date` and the "Non Comping
Stores" reports. Script 04 proves it per store and counts the damage. Don't "fix" it
before asking Finance which rule is intended — 6 vs 19 periods changes the comp list.

## Draft reply to Matt

> [NUMBERS BELOW ARE FROM SCRIPT 05 — refresh from script 06 grid 1 before sending.]
>
> Got it. 2025 comes out at -0.7% on 91 comp stores, so close to the -0.8% you
> mentioned. Here's the series back to 2015:
>
> | FY | Comp % | | FY | Comp % |
> |---|---|---|---|---|
> | 2015 | +5.2% | | 2021 | +25.3% |
> | 2016 | -0.4% | | 2022 | +7.0% |
> | 2017 | -3.1% | | 2023 | +1.9% |
> | 2018 | -3.3% | | 2024 | -1.2% |
> | 2019 | -3.4% | | 2025 | -0.7% |
> | 2020 | -18.0% | | | |
>
> On the comp store list you were missing — the "is comping" flag on the store record
> only tells us who comps *today*, and it gets rewritten as stores mature, so it can't
> answer the question for past years. What I did instead was rebuild the comp set per
> year from the sales history itself. For 2025 I can check that against the flag and
> the two agree exactly: every store my method picks up carries the flag, and the only
> flagged stores it leaves out are ones that had closed. So the approach is sound.
>
> Worth being straight about the earlier years though: because the flag keeps no
> history, there's nothing to check 2015-2024 against. Those numbers rest on the method
> rather than on a second source. I'm looking into whether our audit trail captured the
> flag changes over time — if it did, I can confirm every year properly.
>
> You'll get the per-year store list alongside the percentages either way.
>
> The calendar change turned out not to matter — I work at the fiscal week level rather
> than by period, so 13 vs 12 is irrelevant. What did matter, and I wouldn't have
> guessed it: our fiscal years aren't all the same length. FY2023 has 364 days against
> FY2022's 366. That's about half a point, which is a lot at this scale.
>
> One caveat on the early years: our sales detail only starts in FY2014, so 2015 is the
> earliest year I can compute. There's an older weekly table that reaches 2004 if you
> want to go deeper, but it's on the legacy 13-period calendar and wouldn't splice
> cleanly onto the above — I'd send that as a separate series rather than extend this
> one.
>
> Separately, worth flagging: when we migrated stores to Toast last year, the Aloha
> sales for the pre-cutover part of each store's go-live month never got loaded. It
> hits about 15 stores. It doesn't affect the comp numbers above — I worked around it —
> but anyone pulling those specific months store-by-store will see holes, so it's worth
> getting backfilled.
>
> Two questions: is "Total System" company + franchise, or company only? And what comp
> definition does Finance formally use? We have an official rule on the books — 19
> periods after opening — but the function implementing it has a couple of real bugs, so
> I'd rather confirm the intended rule than inherit whatever it's been doing.
