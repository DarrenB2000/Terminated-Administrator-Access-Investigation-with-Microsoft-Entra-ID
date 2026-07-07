# Role-Based Access Control (RBAC) Design
**MedCare Health Group — Target-State Access Model**

| | |
|---|---|
| Document ID | MC-IAM-2026-002 |
| Author | Sime Delonney Njeba, IAM Analyst |
| Status | Approved design — implementation in progress |
| Related | Audit report MC-IAM-2026-001 (recommendation R3) |

---

## 1. Purpose

The access audit (MC-IAM-2026-001) found that access at MedCare is assigned manually, person by person, with no defined standard for what any role should have. This produced privilege creep (F-03) and made access reviews impossible — there was nothing to review against.

This document defines the standard: for every job role, exactly which access is approved. From implementation onward, access is granted by role, not by request, and anything outside this matrix is an exception requiring documented approval.

## 2. Design principles

1. **Least privilege** — each role receives the minimum access required to perform the job. Nothing is inherited from previous roles, seniority, or convenience.
2. **Access follows the role, not the person** — users are never added directly to application groups. They hold a role; the role carries the access. When the role changes, the access changes with it.
3. **One authoritative source** — the HR record (department + job title) determines the role. If HR data is wrong, the fix is in HR data, not a manual group-add.
4. **Privileged access is separate and explicit** — IT-Admins is not an application group. Membership requires a privileged role, and it is the first target of every review cycle.

## 3. Role-to-access matrix

| Role | Department | EHR | Billing | Finance | Admin Portal | HRIS | Scheduling | IT-Admins |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Nurse | Clinical | ✔ | – | – | – | – | ✔ | – |
| Physician | Clinical | ✔ | – | – | – | – | ✔ | – |
| Billing Specialist | Billing & Finance | – | ✔ | – | – | – | – | – |
| Finance Analyst | Billing & Finance | – | – | ✔ | – | – | – | – |
| Helpdesk Technician | IT | – | – | – | ✔ | – | – | – |
| System Administrator | IT | – | – | – | ✔ | – | – | ✔ |
| HR Coordinator | HR | – | – | – | – | ✔ | – | – |
| Receptionist | Administration | – | – | – | – | – | ✔ | – |
| Office Manager | Administration | – | – | – | – | – | ✔ | – |

Notes on deliberate decisions:
- **Clinical roles** get EHR + Scheduling only. No clinical role has any business or administrative system access.
- **Billing Specialist does NOT get EHR.** Billing works from coded claims data in the billing system, not from the clinical record. This is the HIPAA minimum-necessary standard applied — and it is exactly the F-03 case found in the audit (Hannah Anderson).
- **Finance Analyst does NOT get Billing.** Finance consumes reports, not raw billing operations. (Audit case: Noah Kowalski.)
- **Helpdesk gets Admin Portal but NOT IT-Admins.** Password resets and ticket handling do not require directory-wide administrative rights. (Audit case: Liam Petrov — critical.)

## 4. Enforcement mechanism

Access is computed from directory attributes (department, jobTitle), which mirror the HR feed:

- **Primary (implemented):** a PowerShell reconciliation script (access-reconciliation.ps1) compares every active user's actual group memberships against this matrix and corrects drift — removing excess access, adding missing access, and logging every change. Run on demand and on a schedule.
- **Platform-native (variant):** Entra ID dynamic groups with membership rules on department + jobTitle, mapped to the application groups. Same logic, evaluated continuously by the platform. Documented as an alternative implementation.

Precondition: attribute completeness. The audit's F-04 finding (3 users with missing Department) must be corrected before any attribute-driven enforcement runs, otherwise those users would be silently stripped of all access.

## 5. Exceptions

Any access outside this matrix requires: a documented business justification, an owner, an expiry date, and appears automatically in every access review. No permanent exceptions.

## 6. Review

- IT-Admins membership: reviewed quarterly.
- All application groups: reviewed semi-annually.
- The review compares live memberships against this matrix; the audit script from MC-IAM-2026-001 is reused as the review tool.
