<#
.SYNOPSIS
    MedCare IAM Lab - Phase 6: Leaver Runbook
.DESCRIPTION
    Executes the leaver procedure from the JML policy (MC-IAM-2026-003, section 5)
    against every user marked Terminated in the HR feed whose account is still enabled:
      1. Disable the account
      2. Revoke all active sessions
      3. Record, then remove, ALL group memberships
      4. Log every step with timestamps
    PRIVILEGED accounts (members of IT-Admins) are processed FIRST, per policy.
    Closes audit findings F-01 and F-02.
.EXAMPLE
    .\leaver-runbook.ps1 -ReportOnly    # list who would be processed, touch nothing
    .\leaver-runbook.ps1                # execute the leaver procedure
.NOTES
    Requires: Microsoft.Graph.Authentication, .Users, .Groups + Users.Actions | PowerShell 7
    Author: Sime Delonney Njeba | Identity Lifecycle Governance Lab
#>

param(
    [switch]$ReportOnly
)

# ============ CONFIG ============
$HrFeed  = "C:\medcare-iam-lab\data\medcare-hr-feed.csv"
$LogDir  = "C:\medcare-iam-lab\evidence\06-leaver"
$Domain  = "Simedelonneynjebagmail.onmicrosoft.com"
$PrivilegedGroups = @("IT-Admins")
# ================================

$ErrorActionPreference = "Stop"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$logCsv = Join-Path $LogDir "leaver-log.csv"
$mode = if ($ReportOnly) { "REPORT-ONLY" } else { "EXECUTE" }

Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All" -NoWelcome
Write-Host "Connected. Mode: $mode`n" -ForegroundColor Cyan

# 1. Identify leavers: Terminated in HR
$hr = Import-Csv $HrFeed
$terminated = $hr | Where-Object Status -eq "Terminated"

# 2. Build the work list: terminated users whose accounts are still ENABLED
$work = @()
foreach ($t in $terminated) {
    $nick = ("$($t.FirstName).$($t.LastName)").ToLower() -replace '[^a-z0-9.]',''
    $upn = "$nick@$Domain"
    $u = Get-MgUser -Filter "userPrincipalName eq '$upn'" -Property Id,DisplayName,UserPrincipalName,AccountEnabled,EmployeeId -ErrorAction SilentlyContinue
    if (-not $u) { Write-Warning "Not found in directory: $upn"; continue }
    $memberships = Get-MgUserMemberOf -UserId $u.Id -All |
                   ForEach-Object { $_.AdditionalProperties['displayName'] } |
                   Where-Object { $_ }

    # Skip ONLY if fully processed: disabled AND holding zero memberships.
    # A disabled account that still has group memberships is a partially executed
    # leaver (e.g. an interrupted runbook) and MUST be re-processed.
    if (-not $u.AccountEnabled -and -not $memberships) {
        Write-Host "Already fully processed: $($u.DisplayName)" -ForegroundColor DarkGray; continue
    }
    $isPrivileged = [bool]($memberships | Where-Object { $_ -in $PrivilegedGroups })

    $work += [pscustomobject]@{
        User = $u; TermDate = $t.TermDate; EmployeeId = $t.EmployeeID
        Memberships = $memberships; Privileged = $isPrivileged
    }
}

# 3. Privileged accounts FIRST (JML policy section 5: 1-hour SLA vs 4-hour standard)
$work = $work | Sort-Object { -not $_.Privileged }

Write-Host "Leavers to process: $($work.Count)  (privileged first)`n" -ForegroundColor Cyan
foreach ($w in $work) {
    $tag = if ($w.Privileged) { "[PRIVILEGED]" } else { "" }
    Write-Host ">>> $($w.User.DisplayName) $tag  terminated $($w.TermDate)  groups: $($w.Memberships -join ', ')" -ForegroundColor $(if ($w.Privileged) { "Red" } else { "Yellow" })

    if ($ReportOnly) { continue }

    # STEP 1: Disable (idempotent - safe if a prior interrupted run already disabled it)
    if ($w.User.AccountEnabled) {
        Update-MgUser -UserId $w.User.Id -AccountEnabled:$false
        Write-Host "    1. Account disabled" -ForegroundColor Green
    } else {
        Write-Host "    1. Account already disabled (interrupted prior run) - continuing" -ForegroundColor Yellow
    }

    # STEP 2: Revoke sessions
    Revoke-MgUserSignInSession -UserId $w.User.Id | Out-Null
    Write-Host "    2. Sessions revoked" -ForegroundColor Green

    # STEP 3: Strip memberships (recorded above, removed here)
    $removed = 0
    $groups = Get-MgUserMemberOf -UserId $w.User.Id -All
    foreach ($g in $groups) {
        try {
            Remove-MgGroupMemberByRef -GroupId $g.Id -DirectoryObjectId $w.User.Id -ErrorAction Stop
            $removed++
        } catch { Write-Warning "    Could not remove from $($g.AdditionalProperties['displayName']): $($_.Exception.Message)" }
    }
    Write-Host "    3. $removed group membership(s) removed" -ForegroundColor Green

    # STEP 4: Log
    [pscustomobject]@{
        Timestamp        = Get-Date -Format o
        Action           = "LEAVER-EXECUTED"
        User             = $w.User.UserPrincipalName
        EmployeeId       = $w.EmployeeId
        TermDate         = $w.TermDate
        Privileged       = $w.Privileged
        MembershipsPrior = ($w.Memberships -join "; ")
        GroupsRemoved    = $removed
        ExecutedBy       = (Get-MgContext).Account
        PolicyRef        = "MC-IAM-2026-003 s.5"
    } | Export-Csv $logCsv -NoTypeInformation -Append
    Write-Host "    4. Logged`n" -ForegroundColor Green
}

if ($ReportOnly) {
    Write-Host "`nREPORT-ONLY: nothing was changed. Re-run without -ReportOnly to execute." -ForegroundColor Yellow
} else {
    Write-Host "Leaver runbook complete. $($work.Count) account(s) processed. Log: $logCsv" -ForegroundColor Cyan
    Write-Host "Accounts remain disabled in 30-day retention per policy, with ZERO memberships." -ForegroundColor Cyan
}
