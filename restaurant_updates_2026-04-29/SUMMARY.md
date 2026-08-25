# Restaurant Updates 2026-04-29 — Session Summary

Boss ticket worked over 2026-04-29 (DB updates) and 2026-04-30 (forms-site change + verification).

## The ticket

> 1. Update all of the below restaurants' primary contact to Wes Williams
> 2. Update all the AD's to Brenda Graf
> 3. Make the primary contact phone, email and name accessible via the restaurant
>    setup form so we can change/update w/o having to inject into tables
>
> [10 stores: 1042, 1053, 1069, 1073, 1120, 1127, 1175, 1178, 1184, 1189
>  — all Roundtable / Relentless Restaurants franchise locations]

---

## Task 1 — Primary contact → Wes Williams (10 stores)

- SQL committed via `02_update.sql` (this folder), wrapped in `BEGIN TRAN` / reviewed BEFORE/AFTER / `COMMIT TRANSACTION`.
- Touched: `contacts.dbo.store.StorePrimaryContact = 24` (Wes Williams, `PrimaryContacts.PrimaryID = 24`) for all 10 stores.
- Net change: 5 stores actually flipped from Todd White (PrimaryID 21) → Wes Williams (24): 1073, 1120, 1178, 1184, 1189. The other 5 (1042, 1053, 1069, 1127, 1175) were already Wes — re-saving was a no-op (audit trigger correctly logged nothing for those).
- LastUpdatedBy stamped `Kim Aylesworth`.

## Task 2 — Area Director → Brenda Graf (10 stores)

- Same script (`02_update.sql`), same transaction.
- Touched: `contacts.dbo.store.StoreAreaDirID = 2118` (Brenda Graf, `AreaDir.AreaDirID = 2118`) for all 10 stores.
- Net change: 8 stores flipped — 5 from Wes (AreaDirID 2088) and 3 from Jack Bates (2106) → Brenda (2118). 1042 and 1178 were already Brenda — no-op.

## Task 3 — Primary Contact name/email/phone editable from store form

- Modified `/var/www/html/forms/templates/storeedit.html.php` on dev-jan02.
- Added the **Primary Contact dropdown** (was missing in production — Don had it in `forms_test/` but never deployed).
- Added an **"Edit name / email / phone"** button next to the dropdown that opens `/primarycontact/edit/<id>` in a new tab. Includes a small caption warning that edits affect this person across every store they're linked to (because `PrimaryContacts` is a shared lookup table).
- Backup of pre-change file: `/home/dwilson@nfc.local/storeedit_backup_<timestamp>.html.php`.
- Roundtrip-tested 2026-04-30: changed store 1042's primary contact to "* None None" (PrimaryID 1) via the dropdown → saved → confirmed in DB via SELECT → changed back to Wes Williams → confirmed in DB. Save logic works end-to-end; controller didn't need patching.

---

## Discoveries along the way (separate doc-worthy items)

While debugging this we found out that:

1. **Production isn't where I assumed.** `forms.nfc.local` is fronted by **nginx** on port 80 (not Apache), serving from `/var/www/html/forms/`. There are TWO other near-identical copies in `/var/www/html/` (`forms_test/`, `contacts/`) that aren't live. See `forms_app_infra.md` in memory for the full picture.

2. **HTTPS for forms.nfc.local is broken.** `forms_ssl.conf` was renamed to `forms_ssl.conf.old` at some point — Apache stopped loading it. HTTPS:443 now falls through to a no-DocumentRoot vhost and 404s on everything. Users have been silently using HTTP. Restore plan: rename back to `.conf` AND update `DocumentRoot` from `/var/www/html/contacts` → `/var/www/html/forms`.

3. **`/` is at 100% on dev-jan02.** Couldn't write to `/tmp` or `/var/tmp` — had to use `/home`. Will eventually break things.

4. **Hardcoded DB credentials in source** (`contacts/inc/db_con.inc.php` has the `reports` user pw in plaintext).

---

## Open follow-ups (priority order, none blocking)

| # | item | rough effort |
|---|------|--------------|
| 1 | Restore HTTPS vhost (rename `.old` back, update `DocumentRoot` to `forms/`) | ~5 min |
| 2 | Free space on `/` (journalctl vacuum, log rotation, package cache) | ~30 min |
| 3 | Archive or delete `/var/www/html/contacts/` and `/var/www/html/forms_test/` (dead weight) | ~1 hr including verification |
| 4 | Rotate `contacts.dbo` `reports` user password (currently in source) | depends on every consumer of that user |

---

## Files in this folder

- `01_discovery.sql` — read-only schema + data dump that informed task 1/2
- `02_update.sql` — the actual transactional UPDATE for task 1/2 (already executed and committed 2026-04-29)
- `SUMMARY.md` — this file
