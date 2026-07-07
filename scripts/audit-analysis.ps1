<#
.SYNOPSIS
    MedCare IAM Lab - Phase 2: Access Audit Analysis
.DESCRIPTION
    Cross-references the Entra ID directory exports against the authoritative HR feed
    to identify identity governance findings:
      F-01  Orphaned accounts   (Terminated in HR, still Enabled in directory)
      F-02  Privileged orphans  (F-01 accounts holding privileged group membership)
      F-03  Privilege creep     (Active users holding access beyond their current role)
      F-04  Data hygiene        (Users missing required identity attributes)
    Outputs one findings CSV per finding plus a console summary.
    NOTE: This analysis uses ONLY the HR feed's employment columns as the source of
    truth. The 'Notes' column (lab answer key) is deliberately ignored.
.NOTES
    Run from anywhere in PowerShell 7. Pure file analysis - no Graph connection needed.
    Author: Sime Delonney Njeba | Identity Lifecycle Governance Lab
#>

# ============ CONFIG ============
$HrFeed      = "C:\medcare-iam-lab\data\medcare-hr-feed.csv"
$UsersExport = "C:\medcare-iam-lab\evidence\02-audit-findings\all-users-export.csv"
$Memberships = "C:\medcare-iam-lab\evidence\02-audit-findings\group-memberships.csv"
$OutDir      = "C:\medcare-iam-lab\evidence\02-audit-findings"
$PrivilegedGroups = @("IT-Admins")
# ================================

# The approved role -> access matrix (target state; matches RBAC design)
$roleAccess = @{
    "Nurse"                 = @("APP-EHR-Users","APP-Scheduling-Users")
    "Physician"             = @("APP-EHR-Users","APP-Scheduling-Users")
    "Billing Specialist"    = @("APP-Billing-Users")
    "Finance Analyst"       = @("APP-Finance-Users")
    "Helpdesk Technician"   = @("APP-AdminPortal-Users")
    "System Administrator"  = @("APP-AdminPortal-Users","IT-Admins")
    "HR Coordinator"        = @("APP-HRIS-Users")
    "Receptionist"          = @("APP-Scheduling-Users")
    "Office Manager"        = @("APP-Scheduling-Users")
}

$hr      = Import-Csv $HrFeed      | Select-Object * -ExcludeProperty Notes  # answer key excluded
$dir     = Import-Csv $UsersExport
$members = Import-Csv $Memberships

# Index HR by EmployeeID for fast lookup
$hrById = @{}; foreach ($h in $hr) { $hrById[$h.EmployeeID] = $h }

# ---------- F-01: ORPHANED ACCOUNTS ----------
$f01 = foreach ($d in $dir) {
    $h = $hrById[$d.EmployeeId]
    if ($h -and $h.Status -eq "Terminated" -and $d.AccountEnabled -eq "True") {
        [pscustomobject]@{
            FindingID   = "F-01"
            Severity    = "High"
            EmployeeId  = $d.EmployeeId
            Name        = $d.DisplayName
            JobTitle    = $d.JobTitle
            TermDate    = $h.TermDate
            DaysOrphaned = [int]((Get-Date) - [datetime]$h.TermDate).TotalDays
            Issue       = "Terminated in HR but account still ENABLED in directory"
        }
    }
}

# ---------- F-02: PRIVILEGED ORPHANS ----------
$orphanIds = $f01.EmployeeId
$f02 = foreach ($m in $members) {
    if ($m.EmployeeId -in $orphanIds -and $m.Group -in $PrivilegedGroups) {
        [pscustomobject]@{
            FindingID  = "F-02"
            Severity   = "CRITICAL"
            EmployeeId = $m.EmployeeId
            Name       = $m.Name
            Group      = $m.Group
            Issue      = "TERMINATED user retains PRIVILEGED group membership"
        }
    }
}

# ---------- F-03: PRIVILEGE CREEP (active users, access beyond current role) ----------
$f03 = foreach ($d in ($dir | Where-Object { $hrById[$_.EmployeeId].Status -eq "Active" })) {
    $expected = $roleAccess[$d.JobTitle]
    $actual   = ($members | Where-Object EmployeeId -eq $d.EmployeeId).Group
    foreach ($g in $actual) {
        if ($g -notin $expected) {
            [pscustomobject]@{
                FindingID  = "F-03"
                Severity   = if ($g -in $PrivilegedGroups) { "CRITICAL" } else { "Medium" }
                EmployeeId = $d.EmployeeId
                Name       = $d.DisplayName
                JobTitle   = $d.JobTitle
                ExcessGroup= $g
                Issue      = "Active user holds access not implied by current role"
            }
        }
    }
}

# ---------- F-04: DATA HYGIENE ----------
$f04 = foreach ($d in $dir) {
    if ([string]::IsNullOrWhiteSpace($d.Department)) {
        [pscustomobject]@{
            FindingID  = "F-04"
            Severity   = "Medium"
            EmployeeId = $d.EmployeeId
            Name       = $d.DisplayName
            JobTitle   = $d.JobTitle
            Issue      = "Missing Department attribute - breaks attribute-driven provisioning and reporting"
        }
    }
}

# ---------- OUTPUT ----------
$f01 | Export-Csv "$OutDir\F01-orphaned-accounts.csv"  -NoTypeInformation
$f02 | Export-Csv "$OutDir\F02-privileged-orphans.csv" -NoTypeInformation
$f03 | Export-Csv "$OutDir\F03-privilege-creep.csv"    -NoTypeInformation
$f04 | Export-Csv "$OutDir\F04-data-hygiene.csv"       -NoTypeInformation

Write-Host "`n================ AUDIT FINDINGS SUMMARY ================" -ForegroundColor Cyan
Write-Host ("F-01 Orphaned accounts:          {0}  (High)"     -f @($f01).Count) -ForegroundColor Yellow
Write-Host ("F-02 Privileged orphans:         {0}  (CRITICAL)" -f @($f02).Count) -ForegroundColor Red
Write-Host ("F-03 Privilege creep instances:  {0}  (Medium+)"  -f @($f03).Count) -ForegroundColor Yellow
Write-Host ("F-04 Data hygiene failures:      {0}  (Medium)"   -f @($f04).Count) -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "Findings CSVs written to $OutDir" -ForegroundColor Green

Write-Host "`n--- F-02 DETAIL (remediate first) ---" -ForegroundColor Red
$f02 | Format-Table -AutoSize
Write-Host "--- F-01 DETAIL ---" -ForegroundColor Yellow
$f01 | Sort-Object DaysOrphaned -Descending | Format-Table EmployeeId,Name,JobTitle,TermDate,DaysOrphaned -AutoSize
