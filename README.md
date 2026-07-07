# Enterprise Identity Lifecycle Governance with Microsoft Entra ID
### Detecting and remediating orphaned accounts, privilege creep, and offboarding failures in a regulated healthcare environment

> She was terminated in November. The following July, her account could still sign in, 229 days later. She was not the worst case: a terminated system administrator had retained privileged group membership for 130 days.

This project delivers end to end identity lifecycle governance for MedCare Health Group, a multinational healthcare organization operating under HIPAA, GDPR, and ISO 27001 requirements. It covers the full arc of real Identity and Access Management (IAM) work: a compliance driven access audit, findings with severity ratings and regulatory mappings, governance documentation, automated Role Based Access Control (RBAC) enforcement, Joiner Mover Leaver (JML) lifecycle implementation, and independent verification that every finding was closed.

**Platform:** Microsoft Entra ID, Microsoft Graph PowerShell, PowerShell 7
**Regulatory context:** HIPAA, GDPR, ISO 27001 Annex A.9, NIST SP 800 53 (Access Control family)
**Role performed:** IAM Analyst, end to end (audit, design, implementation, verification)
**Author:** Sime Delonney Njeba, Cybersecurity Analyst | IAM Specialist | CEH v13

## Executive summary

An access audit compared every identity in the MedCare directory against the authoritative HR employment record. The two sources did not agree. Eight former employees retained enabled accounts with working access, including four clinical accounts able to reach the Electronic Health Records (EHR) system and one terminated system administrator holding privileged group membership. Five active employees carried access left over from previous roles. Three identity records were missing attributes required for any automated access decision.

All findings were remediated through policy driven automation: an approved RBAC matrix enforced by a reconciliation engine, a formal JML policy with tiered deprovisioning SLAs, and an ordered leaver runbook. The original audit tooling was then rerun unchanged against the environment and returned zero findings in all four categories.

## Results

| Metric | Before | After |
|---|---|---|
| Orphaned enabled accounts (terminated in HR) | 8, oldest 229 days | 0 |
| Terminated users holding privileged access | 1 (IT Admins, 130 days) | 0 |
| Privilege creep instances (access beyond current role) | 5, including a helpdesk technician in IT Admins | 0 |
| Identity records with incomplete attributes | 3 | 0 |
| Access assignment method | Manual, email driven | Role based, policy driven, automated enforcement |
| Deprovisioning SLA | Undefined | 4 business hours standard, 1 hour privileged, evidenced |
| Verification audit (same tooling as initial audit) | 17 finding instances | 0 findings |

## Scope of work

**Access audit and findings.** Extracted all users and group memberships through Microsoft Graph PowerShell and reconciled them against the authoritative HR feed. Findings were validated through two independent methods, a manual spreadsheet join and a scripted analysis, producing identical counts. Each finding carries a severity rating, a risk statement, and a mapping to the specific regulatory control it violates. Full report: [docs/02-audit-findings-report.md](docs/02-audit-findings-report.md)

**Governance design.** Authored the target state access model and the lifecycle policy that governs it. The RBAC design defines an approved role to access matrix built on least privilege, with documented rationale for every access decision including deliberate denials such as billing staff never holding EHR access under the HIPAA minimum necessary standard. The JML policy defines triggers, ownership, ordered procedures, tiered SLAs, exception handling, and audit logging for every lifecycle event. Documents: [docs/03-rbac-design.md](docs/03-rbac-design.md), [docs/04-jml-policy.md](docs/04-jml-policy.md)

**RBAC enforcement automation.** Built a reconciliation engine that compares every active user's actual group memberships against the approved matrix, removes excess access, adds missing access, and writes every change to a timestamped log citing the governing policy document. The engine supports a report only mode so every enforcement run is reviewed as a plan before execution. This closed all five privilege creep findings in a single governed run and now operates as the recurring access review tool. Script: [scripts/access-reconciliation.ps1](scripts/access-reconciliation.ps1)

