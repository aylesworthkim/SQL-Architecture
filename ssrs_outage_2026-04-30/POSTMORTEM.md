# SSRS Subscription Email Outage — 2026-04-30 Postmortem

## TL;DR

- **What broke:** every SSRS data-driven subscription that emails out (Daily Sales FLASH x4, Sales per Labor Hour x2, Monkey Orders x2, several `[ALERT]` reports, Database file sizes report, Drivespace alert) failed delivery the morning of 2026-04-30. Each one showed `Done: 1 processed of 1 total; 1 errors` in the SSRS subscription manager. **Reports rendered fine; emails never sent.**
- **Root cause:** `/` filesystem on **dev-jan02** filled to 100%. dev-jan02 hosts the **postfix SMTP relay** that SSRS on SQL-PROD uses for outbound mail. Once `/` was full, postfix refused new SMTP connections and silently rejected every SSRS delivery attempt.
- **NOT the cause:** the boss-ticket work the day before (disabling 33 SSRS subscription jobs + verifying 13 active subscriptions). Verified via `ReportServer.dbo.Catalog.ModifiedDate` and audit of every changed item — the boss-ticket touched only `msdb.dbo.sysjobs.enabled`, which has no mechanism to affect other subscriptions' delivery. **Pure temporal coincidence.**
- **Fix:** truncated 2.7 GB Docker container log on dev-jan02 → `/` recovered to 3.3 GB free → postfix immediately resumed accepting mail → `Run Now` on a FLASH subscription delivered successfully.
- **Time to identify, diagnose, and resolve:** ~3 hours, with most of the time burned chasing the wrong leads (SSRS-side credentials, recipient-query bugs, BCC mailbox theory) before locating the postfix relay on dev-jan02.

## Timeline (all times CDT, 2026-04-30 unless noted)

| Time | Event |
|---|---|
| 2026-04-29 ~10am–12pm | Boss ticket executed: 33 SSRS subscription Agent jobs disabled, 13 retained subscriptions confirmed configured (`Audit Trail.csv`, `subscriptions updated.csv`). |
| 2026-04-29 8:50am | Last SUCCESSFUL Daily Sales FLASH delivery (0 errors). |
| 2026-04-29 (later in day) | dev-jan02 `/` filesystem crosses postfix's no-write threshold. Exact crossover not logged. |
| 2026-04-30 6:30am | First failed `[ALERT]` deliveries of the day (also already pre-existing rendering bugs separately). |
| 2026-04-30 8:25am | First failed Daily Sales FLASH (Corporate). Universal "1 errors" pattern begins. |
| 2026-04-30 9:00am | Outage reported — "no FLASH emails today". |
| 2026-04-30 9:00am–12:00pm | Investigation: ruled out rendering, ruled out recipient-query bugs, ruled out BCC mailbox theory, ruled out data source credential wipes, confirmed yesterday's job-disable had no mechanism to cause this. |
| 2026-04-30 ~12:00pm | Pivot to the postfix-on-dev-jan02 hypothesis. Confirmed postfix listening on :25, queue empty, `/` at 100%. |
| 2026-04-30 ~12:30pm | Truncated `/var/lib/docker/containers/<id>/<id>-json.log` (2.7 GB). `/` recovered to 3.3 GB free. |
| 2026-04-30 ~12:35pm | `Run Now` on `[REPORT] - Daily Sales FLASH - All Open Stores` delivered with **0 errors**. Root cause confirmed. |

## What was changed during this incident

| Change | Where | Effect | Reversible? |
|---|---|---|---|
| `truncate -s 0 /var/lib/docker/containers/<id>/<id>-json.log` | dev-jan02 | Recovered 2.7 GB on `/` (the actual fix) | Logs re-accumulate; future docker output continues writing |
| `rm /var/log/messages-20260429` | dev-jan02 | Recovered 604 MB | Permanent; was a rotated archive — fine |
| `journalctl --vacuum-size=200M` | dev-jan02 | Freed 198.8 MB but from RAM tmpfs, not disk (no df impact) | n/a |
| `find /var/log -name '*-2025*' -delete` etc. | dev-jan02 | Removed dated log archives | Permanent; old logs |
| `Run Now` on backlogged subscriptions | SSRS portal | Delivered missed reports | n/a |

## What was NOT changed

