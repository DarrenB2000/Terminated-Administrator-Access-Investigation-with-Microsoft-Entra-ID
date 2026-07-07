<#
.SYNOPSIS
    MedCare Health Group IAM Lab - Phase 1: Build the Broken State
.DESCRIPTION
    Creates 7 app/security groups, provisions 40 users from the HR feed CSV,
    and assigns group memberships INCLUDING the deliberately seeded problems:
      - 8 terminated users created ENABLED with access intact (orphaned accounts)
      - 5 privilege-creep users holding access from previous roles
      - 3 users with missing department attributes (data hygiene failures)
    This represents the ungoverned "before" state that the audit (Phase 2) will expose.
.NOTES
    Run in Windows PowerShell 5.1+ as a normal user (not elevated).
    Requires: Microsoft.Graph.Authentication, .Users, .Groups modules.
    Author: Sime Delonney Njeba | Identity Lifecycle Governance Lab
#>

# ============ CONFIG - EDIT THESE TWO LINES ============
$Domain  = "Simedelonneynjebagmail.onmicrosoft.com"   # your tenant domain
$CsvPath = "C:\medcare-iam-lab\data\medcare-hr-feed.csv"  # where you saved the HR feed
# =======================================================

$ErrorActionPreference = "Stop"
$log = @()

# ---------- 1. CONNECT ----------
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All" -NoWelcome
Write-Host "Connected as: $((Get-MgContext).Account)" -ForegroundColor Green

# ---------- 2. CREATE GROUPS ----------
$groupNames = @(
    "APP-EHR-Users","APP-Billing-Users","APP-Finance-Users",
    "APP-AdminPortal-Users","APP-HRIS-Users","APP-Scheduling-Users","IT-Admins"
)
$groups = @{}
foreach ($name in $groupNames) {
    $existing = Get-MgGroup -Filter "displayName eq '$name'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Group exists: $name" -ForegroundColor Yellow
        $groups[$name] = $existing.Id
    } else {
        $g = New-MgGroup -DisplayName $name `
                         -MailEnabled:$false `
                         -MailNickname ($name.ToLower() -replace '[^a-z0-9]','') `
                         -SecurityEnabled:$true `
                         -Description "MedCare lab - represents access to $name"
        $groups[$name] = $g.Id
        Write-Host "Created group: $name" -ForegroundColor Green
    }
}

# ---------- 3. ROLE -> BASE ACCESS MATRIX (the access each CURRENT role implies) ----------
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

# ---------- 4. SEEDED EXTRA ACCESS (the privilege creep - EmployeeID -> extra groups) ----------
$seededCreep = @{
    "MC1011" = @("APP-EHR-Users")        # Hannah Anderson - former Nurse
    "MC1016" = @("APP-Billing-Users")    # Noah Kowalski - former Billing
    "MC1020" = @("IT-Admins")            # Liam Petrov - former SysAdmin
    "MC1025" = @("APP-Scheduling-Users") # Nadia Ali - former Receptionist
    "MC1030" = @("APP-HRIS-Users")       # Ryan Walsh - former HR temp cover
}

# ---------- 5. CREATE USERS FROM HR FEED ----------
$users = Import-Csv $CsvPath
Write-Host "`nProvisioning $($users.Count) users..." -ForegroundColor Cyan

foreach ($u in $users) {
    $mailNick = ("$($u.FirstName).$($u.LastName)").ToLower() -replace '[^a-z0-9.]',''
    $upn = "$mailNick@$Domain"

    # Skip if already exists (lets you re-run the script safely)
    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) { Write-Host "Exists, skipping: $upn" -ForegroundColor Yellow; $userId = $existing.Id }
    else {
        $params = @{
            AccountEnabled    = $true    # BROKEN STATE: even Terminated users are enabled
            DisplayName       = "$($u.FirstName) $($u.LastName)"
            MailNickname      = $mailNick
            UserPrincipalName = $upn
            JobTitle          = $u.JobTitle
            EmployeeId        = $u.EmployeeID
            PasswordProfile   = @{
                Password = "TempMC!$(Get-Random -Minimum 10000 -Maximum 99999)"
                ForceChangePasswordNextSignIn = $true
            }
        }
        # Data hygiene seed: only set Department if HR actually recorded one
        if (-not [string]::IsNullOrWhiteSpace($u.Department)) { $params.Department = $u.Department }

        $newUser = New-MgUser @params
        $userId = $newUser.Id
        Write-Host "Created: $($u.EmployeeID) $($u.FirstName) $($u.LastName) [$($u.Status)]" -ForegroundColor Green
    }

    # ---------- 6. ASSIGN GROUPS (base access by role + seeded creep) ----------
    $targetGroups = @()
    if ($roleAccess.ContainsKey($u.JobTitle)) { $targetGroups += $roleAccess[$u.JobTitle] }
    if ($seededCreep.ContainsKey($u.EmployeeID)) { $targetGroups += $seededCreep[$u.EmployeeID] }

    foreach ($gName in ($targetGroups | Select-Object -Unique)) {
        try {
            New-MgGroupMember -GroupId $groups[$gName] -DirectoryObjectId $userId -ErrorAction Stop
            Write-Host "   -> added to $gName" -ForegroundColor DarkGray
        } catch {
            if ($_.Exception.Message -match "already exist") {
                Write-Host "   -> already in $gName" -ForegroundColor DarkGray
            } else { Write-Warning "   -> FAILED adding to ${gName}: $($_.Exception.Message)" }
        }
    }

    $log += [pscustomobject]@{
        Timestamp  = (Get-Date -Format o)
        EmployeeID = $u.EmployeeID
        UPN        = $upn
        Status     = $u.Status
        Enabled    = $true
        Groups     = ($targetGroups | Select-Object -Unique) -join "; "
        SeededNote = $u.Notes
    }
}

# ---------- 7. WRITE PROVISIONING LOG (evidence artifact) ----------
$logPath = Split-Path $CsvPath -Parent
$log | Export-Csv "$logPath\..\evidence\01-baseline\provisioning-log.csv" -NoTypeInformation
Write-Host "`nDone. Provisioning log written to evidence\01-baseline\provisioning-log.csv" -ForegroundColor Cyan
Write-Host "Broken state summary: $($users.Count) users created; $(( $users | Where-Object Status -eq 'Terminated').Count) of them are TERMINATED but still ENABLED with access." -ForegroundColor Red