**Mover workflow.** Executed an internal transfer scenario in which a nurse moved into a billing role. The HR attribute change drove automatic recalculation of access: clinical access removed and billing access granted the same day, within the policy SLA, fully logged. The same mechanism that remediated historical privilege creep now prevents new creep at the moment a role changes.

**Leaver runbook.** Implemented the ordered deprovisioning procedure from the JML policy: disable the account, revoke all active sessions, record and then remove every group membership, and log each action with timestamps, the executing identity, and the policy reference. Privileged accounts are processed first under the stricter SLA. This closed all eight orphaned accounts, including the critical privileged case. Script: [scripts/leaver-runbook.ps1](scripts/leaver-runbook.ps1)

**Independent verification.** Reran the original audit tooling, unchanged, against the remediated environment. Result: zero findings across all four categories. The same test that failed the environment now certifies it. Evidence: [evidence/07-post-remediation](evidence/07-post-remediation)

## Compliance mapping

| Finding category | Controls implicated |
|---|---|
| Orphaned accounts and privileged orphan | HIPAA 164.308(a)(3)(ii)(C) termination procedures; ISO 27001 A.9.2.6 removal of access rights; GDPR Article 32 security of processing |
| Privilege creep | ISO 27001 A.9.2.5 review of user access rights; HIPAA 164.502(b) minimum necessary standard |
| Identity data quality | ISO 27001 A.9.2.1 user registration and deregistration |

## Skills demonstrated

Identity and Access Management (IAM), Microsoft Entra ID (Azure AD), user lifecycle management, provisioning and deprovisioning, Joiner Mover Leaver (JML) workflows, Role Based Access Control (RBAC), least privilege enforcement, access reviews and recertification, privileged access governance, Multi Factor Authentication (MFA), Microsoft Graph PowerShell automation, audit evidence and compliance documentation, HIPAA, GDPR, ISO 27001.

## Engineering lessons

1. **The directory alone looks healthy.** Every finding was invisible until directory state was reconciled against the authoritative HR source. Identity governance is a data reconciliation discipline: the access people have versus the access the source of truth says they should have.
2. **Deprovisioning automation must be idempotent.** The leaver runbook failed mid execution on the first privileged account, leaving it disabled but still holding admin group membership. A naive rule of skipping disabled accounts would have concealed that residual access permanently. The fix defines completion by end state, disabled with zero memberships, never by a single flag.
3. **Enforcement follows policy.** Every automated change cites the governing document in its log entry. Automation without governance is opinion running at scale.
4. **Plan before execution.** Both enforcement tools run in report only mode first. Access removal is never executed without a reviewed plan.
5. **Authentication friction is core IAM work.** Real issues were diagnosed and resolved during delivery, including the Graph SDK crashing Windows PowerShell 5.1, script blocking by mark of the web, sign in windows hidden by Web Account Manager, and duplicate device code prompts. Understanding how authentication flows fail is part of the job, not a distraction from it.
6. **Scaling path.** At full enterprise scale this design maps directly to HR driven provisioning through SCIM, Entra Lifecycle Workflows and dynamic groups, and Identity Governance and Administration platforms such as SailPoint and Saviynt, which industrialize the same JML, reconciliation, and certification loop implemented here.

## Repository structure

```
docs/          audit findings report, RBAC design, JML policy
scripts/       environment setup, audit analysis, reconciliation engine, leaver runbook
data/          HR feed used as the authoritative identity source
evidence/      timestamped logs, exports, and screenshots for every phase
```

## Integrity note

MedCare Health Group is a fictional organization created for this project and all identities are fictional. The platform, the automation, the governance documents, the failures encountered, and the evidence produced are real. The environment was built deliberately broken, audited, remediated, and verified to the standard expected of enterprise IAM delivery.

**Next in this series:** Cloud IAM Policy Design on AWS, in which MedCare's cloud migration exposes over permissive IAM roles.
