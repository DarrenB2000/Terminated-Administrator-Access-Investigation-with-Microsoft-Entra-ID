# Access Audit Findings Report
**MedCare Health Group — Identity & Access Review**

| | |
|---|---|
| Report ID | MC-IAM-2026-001 |
| Author | Sime Delonney Njeba, IAM Analyst |
| Audit date | July 7, 2026 |
| Scope | All workforce identities and access groups, MedCare Entra ID tenant |
| Status | Findings confirmed — remediation in progress |

---

## 1. Executive Summary

This review compared every user account in the MedCare directory against the HR system's employment records. The two did not match.

Eight former employees — terminated between November 2025 and April 2026 — still have enabled accounts with working access. The worst case is a system administrator, terminated 130 days ago, who still holds membership in the IT-Admins group. If his credentials were used today, by him or by anyone who compromised them, that person would have administrative control of the environment. Another account, a billing specialist terminated in November 2025, has been sitting enabled for 229 days.

On top of the orphaned accounts, five current employees hold access left over from previous roles, including a helpdesk technician with admin group membership and a billing specialist who can still open patient records from her time as a nurse. Three user records are missing basic attributes like department, which blocks any attempt to automate access decisions.

The root cause is the same for all of it: there is no process connecting HR events (hire, transfer, termination) to directory actions. Accounts are created and changed manually, and nothing is ever removed unless someone remembers. The recommendations in section 4 fix this with a formal joiner-mover-leaver process.

---

## 2. Scope and Methodology

**What was reviewed:** all 40 workforce user accounts and all 7 access groups (6 application groups plus the privileged IT-Admins group) in the MedCare Health Group Entra ID tenant.

**Source of truth:** the HR employment feed (medcare-hr-feed.csv). The directory tells you what access people HAVE. Only HR tells you what access they SHOULD have. Every finding in this report comes from comparing the two.

**How the data was collected:**
1. Exported all users with their enabled/disabled state and identity attributes via Microsoft Graph PowerShell
2. Exported the membership of every access group the same way
3. Cross-referenced both exports against the HR feed on EmployeeID

**Validation:** the analysis was done twice with independent methods — manually in Excel (VLOOKUP join + filtering) and programmatically with a PowerShell script (audit-analysis.ps1, in this repo). Both methods produced identical counts. Raw exports, the findings CSVs, and the script are all in the evidence folder.

---

## 3. Findings

### F-01 — Orphaned accounts (8 users) — Severity: HIGH

Eight users marked **Terminated** in HR still have **enabled** accounts with their group memberships intact:

| EmployeeID | Name | Former role | Terminated | Days orphaned |
|---|---|---|---|---|
| MC1013 | Julia Rossi | Billing Specialist | 2025-11-20 | 229 |
| MC1027 | Chloe Ortega | Receptionist | 2025-12-05 | 214 |
| MC1004 | Daniel Silva | Nurse | 2026-01-15 | 173 |
| MC1008 | Tom Reyes | Physician | 2026-02-03 | 154 |
| MC1022 | Peter Mensah | System Administrator | 2026-02-27 | 130 |
| MC1019 | Yuki Smith | Helpdesk Technician | 2026-03-10 | 119 |
| MC1037 | Ines Ramos | Physician | 2026-03-22 | 107 |
| MC1032 | Samuel Owusu | Nurse | 2026-04-01 | 97 |

Four of these (Silva, Reyes, Ramos, Owusu) are clinical accounts with EHR access — meaning former employees can still reach patient records.

**Risk:** an ex-employee, or an attacker who gets hold of these dormant credentials, signs in with legitimate access that nobody is watching. Dormant accounts are attractive targets precisely because no active employee will notice anything odd about their own account.

**Compliance:** HIPAA §164.308(a)(3)(ii)(C) requires procedures for terminating access when employment ends — this is a direct failure. Also ISO 27001 Annex A.9.2.6 (removal of access rights on termination) and GDPR Art. 32 (appropriate security of personal data — for the EHR-connected accounts of EU patients).

