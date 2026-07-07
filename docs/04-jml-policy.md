# Joiner-Mover-Leaver (JML) Policy
**MedCare Health Group — Identity Lifecycle Policy**

| | |
|---|---|
| Document ID | MC-IAM-2026-003 |
| Author | Sime Delonney Njeba, IAM Analyst |
| Status | Active |
| Related | Audit report MC-IAM-2026-001 (recommendation R2), RBAC design MC-IAM-2026-002 |

---

## 1. Purpose and scope

The access audit found 8 former employees with working accounts, one of them a system administrator gone for 130 days. This happened because there was no rule connecting HR events to directory actions. Accounts were created from email requests and removed only if someone remembered.

This policy fixes that. It defines what must happen, who does it, and how fast, every time someone joins MedCare, changes role, or leaves.

It applies to every workforce identity in the MedCare directory. No exceptions for seniority, department, or "temporary" arrangements.

## 2. Roles and responsibilities

- **HR** owns the trigger. Every hire, transfer, and termination must be recorded in the HR system. The HR record is the only valid trigger for any account action. Nobody gets an account, a change, or a removal based on an email or a verbal request.
- **IAM** owns the execution. IAM performs the directory actions within the SLAs below and logs every action with a timestamp.
- **Managers** own attestation. After a transfer, the new manager confirms the access looks right. During access reviews, managers confirm their people's access is still needed.
- If a Mensah case happens again (a terminated user keeps access past SLA), the failure is traced to whichever step broke: no HR record = HR accountability, HR record but no action = IAM accountability.

## 3. Joiner procedure

**Trigger:** HR creates the employment record (name, employee ID, department, job title, start date).

**Steps:**
1. IAM creates the account from the HR record. Only from the HR record — if the data is wrong or missing, it goes back to HR, we do not guess.
2. Access is assigned through role groups per the RBAC matrix (MC-IAM-2026-002). No direct group adds, no extras "because they might need it."
3. Account is created with a temporary password that must be changed at first sign-in.
4. MFA registration is required before the user can access anything. No MFA, no access.

**Timing:** account and access ready by the start date, created no more than 3 business days before it (so accounts don't sit idle and unwatched).

## 4. Mover procedure

**Trigger:** HR updates the employee's department or job title.

**Steps:**
1. Access is recalculated from the new role using the RBAC matrix.
2. New role access is added AND old role access is removed. Both, always, same action. Removing the old access is the whole point — skipping it is how privilege creep happens, and the audit found 5 people carrying old access for exactly this reason.
3. The new manager gets notified and confirms the access is right for the role.

**SLA:** old access removed within 1 business day of the HR change.

## 5. Leaver procedure

**Trigger:** HR records the termination.

**Steps, in this order:**
1. Disable the account.
2. Revoke all active sessions (so an open laptop or logged-in phone dies too — disabling alone does not kill live sessions).
3. Remove all group memberships. Record what they were first, for the audit trail.
4. Log every step with a timestamp and who did it.

**SLA:**
- Standard accounts: within **4 business hours** of the HR termination record.
- Privileged accounts (IT-Admins or any admin role): **immediately, within 1 hour**, and these are done first. Reason: a leftover receptionist account is a problem, a leftover admin account is a disaster. The audit proved both exist, but they are not the same size of risk.

**Retention:** disabled accounts are kept 30 days (in case of legal hold, mailbox handover, or rehire), then deleted. A disabled account in retention has zero group memberships — retention means the object exists, not that access exists.

## 6. Exceptions and audit

- Any access outside the RBAC matrix follows the exception rules in MC-IAM-2026-002: written justification, an owner, an expiry date. No permanent exceptions.
- Every JML action is logged: what was done, to whom, when, by whom, triggered by which HR event.
- Logs feed the access reviews: IT-Admins quarterly, all application groups semi-annually.
- The audit script from MC-IAM-2026-001 is re-run as part of every review. If it ever finds an enabled account for a terminated employee again, that is an SLA breach and gets investigated, not just fixed quietly.
