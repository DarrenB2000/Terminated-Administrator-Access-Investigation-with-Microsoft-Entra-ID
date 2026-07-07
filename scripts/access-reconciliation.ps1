<#
.SYNOPSIS
    MedCare IAM Lab - Phase 4: Access Reconciliation (RBAC enforcement)
.DESCRIPTION
    Enforces the approved role-to-access matrix (MC-IAM-2026-002) for all ACTIVE users:
      - Computes each user's EXPECTED groups from their jobTitle
      - Compares against ACTUAL group memberships
      - REMOVES excess access (privilege creep - closes audit finding F-03)
      - ADDS missing access (users under-provisioned relative to their role)
      - Logs every change with timestamp, user, group, action, and reason
    Terminated-in-HR users are NOT handled here - that is the leaver runbook's job
    (Phase 6). This script only reconciles active workforce access.
    Supports -WhatIf style dry run via -ReportOnly.
.EXAMPLE
    .\access-reconciliation.ps1 -ReportOnly    # show what WOULD change, touch nothing
    .\access-reconciliation.ps1                # enforce the matrix for real
.NOTES
    Requires: Microsoft.Graph.Authentication, .Users, .Groups | PowerShell 7
    Author: Sime Delonney Njeba | Identity Lifecycle Governance Lab
#>

param(
    [switch]$ReportOnly
)

# ============ CONFIG ============
$HrFeed = "C:\medcare-iam-lab\data\medcare-hr-feed.csv"
$LogDir = "C:\medcare-iam-lab\evidence\04-joiner"   # reconciliation evidence lives with Phase 4
$ManagedGroups = @(
    "APP-EHR-Users","APP-Billing-Users","APP-Finance-Users",
    "APP-AdminPortal-Users","APP-HRIS-Users","APP-Scheduling-Users","IT-Admins"
)
# ================================

# The approved matrix - MUST match docs/03-rbac-design.md
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

$ErrorActionPreference = "Stop"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$logFile = Join-Path $LogDir "reconciliation-log.csv"
$mode = if ($ReportOnly) { "REPORT-ONLY" } else { "ENFORCE" }

Connect-MgGraph -Scopes "User.Read.All","Group.ReadWrite.All" -NoWelcome
Write-Host "Connected. Mode: $mode`n" -ForegroundColor Cyan

# Resolve managed group IDs once
$groupIds = @{}
foreach ($name in $ManagedGroups) {
    $g = Get-MgGroup -Filter "displayName eq '$name'"
    if (-not $g) { throw "Managed group not found: $name" }
    $groupIds[$name] = $g.Id
}

# HR feed: only ACTIVE employees are reconciled
$hr = Import-Csv $HrFeed
$activeIds = ($hr | Where-Object Status -eq "Active").EmployeeID

$changes = @()
$users = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,JobTitle,EmployeeId,AccountEnabled |
         Where-Object { $_.EmployeeId -and $_.EmployeeId -in $activeIds }

Write-Host "Reconciling $($users.Count) active users against the RBAC matrix...`n" -ForegroundColor Cyan

foreach ($u in $users) {
    $expected = @()
    if ($roleAccess.ContainsKey($u.JobTitle)) { $expected = $roleAccess[$u.JobTitle] }
    else { Write-Warning "$($u.DisplayName): jobTitle '$($u.JobTitle)' not in matrix - skipping (flag for review)"; continue }

    # Actual memberships within MANAGED groups only
    $memberOf = Get-MgUserMemberOf -UserId $u.Id -All
    $actual = @()
    foreach ($m in $memberOf) {
        $name = $m.AdditionalProperties['displayName']
        if ($name -in $ManagedGroups) { $actual += $name }
    }

    $toRemove = $actual   | Where-Object { $_ -notin $expected }
    $toAdd    = $expected | Where-Object { $_ -notin $actual }

    foreach ($g in $toRemove) {
        Write-Host "REMOVE  $($u.DisplayName) [$($u.JobTitle)]  -x->  $g" -ForegroundColor Red
        if (-not $ReportOnly) {
            Remove-MgGroupMemberByRef -GroupId $groupIds[$g] -DirectoryObjectId $u.Id
        }
        $changes += [pscustomobject]@{
            Timestamp = Get-Date -Format o; Mode = $mode; Action = "REMOVE"
            User = $u.UserPrincipalName; EmployeeId = $u.EmployeeId
            JobTitle = $u.JobTitle; Group = $g
            Reason = "Access not implied by current role (RBAC matrix MC-IAM-2026-002)"
        }
    }
    foreach ($g in $toAdd) {
        Write-Host "ADD     $($u.DisplayName) [$($u.JobTitle)]  -->  $g" -ForegroundColor Green
        if (-not $ReportOnly) {
            New-MgGroupMember -GroupId $groupIds[$g] -DirectoryObjectId $u.Id
        }
        $changes += [pscustomobject]@{
            Timestamp = Get-Date -Format o; Mode = $mode; Action = "ADD"
            User = $u.UserPrincipalName; EmployeeId = $u.EmployeeId
            JobTitle = $u.JobTitle; Group = $g
            Reason = "Role requires access per RBAC matrix MC-IAM-2026-002"
        }
    }
}

if ($changes.Count -eq 0) {
    Write-Host "`nNo drift found. All active users match the RBAC matrix." -ForegroundColor Green
} else {
    $changes | Export-Csv $logFile -NoTypeInformation -Append
    Write-Host "`n$mode complete: $(@($changes | Where-Object Action -eq 'REMOVE').Count) removals, $(@($changes | Where-Object Action -eq 'ADD').Count) additions." -ForegroundColor Cyan
    Write-Host "Change log appended to $logFile" -ForegroundColor Green
}
if ($ReportOnly) { Write-Host "REPORT-ONLY mode: nothing was changed. Re-run without -ReportOnly to enforce." -ForegroundColor Yellow }
