from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

wb = Workbook()
hf = Font(name="Arial", bold=True, size=11, color="FFFFFF")
hfill = PatternFill("solid", fgColor="E85D26")
nf = Font(name="Arial", size=10)
ok = PatternFill("solid", fgColor="D4EDDA")
fail = PatternFill("solid", fgColor="F8D7DA")
warn = PatternFill("solid", fgColor="FFF3CD")
dis = PatternFill("solid", fgColor="E9ECEF")
tb = Border(bottom=Side(style="thin", color="DDDDDD"))

def style_sheet(ws, ncols):
    for c in range(1, ncols + 1):
        cl = ws.cell(row=1, column=c)
        cl.font = hf
        cl.fill = hfill
        cl.alignment = Alignment(horizontal="center", wrap_text=True)
    for r in range(2, ws.max_row + 1):
        for c in range(1, ws.max_column + 1):
            cl = ws.cell(row=r, column=c)
            cl.font = nf
            cl.border = tb
    for c in range(1, ws.max_column + 1):
        mx = 0
        for r in range(1, ws.max_row + 1):
            v = ws.cell(row=r, column=c).value
            if v:
                mx = max(mx, len(str(v)))
        ws.column_dimensions[get_column_letter(c)].width = min(mx + 3, 55)

# Sheet 1: Active Jobs
ws1 = wb.active
ws1.title = "Active Jobs"
ws1.append(["Job Name", "Category", "Frequency", "Last Run Status", "Last Run Date", "Steps", "Notes"])
jobs = [
    ["Backups.Daily Differential", "Backup", "Weekly", "Failed", "2026-04-10", 1, "Failed - H: drive full"],
    ["Backups.T-Log 15 min", "Backup", "Every 15 min", "Succeeded", "2026-04-10", 1, "Fixed 4/10 - H: drive cleared"],
    ["Backups.Weekly Full", "Backup", "Weekly", "Failed", "2026-04-08", 1, "Failed - H: drive full"],
    ["Check DB Integ.DB Integrity Check", "Maintenance", "Weekly", "Succeeded", "2026-04-06", 1, "Healthy"],
    ["History Cleanup.Subplan_1", "Maintenance", "Weekly", "Succeeded", "2026-04-06", 1, "Healthy"],
    ["syspolicy_purge_history", "Maintenance", "Daily", "Succeeded", "2026-04-10", 3, "Healthy"],
    ["cdc.Logging_capture", "Maintenance", "On Start", "N/A", "-", 2, "CDC capture for Logging DB"],
    ["Populate tbl_SalesDataByDayPart", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 5, "CRITICAL - builds SSRS rollup table"],
    ["Populate tbl_LaborDataByDayPart", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Labor data rollup"],
    ["Populate_Check_Data", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Check data population"],
    ["Populate Dev_Aloha.dbo.CheckInfo", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Check info summary"],
    ["Populate ASVSummary", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "ASV summary"],
    ["Populate [dev_aloha].[dbo].[MenuMix]", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Menu mix build"],
    ["Populate Weekly Sales", "Data Pipeline", "Weekly", "Succeeded", "2026-04-07", 1, "Weekly sales summary"],
    ["update royalties", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Royalty calculations"],
    ["Update dev_aloha.dbo.Item", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 2, "Item master update"],
    ["Update POS Type", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "POS type classification"],
    ["Update Table Last Replicated Date", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Replication tracking"],
    ["update prod HstvbogcTransactionDetail", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "ASV txns from replication"],
    ["NEW01 - copy vbogcAchStoreSettings", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "ACH store settings sync"],
    ["NEW01 - Populate Tax by Store", "Data Pipeline", "Daily", "Failed", "2026-04-10", 1, "FAILING - needs investigation"],
    ["Update Monkey local from linked server", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Monkey Media sync"],
    ["update logging.dbo.Employees", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Employee tracking"],
    ["update logging.dbo.EmployeeJobByStore", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Employee job tracking"],
    ["update tattle ids", "Data Pipeline", "Daily", "Succeeded", "2026-04-10", 1, "Tattle survey IDs"],
    ["DOMO - Daily Sales Totals", "DOMO", "Daily", "Succeeded", "2026-04-10", 1, "DOMO feed"],
    ["DOMO - Aloha Discounts", "DOMO", "Daily", "Succeeded", "2026-04-10", 1, "DOMO feed"],
    ["DOMO - DailySalesByDayPart", "DOMO", "Daily", "Succeeded", "2026-04-10", 1, "DOMO feed"],
    ["DOMO - Check Avg and PPA", "DOMO", "Daily", "Succeeded", "2026-04-10", 1, "DOMO feed"],
    ["DOMO - Tom Discount Data", "DOMO", "Daily", "Succeeded", "2026-04-10", 1, "DOMO feed"],
    ["DOMO - Net/Check by OrderMode", "DOMO", "Daily", "Succeeded", "2026-04-09", 1, "DOMO feed"],
    ["Populate Domo MASTER PMIX", "DOMO", "Daily", "Failed", "2026-04-10", 1, "FAILING - needs investigation"],
    ["Populate Domo MASTER Sales", "DOMO", "Daily", "Succeeded", "2026-04-10", 1, "DOMO feed"],
]
for r in jobs:
    ws1.append(r)
for r in range(2, ws1.max_row + 1):
    s = ws1.cell(row=r, column=4)
    if s.value == "Succeeded":
        s.fill = ok
    elif s.value == "Failed":
        s.fill = fail
        s.font = Font(name="Arial", size=10, bold=True, color="721C24")
style_sheet(ws1, 7)

# Sheet 2: SSRS Subscriptions
ws2 = wb.create_sheet("SSRS Subscriptions")
ws2.append(["Job ID", "Frequency", "Status", "Last Run", "Notes"])
ws2.append(["~70 SSRS subscription jobs", "Various", "", "", "Auto-created by SSRS. Lookup in ReportServer.dbo.Subscriptions"])
ws2.append(["D7AFA5D5...", "Daily", "Succeeded", "2026-04-08", "Daily Flash - All Open (Group 192)"])
ws2.append(["BCAD45F8...", "Daily", "Succeeded", "2026-04-08", "Enhanced Flash - All Open (Group 192)"])
ws2.append(["F9E13DE0...", "Daily", "Succeeded", "2026-04-08", "Daily Flash - Franchise (Group 8)"])
ws2.append(["520748A0...", "Daily", "Succeeded", "2026-04-08", "Daily Flash - Corporate (Group 79)"])
ws2.append(["CC56FA54...", "Weekly", "Failed", "2026-04-09", "Legacy validation - RECOMMEND DISABLE"])
style_sheet(ws2, 5)

# Sheet 3: Disabled Jobs
ws3 = wb.create_sheet("Disabled Jobs")
ws3.append(["Job Name", "Category", "Last Modified", "Purpose", "Status Note"])
disabled = [
    ["Backup Logging clean up", "Maintenance", "2026-03-06", "Cleans old backup files", "H: drive filled up because this was disabled. Discuss with boss."],
    ["DOMO - Tom Item Data", "DOMO", "2024-05-25", "Item-level DOMO data", "May be replaced by another feed"],
    ["Merge Toast to tbl_SalesDataByDayPart", "Pipeline", "2026-03-11", "Old Toast merge approach", "Replaced by sp_toast_SalesDataByDayPart"],
    ["NEW01 - NonCompingSites", "Pipeline", "2025-11-10", "Non-comping sites list", "Unknown why disabled"],
    ["HotSchedules (3 jobs)", "Export", "2024-08-29", "HotSchedules exports", "Service likely replaced"],
    ["Populate chabi.dbo.Labor", "Pipeline", "2025-01-02", "Chabi labor data", "Chabi DB removed - safe to delete job"],
    ["Pull CT GL and Labor data", "Pipeline", "2025-08-30", "CrunchTime import", "CT integration may have changed"],
    ["Update Chabi Raw tables", "Pipeline", "2025-01-02", "Chabi raw data", "Chabi DB removed - safe to delete job"],
    ["Yext (2 jobs)", "Pipeline", "2023-07-20", "Yext store hours sync", "Yext integration ended"],
    ["z.* prefix (30+ jobs)", "Legacy", "2022-09-30", "Various legacy tasks", "ALL disabled Sep 30 2022 by Don Wilson"],
]
for r in disabled:
    ws3.append(r)
for r in range(2, ws3.max_row + 1):
    for c in range(1, 6):
        ws3.cell(row=r, column=c).fill = dis
style_sheet(ws3, 5)

# Sheet 4: Maintenance Gaps
ws4 = wb.create_sheet("Maintenance Gaps")
ws4.append(["Gap", "Current State", "Risk", "Impact", "Recommendation", "Effort"])
gaps = [
    ["Index Rebuild", "No active job", "HIGH", "Indexes fragment, queries slow down", "Create weekly rebuild job for key tables", "1 hour"],
    ["Statistics Update", "No job exists", "MEDIUM", "Poor query plans, slow queries", "Create weekly UPDATE STATISTICS job", "30 min"],
    ["Backup Cleanup", "Job DISABLED", "CRITICAL", "H: drive fills up, backups fail", "Re-enable cleanup job (discuss with boss)", "5 min"],
    ["Data Archiving", "No job", "LOW", "Tables grow forever, queries slower", "Archive data older than 2 years", "1-2 days"],
    ["Toast Poll Check", "No automated check", "HIGH", "504 timeouts silently drop store data", "Deploy Pipeline Health dashboard", "Built"],
    ["Aloha-Toast Transition", "No automated check", "MEDIUM", "Pre-Toast data missing from rollup", "Pipeline Health dashboard includes this", "Built"],
]
for r in gaps:
    ws4.append(r)
for r in range(2, ws4.max_row + 1):
    risk = ws4.cell(row=r, column=3)
    if "CRITICAL" in str(risk.value):
        risk.fill = fail
    elif "HIGH" in str(risk.value):
        risk.fill = warn
    elif "MEDIUM" in str(risk.value):
        risk.fill = ok
style_sheet(ws4, 6)

# Sheet 5: Failed Jobs
ws5 = wb.create_sheet("Failed Jobs (Current)")
ws5.append(["Job Name", "Last Failure", "Root Cause", "Fix Status", "Action Required"])
failed = [
    ["Backups.T-Log 15 min", "2026-04-10", "H: drive full (20 MB free)", "FIXED - moved 54GB chabi file", "Monitor H: drive"],
    ["Backups.Daily Differential", "2026-04-10", "H: drive full", "Should auto-resolve", "Verify next run"],
    ["Backups.Weekly Full", "2026-04-08", "H: drive full", "Should auto-resolve", "Verify next run"],
    ["CC56FA54 (SSRS validation)", "2026-04-09", "aloha DB no longer exists", "Not fixed", "DISABLE this job"],
    ["Tax by Store rate table", "2026-04-10", "Unknown", "Not investigated", "Check proc and error"],
    ["Domo MASTER PMIX", "2026-04-10", "Unknown", "Not investigated", "Check proc and error"],
]
for r in failed:
    ws5.append(r)
for r in range(2, ws5.max_row + 1):
    s = ws5.cell(row=r, column=4)
    color = ok if "FIXED" in str(s.value) else warn if "auto-resolve" in str(s.value) else fail
    for c in range(1, 6):
        ws5.cell(row=r, column=c).fill = color
style_sheet(ws5, 5)

wb.save("SQL-PROD_Agent_Jobs_Documentation.xlsx")
print("Done! Saved to SQL-PROD_Agent_Jobs_Documentation.xlsx")
