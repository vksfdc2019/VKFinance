# Architecture review — Owner Workspace

## The need

The platform owner wants to look after families from a phone: pick a family, see where it stands, and record or correct money movements. Families use the React portal on Experience Cloud with their own sign-in. The owner is a Salesforce user, so the natural home is the Salesforce mobile app, not the portal.

## Options considered

| Option                                                                            | Verdict             | Why                                                                                                                                                                                                                                   |
| --------------------------------------------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A. Standard record pages** (Transaction, Bill, Loan tabs on the phone)          | Rejected for writes | Skips the service rules. A transfer is two linked rows; paying a bill posts ledger entries; voiding a payment re-opens the bill or EMI. Editing one record directly breaks these. The trigger keeps balances right, but nothing else. |
| **B. Wrap the React portal in the mobile app**                                    | Rejected            | The portal depends on the custom portal session (`X-VKF-Session`) and the site guest user. The owner would need a portal login per family, and nothing would be audited as the owner.                                                 |
| **C. Native app with the Mobile SDK**                                             | Rejected for now    | A separate app to build, sign and distribute for one user. The Salesforce mobile app already provides sign-in, biometrics, push and distribution.                                                                                     |
| **D. LWC workspace in the Console + an owner context over the existing services** | **Chosen**          | Free, uses Salesforce sign-in and MFA, works on phone and desktop, and every write goes through the same services as the portal.                                                                                                      |

## Design

```mermaid
flowchart TD
  Phone[Salesforce mobile app / desktop] --> Tab[Owner Workspace tab<br/>VK Finance Console]
  Tab --> LWC[vkfOwnerWorkspace + 5 section components]
  LWC -->|@AuraEnabled, JSON| Ctrl[VkfOwnerController<br/>with sharing]
  Ctrl --> Gate[OwnerContext.forFamily<br/>custom permission check]
  Gate -->|Family Admin context<br/>family read from the database| Services[Existing services<br/>Transaction, Transfer, Bill, Loan,<br/>Budget, Dashboard, Dues, Member]
  Gate -->|tags the request| Audit[AuditService<br/>'[Owner userId]' on every event]
  Services --> Ledger[(Ledger objects + LedgerBalances trigger)]
```

### Key decisions

1. **Act as the family's admin, through the services.** `OwnerContext.forFamily` builds the same `UserContext` the portal builds after sign-in, from the family's active Family Admin (or invited admin if none is active). The role, the family and the scope come from the database, never from the browser. Every service applies its normal checks (`AccessGuard`, `LedgerScope`, `FamilyScopedSelector`), so the owner can do exactly what that family's admin can do — no more.
2. **Permission first, every call.** Every controller method passes through `OwnerContext`, which calls `FeatureManagement.checkPermission('VKF_Platform_Admin')` before anything else. Without the `VKF_Platform_Admin` permission set nothing is returned.
3. **The audit trail names the owner.** `OwnerContext` sets `AuditService.actingOwnerId` for the request. Every audit event raised in that request — including events raised deep inside services — gets `[Owner <Salesforce user id>]` at the start of its details. The actor stays the family admin's portal user, so the event still belongs to the family, but nobody can mistake the change for the admin's own.
4. **Suspended families are read-only.** Reads work so the owner can investigate; any write returns "This family is suspended".
5. **One response shape.** The controller returns JSON strings in exactly the portal REST shape. The service DTOs did not need `@AuraEnabled` copies, and the screens and the portal read the same data.
6. **No new data.** No objects or fields were added, so the 5 MB storage limit is not affected.

## Security review

| Concern                                          | Control                                                                                                                                                                |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Someone other than the owner opens the tab       | Tab, app and Apex class are granted only by `VKF_Platform_Admin`; every method re-checks the custom permission                                                         |
| A tampered request names another family's record | Records are always looked up within the context's family; other families' records are not found                                                                        |
| Client chooses the role or scope                 | Role and family come from the admin's database record                                                                                                                  |
| Sign-in strength                                 | Salesforce sign-in; turn on Salesforce MFA for the owner user (see the implementation guide)                                                                           |
| Error details leak internals                     | Service messages are passed through; any other error becomes "Something went wrong. Please try again." and the detail goes only to the debug log                       |
| Families can't tell the owner acted              | Audit events carry the owner tag; ledger entries are created normally and appear in the family's ledger                                                                |
| Step-up checks (password + code)                 | Not used on this path. The member actions that need them (password resets, MFA resets, role changes) are deliberately **not** exposed; the Family section is read-only |

## What is deliberately out of scope (v1)

- Member management (roles, unlocks, password and MFA resets) — stays in the portal behind step-up checks.
- Card bill payment from the Dues list — record it as a transfer to the card.
- Creating bills, loans, budgets, categories or accounts — use the portal.
- Offline use — custom Apex screens in the Salesforce app need a connection.

## Risks and follow-ups

| Risk                                                                | Mitigation / next step                                                                                                      |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| A family without an active or invited Family Admin cannot be opened | Shown as "That family has no Family Admin to act as." Reactivate or add an admin first                                      |
| Future services that read `ctx.sessionId`                           | Today only sign-in and profile code reads it, and those are not exposed. New owner methods must avoid session-only services |
| `AuditService.actingOwnerId` is a request-wide static               | Set only by `OwnerContext`; each Lightning request is its own transaction, so it cannot leak between users                  |
| LWC behaviour differs on a real phone (modals, date pickers)        | Physical device check after deployment                                                                                      |
| Code Analyzer not run (CLI plugin could not install)                | Install `sf plugins install code-analyzer` and run it before go-live                                                        |

## Recommended next phases

1. **Quick action "Add entry"** on the Salesforce app action bar.
2. **Owner push notifications** with `Messaging.CustomNotification` from the nightly jobs (failed jobs, reconciliation drift, large transactions).
3. **Edit transaction** (the service supports it; the form needs an edit mode).
4. **Pay card bills** through `BillService.recordCardPayment`.
