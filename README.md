# VK Finance

A multi-family budget management platform on Salesforce. Each family has its own Family Admin and
members (spouse, children, parents) who sign in to a React portal hosted on Experience Cloud. No
family can see another family's data. The full design is in
[docs/VKFinance_Solution_Blueprint.pdf](docs/VKFinance_Solution_Blueprint.pdf).

**Status:** Phase 0 (React on Experience Cloud) and Phase 1 (identity, sessions, security core,
member management) are built and deployed to the `VKFinance` org. Finance features start in Phase 2.

## How it fits together

| Layer | What it is |
| --- | --- |
| Portal | React 19 UI bundle (`force-app/main/default/uiBundles/VKFinancePortal`) on the Experience Cloud site `VKFinancePortal`, served at `/VKFinancePortal` |
| API | Apex REST under `/services/apexrest/vkf/v1/*` (`Vkf*Resource` classes), called as the site guest user with the VK session token in the `X-VKF-Session` header |
| Identity | Custom `Portal_User__c` / `Portal_Session__c` - not Salesforce users. Passwords are salted, iterated HMAC-SHA256; only token hashes are stored |
| Security gateway | `SessionService.require` → `AccessGuard.require` → `FamilyScopedSelector` on every endpoint. Other families' records return 404 |
| Config | `Security_Policy__mdt` (timeouts, lockout, password rules, hash iterations) and `Role_Permission__mdt` (role × feature × action) |
| Audit | `Audit_Event__e` (publish immediately) → `AuditEventTrigger` → `Audit_Log__b` big object |
| Console | Lightning app **VK Finance Console** for the platform owner (needs the `VKF_Platform_Admin` permission set) |

## Day-to-day commands

Run from the project root. Everything targets the `VKFinance` org only.

```bash
# Build the React portal (needed before deploying the UI bundle)
cd force-app/main/default/uiBundles/VKFinancePortal && npm install && npm run build && cd -

# Deploy. Classes used by scheduled jobs can't deploy while the job is scheduled, so:
sf apex run --target-org VKFinance --file scripts/apex/unschedule-jobs.apex
sf project deploy start --target-org VKFinance --source-dir force-app
sf apex run --target-org VKFinance --file scripts/apex/schedule-jobs.apex
sf community publish --name VKFinancePortal --target-org VKFinance

# Apex tests (55 tests, ~96% coverage of VK classes)
sf apex run test --target-org VKFinance --test-level RunLocalTests --code-coverage --wait 20

# React unit tests
cd force-app/main/default/uiBundles/VKFinancePortal && npx vitest run
```

The unschedule/reschedule step can be skipped by enabling **Setup → Deployment Settings → Allow
deployments of components when corresponding Apex jobs are pending or in progress**.

## Onboarding a family

1. In Salesforce, open the **VK Finance Console** app → **Onboard Family**.
2. Enter the family and its first Family Admin. Share the username and one-time temporary password
   privately.
3. The admin signs in at the portal, sets their own password, and adds family members from
   **Family**.

`scripts/apex/seed-demo-families.apex` creates two demo families (`demo.admin.a`, `demo.admin.b`)
for trying the portal and checking isolation. Delete them from the console when you're done.
Sign-in details for the demo families are in [docs/Demo_Access.md](docs/Demo_Access.md).

## Things that will bite you

- **Apex runs in user mode by default from API 67.0.** The portal runs as the site guest user, who
  has no object or field access by design. So every query in the service/selector layer says
  `WITH SYSTEM_MODE`, and every DML says `as system`. That elevation only happens behind the session
  and role checks. Keep it that way for new code.
- **`AuditService` is pinned to API 66.0** on purpose: the guest user can't be granted platform-event
  access, so publishing audit events needs the pre-67 system-mode default. Don't bump its version.
- **Apex REST rejects some HTTP status codes** (e.g. 423). Stick to the codes in `PortalException`.
- **Never use GraphQL / UI API from the portal for family data.** The guest user can't read it, and
  granting access would expose every family.
- The Data SDK makes two background calls as the guest (`ui-api/session/csrf`, `ui-telemetry`) that
  return 401. They're harmless platform noise.
- Developer Edition limits: 5 MB data storage, 15 emails/day. Sessions are deleted after 7 days by
  the hourly `VKF Session Cleanup` job; audit lives in a big object.
