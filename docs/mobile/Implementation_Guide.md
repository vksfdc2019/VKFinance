# Implementation guide — Owner Workspace

## Before you start

- Salesforce CLI connected to the `VKFinance` org (alias `VKFINANCE`).
- Your Salesforce user has (or will get) the `VKF_Platform_Admin` permission set.
- The Salesforce mobile app installed on your phone and signed in to the same org.

## 1. Validate, then deploy

The change set is small and adds no objects or fields. Classes used by scheduled jobs (`UserContext`, `AuditService`) can't deploy while those jobs are scheduled, so unschedule first, as for any release.

```bash
# Check only: compiles everything and runs all local tests, saves nothing
sf project deploy start --dry-run --target-org VKFINANCE --test-level RunLocalTests --wait 30 \
  --source-dir force-app/main/default/classes/OwnerContext.cls \
  --source-dir force-app/main/default/classes/VkfOwnerController.cls \
  --source-dir force-app/main/default/classes/VkfOwnerControllerTest.cls \
  --source-dir force-app/main/default/classes/AuditService.cls \
  --source-dir force-app/main/default/classes/UserContext.cls \
  --source-dir force-app/main/default/lwc \
  --source-dir force-app/main/default/tabs/VKF_Owner_Workspace.tab-meta.xml \
  --source-dir force-app/main/default/applications/VK_Finance_Console.app-meta.xml \
  --source-dir force-app/main/default/permissionsets/VKF_Platform_Admin.permissionset-meta.xml

# Release
sf apex run --target-org VKFINANCE --file scripts/apex/unschedule-jobs.apex
sf project deploy start --target-org VKFINANCE --test-level RunLocalTests --wait 30 <same --source-dir list>
sf apex run --target-org VKFINANCE --file scripts/apex/schedule-jobs.apex
```

The portal does not need to be rebuilt or republished; nothing in the UI bundle changed.

**The dry run needs the same treatment.** Even a check-only deploy is refused while the jobs are scheduled. Either run the unschedule script before the dry run (and reschedule after), or once enable **Setup → Deployment Settings → Allow deployments of components when corresponding Apex jobs are pending or in progress**, which removes the step for every future release.

## 2. Permissions

1. **Setup → Users → your user → Permission Set Assignments**: make sure `VKF Platform Admin` is assigned. It now grants the `VkfOwnerController` class and the **Owner Workspace** tab.
2. **Turn on Salesforce MFA for your user** (Setup → Identity Verification, or a permission set with _Multi-Factor Authentication for User Interface Logins_). The workspace can change any family's ledger, so the sign-in protecting it should be at least as strong as the portal's two-step verification.

## 3. Salesforce mobile app

1. Sign in to the org in the app. Pull down to refresh after a deployment.
2. Open the **App Launcher** (the grid icon, or _Menu → All Items_) and choose **VK Finance Console**. The app now supports phones, so it is listed.
3. **Owner Workspace** is the first item in the app's navigation.
4. Optional: in Setup → **Mobile Navigation**, nothing is needed for app-based navigation. Add the tab there only if you want it in the global menu outside the app.
5. Enable **biometric unlock** in the app's settings (_Settings → Passcode / Biometrics_) so the workspace opens with Face ID or a fingerprint.

## 4. First use

| Step                     | What you see                                                                                                               |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| Open **Owner Workspace** | The hero card shows the first family (or the last one you opened on this device), its code, status, member count and admin |
| Change family            | The family picker in the hero card                                                                                         |
| Change month             | ‹ and › in the hero card (Overview, Ledger, Budget)                                                                        |
| Sections                 | Overview · Ledger · Dues · Budget · Family                                                                                 |
| Add an entry             | The round **+** button (bottom right) → Expense, Income or Transfer                                                        |
| Void an entry            | Ledger → **Void** on the row → confirm                                                                                     |
| Pay a bill or EMI        | Dues → **Pay** → confirm (full amount from the usual account)                                                              |

Suspended families open read-only: the **+** button is hidden and writes are refused.

## Troubleshooting

| Message or symptom                                               | Cause                                     | Fix                                                             |
| ---------------------------------------------------------------- | ----------------------------------------- | --------------------------------------------------------------- |
| "You need the VKF Platform Admin permission set to do this."     | Permission set not assigned               | Assign `VKF Platform Admin`                                     |
| VK Finance Console missing on the phone                          | Old deployment, or app cache              | Deploy this change set, then pull to refresh or sign out and in |
| "That family has no Family Admin to act as."                     | The family's admin is disabled or removed | Reactivate or add a Family Admin from the console/portal        |
| "This family is suspended. Reactivate it before making changes." | Family status is Suspended                | Set the family to Active if changes are intended                |
| "Card bills are paid as a transfer…"                             | Card bills aren't paid from Dues in v1    | Add entry → Transfer from the bank account to the card          |
| "Choose the account the EMI is paid from."                       | The loan has no debit account             | Set it on the loan in the portal, or pay as an entry            |
| "Something went wrong. Please try again."                        | Unexpected server error                   | Check the debug log for "Owner Workspace error"                 |

## Validation evidence

| Check                        | Result                                                         | Scope                                                                                                                                                                                                                                                                                             |
| ---------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| LWC Jest                     | **26/26 passed**                                               | 5 suites: helpers, shell, ledger, dues, entry form                                                                                                                                                                                                                                                |
| ESLint (LWC rules)           | **Clean**                                                      | All `vkfOwner*` JavaScript, including tests                                                                                                                                                                                                                                                       |
| Org dry run, all local tests | **Passed (31 Oct 2026): 17/17 components, 196/196 Apex tests** | Validation `0AfjV000005RcazSAC` against `VKFINANCE`, nothing saved. Coverage: `AuditService` 100%, `OwnerContext` 97%, `UserContext` 93%, `VkfOwnerController` 89%. The first attempt (`0AfjV000005RJ8YSAW`) was refused because of scheduled jobs; the Deployment Setting below was then enabled |
| Salesforce Code Analyzer     | **Not run**                                                    | The CLI could not install the `code-analyzer` plugin on this machine                                                                                                                                                                                                                              |
| Physical device check        | **Pending**                                                    | After deployment                                                                                                                                                                                                                                                                                  |