For audit-trail clarity:
- **No SSRS subscription was edited** during this incident. Recipients, schedules, parameters, etc. all untouched.
- **No SSRS data source was edited** — `ReportServer.dbo.Catalog.ModifiedDate` confirms the most recent data source change was 2026-02-26 (over 2 months ago).
- **No SQL Agent jobs were modified** during this incident (only inspected).
- **Yesterday's boss-ticket work (33 job-disables) remains in place.** Per `Audit Trail.csv` rollback SQL is available if needed; intentional and not the cause.

## Follow-ups (for Adam / dev-jan02 owner)

### Immediate

- **Free more disk on `/` of dev-jan02.** Currently at 3.3 GB free / 70 GB total = 96% used. Will refill within days. Big targets:
  - **GitLab data** — `/var/opt/gitlab` is **30 GB**, `/opt/gitlab` is 4.3 GB. If GitLab still in active use → run `gitlab-rake gitlab:cleanup:orphan_job_artifact_files` and prune CI artifacts. If GitLab unused → `dnf remove gitlab-ee && rm -rf /opt/gitlab /var/opt/gitlab` reclaims ~35 GB instantly.
  - **DNF cache** — already partially cleared in this incident; finish with `dnf clean all` (now that there's lock-file space).

### Hardening (so this doesn't happen again)

1. **Docker log rotation.** Add to `/etc/docker/daemon.json`:
   ```json
   { "log-driver": "json-file", "log-opts": { "max-size": "100m", "max-file": "3" } }
   ```
   Restart Docker once. Prevents the 2.7 GB single-log-file scenario we hit today.
2. **DNF auto-clean.** `systemctl enable --now dnf-automatic.timer` with appropriate config. Stops 13 GB+ of stale GitLab RPMs from accumulating.
3. **Journald disk cap.** `/etc/systemd/journald.conf` → `SystemMaxUse=2G`.
4. **Disk-space monitoring with non-email alerting.** ✅ **DONE 2026-04-30 (same day as the incident).** Slack webhook alert installed at `/home/dwilson@nfc.local/disk_alert.sh` + scheduled via `/etc/cron.d/disk_alert` (every 10 min). Warns at 85% used, escalates at 95%, sends recovered notice under 80%. Hysteresis prevents alert spam. Tested end-to-end with a forced threshold drop — Slack message confirmed received. Email alerting was deliberately avoided since this is the exact failure mode that breaks email.
5. **Move postfix spool off `/`** (or grow `/`). Either: relocate `/var/spool/postfix` to `/home` (which has 585 GB free), or grow the LV that backs `/`. Either makes postfix resilient to `/` filling up.
6. **GitLab artifact retention policy.** Configure CI artifact expiration in GitLab admin if Option A above is taken.

### SSRS-side observation (separate ticket)

The `[ALERT]` reports (Missing Config Data, Missing EOD Markers, Over Night Stored Proc Failures, Tables Missing Replicated Data, New stores opening within 3 days) have been failing **rendering** with `rsProcessingAborted` for some time — not delivery, **rendering**. They have a bug in their dataset queries that's distinct from today's outage. Worth fixing as a separate ticket; not blocking. Note that "Over Night Stored Proc Failures" is itself a watchdog for overnight sproc failures — if it's been silent because IT was failing to render, real upstream pipeline issues may have gone unreported.

## Lessons

- **Temporal correlation ≠ causation.** Yesterday's boss-ticket work happening just before today's outage made it look like our work broke something. We had to verify mechanism (no mechanism existed) before believing the data over the gut feeling.
- **The SMTP relay isn't where you'd expect.** SSRS lives on SQL-PROD. The SMTP relay it uses is on dev-jan02 (a Linux box otherwise associated with PHP/Toast pipelines). Future incidents involving "SSRS emails not delivering" should check dev-jan02 disk + postfix queue **first**.
- **Email-based alerting fails silently when email itself fails.** The two existing watchdog reports (`SQL-PROD - Drivespace Alert`, `Over Night Stored Proc Failures`) are emailed via SSRS — meaning when SSRS email is broken, they don't fire. Need a non-email alert channel for at least the disk-space and overnight-build watchdogs.
- **Tooling friction on dev-jan02 cost time.** When `/` is full, `dnf clean` can't write a lock file → can't run. `tar` can't create files in `/tmp`. SCP can't drop tarballs anywhere on `/`. The recovery path required knowing `/home` is on a separate mount with space.