**Evidence:** F01-orphaned-accounts.csv; f01-orphans-excel-view.png

### F-02 — Terminated user with privileged access (1 user) — Severity: CRITICAL

Peter Mensah (MC1022), System Administrator, terminated 2026-02-27, retains membership in **IT-Admins** with an enabled account. This is the single most serious finding: 130 days of standing administrative access held by someone no longer employed here.

**Risk:** full administrative compromise of the environment through one dormant credential. This is a breach-headline scenario, not a hygiene issue.

**Compliance:** same clauses as F-01, aggravated by the privileged scope. Privileged access is exactly where termination procedures must work first and fastest.

**Evidence:** F02-privileged-orphans.csv; 03-it-admins-before.png

### F-03 — Privilege creep (5 users) — Severity: MEDIUM to CRITICAL

Five active employees hold access their current role does not justify — leftovers from previous roles that were never removed when they moved:

| EmployeeID | Name | Current role | Excess access | Severity |
|---|---|---|---|---|
| MC1020 | Liam Petrov | Helpdesk Technician | IT-Admins | CRITICAL |
| MC1011 | Hannah Anderson | Billing Specialist | APP-EHR-Users | Medium |
| MC1016 | Noah Kowalski | Finance Analyst | APP-Billing-Users | Medium |
| MC1025 | Nadia Ali | HR Coordinator | APP-Scheduling-Users | Medium |
| MC1030 | Ryan Walsh | Office Manager | APP-HRIS-Users | Medium |

Petrov's case is critical for the same reason as F-02: admin membership without an admin role. Anderson's case matters for a different reason — she can open patient records with no clinical duty, which is a least-privilege and HIPAA minimum-necessary problem.

**Risk:** every unnecessary entitlement widens the blast radius of a compromised account, and access nobody remembers granting is access nobody thinks to review.

**Compliance:** ISO 27001 A.9.2.5 (regular review of user access rights); HIPAA minimum necessary standard §164.502(b) for the EHR case.

**Evidence:** F03-privilege-creep.csv

### F-04 — Identity data hygiene (3 users) — Severity: MEDIUM

Three active users have no Department attribute in the directory: Victor Sato (MC1034), Felix Volkov (MC1038), Hugo Doyle (MC1040).

This looks minor next to the other findings but it blocks the fix: any attribute-driven access model (dynamic groups, automated provisioning) decides access based on these attributes. Empty attributes mean these users would silently receive no access — or wrong access — the moment automation is turned on.

**Risk:** broken automation, unreliable reporting, and audit answers ("who has access to X and why") that can't be trusted.

**Compliance:** ISO 27001 A.9.2.1 (formal user registration process).

**Evidence:** F04-data-hygiene.csv

---

## 4. Recommendations

Priority order:

1. **R1 — Immediate remediation (this week).** Disable and strip access from the F-02 account first, then all remaining F-01 accounts: disable, revoke sessions, remove all group memberships, document each action with timestamps. Remove the five F-03 excess entitlements. Correct the three F-04 attribute gaps.
2. **R2 — Establish a formal JML process.** A written joiner-mover-leaver policy, jointly owned by HR and IAM: accounts created only from HR records, access recalculated on transfer, termination triggering same-day disablement with a defined SLA.
3. **R3 — Move to role-based, attribute-driven access.** Define a role-to-access matrix and assign access through role groups driven by directory attributes, so a change in HR data automatically corrects access. Removes the human memory dependency that caused F-01 and F-03.
4. **R4 — Recurring access reviews.** Quarterly recertification of privileged groups, semi-annual for application groups, so drift gets caught even when process fails.

Remediation of R1 begins immediately; R2–R3 are the subject of the next phase of this project. Post-remediation verification will re-run this same audit and publish before/after results.

---

*All evidence referenced in this report is available in the /evidence directory of this repository. Names and identifiers are fictional; the environment is a lab simulation built to enterprise governance standards.*
