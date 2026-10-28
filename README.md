# VK Finance

A multi-family budget management platform on Salesforce. Each family has its own Family Admin and
members (spouse, children, parents) who sign in to a React portal hosted on Experience Cloud. No
family can see another family's data. The full design is in
[docs/VKFinance_Solution_Blueprint.pdf](docs/VKFinance_Solution_Blueprint.pdf).

**Status: v1.0.** All five phases are built and deployed to the `VKFinance` org:
- React on Experience Cloud, custom identity and security, and member management.
- The core ledger: accounts, categories, transactions, transfers, credit cards, budgets and the
  dashboard.
- Commitments with automation: bills, loans and EMIs, card statements, recurring entries, in-app
  notifications and a daily dues job.
- Insights: 13 reports with CSV, print and saved filters, monthly snapshots and a customisable
  overview.
- Go-live hardening:
  - two-step verification with an authenticator app, plus recovery codes
  - per-address throttling and step-up checks that count toward lockout
  - a Security page and in-app Help
  - nightly balance reconciliation, weekly retention purge and a weekly security digest
  - a passing security test run (see [docs/Security_Checklist.md](docs/Security_Checklist.md))

Phase 6 optional enhancements were deployed and published on 28 October 2026, with all 150 Apex
tests passing. Every family starts with these features off; see the Phase 6 guide for activation,
release evidence and remaining pilot checks.

| Document | For |
| --- | --- |
| [Phase 6 enhancements](docs/Phase6_Enhancements.md) | Released optional features; per-family switches, limits, deployment evidence and live-site checks |
| [Implementation guide (PDF)](docs/VKFinance_Implementation_Document.pdf) / [Word](docs/VKFinance_Implementation_Document.docx) | Developers and administrators: 12 diagrams, architecture, security, APIs, full data dictionary, deployment and operations |
| [docs/User_Guide.md](docs/User_Guide.md) | Families using the portal (also in the app under **Help**) |
| [docs/Security_Checklist.md](docs/Security_Checklist.md) | The go-live security pass: live checks, Code Analyzer triage, Health Check |
| [docs/Demo_Access.md](docs/Demo_Access.md) | Demo sign-ins and what to try |
| [docs/VKFinance_Solution_Blueprint.pdf](docs/VKFinance_Solution_Blueprint.pdf) | The full design |

## How it fits together

| Layer | What it is |
| --- | --- |
| Portal | React 19 UI bundle (`force-app/main/default/uiBundles/VKFinancePortal`) on the Experience Cloud site `VKFinancePortal`, served at `/VKFinancePortal` |
| API | Apex REST under `/services/apexrest/vkf/v1/*` (`Vkf*Resource` classes), called as the site guest user with the VK session token in the `X-VKF-Session` header |
| Identity | Custom `Portal_User__c` / `Portal_Session__c` - not Salesforce users. Passwords are salted, iterated HMAC-SHA256; only token hashes are stored |
| Two-step | `MfaService`: RFC 6238 authenticator codes (key in an encrypted field, replay-proof), 10 single-use recovery codes and sign-in challenges, stored as hashes in `Auth_Token__c`. Step-up checks (password, plus a code when two-step is on) guard sensitive actions, and failures count toward lockout |
| Throttling | Per username (`Security_Policy__mdt`) and per client address (`RateLimiter` → `Rate_Limit__c`, which stores only a hash of the address), plus caps on reset emails |
| Security gateway | `SessionService.require` → `AccessGuard.require` → `FamilyScopedSelector` on every endpoint. Other families' records return 404 |
| Ledger | `Financial_Account__c`, `Category__c`, `Transaction__c` (one row per money movement; a transfer is two linked rows), `Budget__c` / `Budget_Line__c`. `TransactionTrigger` → `LedgerBalances` keeps balances current incrementally, locking accounts `FOR UPDATE` |
| Commitments | `Bill__c` → `Bill_Instance__c`, `Loan__c` → `EMI_Installment__c` (only the next 12 stored; the full schedule is computed by `EmiCalculator`), `Card_Statement__c`, `Recurring_Rule__c`. Paying posts normal ledger entries, so budgets and balances just work; voiding a payment re-opens what it paid |
| Automation | `DailyDuesBatch` (06:00, "VKF Daily Dues") runs `DuesProcessor` once per family in its own transaction: bill/EMI statuses, card statements, recurring posts, auto-pay, reminders and budget alerts as `Notification__c` (deduplicated, read ones purged after 60 days) |
| Housekeeping | `BalanceReconcileJob` (02:00 daily) fixes and audits balance drift; `RetentionPurgeJob` (Sundays 04:00) deletes stale notifications, tokens, password history and rate-limit rows; `SecurityDigestJob` (Mondays 07:00) emails the org owner a weekly security summary; `SessionCleanupJob` runs hourly |
| Insights | `ReportService` returns every report in one shape (KPIs, one chart, tables), so the portal renders all 13 with one component. `InsightService`: saved reports (filters only - data is always re-read with the viewer's scope), per-person overview layout (`Portal_User__c.Dashboard_Layout__c`), and `Monthly_Summary__c` snapshots written by the daily job and used for months older than three in the trend |
| Who sees what | `LedgerScope`: admins see the family; Members their own and shared accounts; Children their own (editable for 24 hours); Viewers read only |
| Config | `Security_Policy__mdt` (timeouts, lockout, password rules, hash iterations), `Role_Permission__mdt` (role × feature × action) and `Default_Category__mdt` (the category template each family starts with) |
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

# Apex tests
sf apex run test --target-org VKFinance --test-level RunLocalTests --code-coverage --wait 20

# React unit tests
cd force-app/main/default/uiBundles/VKFinancePortal && npx vitest run

# Org hardening for Health Check (only the settings it lists; safe to re-run)
sf project deploy start --target-org VKFinance --metadata-dir config/hardening

# Live security checks (see docs/Security_Checklist.md for the variables)
node scripts/security/pentest.mjs
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
for trying the portal and checking isolation, `scripts/apex/seed-demo-finance.apex` gives
Demo Family A about four months of realistic accounts, transactions and budgets, and
`scripts/apex/seed-demo-commitments.apex` (run it twice) adds bills, loans and recurring rules. Delete them from
the console when you're done.
Sign-in details for the demo families are in [docs/Demo_Access.md](docs/Demo_Access.md).

## Things that will bite you

- **Apex runs in user mode by default from API 67.0.** The portal runs as the site guest user, who
  has no object or field access by design. So every query in the service/selector layer says
  `WITH SYSTEM_MODE`, and every DML says `as system`. That elevation only happens behind the session
  and role checks. Keep it that way for new code.
- **`AuditService` is pinned to API 66.0** on purpose: the guest user can't be granted platform-event
  access, so publishing audit events needs the pre-67 system-mode default. Don't bump its version.
- **Apex REST rejects some HTTP status codes** (e.g. 423). Stick to the codes in `PortalException`.
- **Anonymous Apex can't use `WITH SYSTEM_MODE` or `as system`.** Scripts run as you, so they need
  the `VKF_Platform_Admin` permission set, and they never set `Current_Balance__c` - the
  transaction trigger owns balances.
- **Apex is case-insensitive.** A local variable called `window` hides a constant `WINDOW`, and a
  parameter called `json` hides the `JSON` class - both cost a deploy cycle in Phase 3.
- **Bill and EMI payments aren't edited, they're voided** - the void re-opens the bill or rebuilds
  the loan's instalments from the loan account's ledger balance.
- **Never change a balance directly.** Opening balances and Adjustment entries (Accounts → Match to
  statement) are the only ways in, so the ledger always explains every balance.
  `LedgerBalances.recalculate()` rebuilds balances from the ledger if you ever need to check.
- **Big-object (audit log) queries fail after any DML in the same request**, and the error can't be
  caught. `SessionService` defers its last-activity update to `VkfRest.respond`, so audit reads
  run first. Keep any new audit read ahead of writes, and run anonymous checks in their own
  transaction.
- **Recovery for lost two-step:** a Family Admin uses **Reset two-step** on the Family page. If the
  Family Admin is the one locked out, the platform owner clears `MFA_Method__c` on their Portal User
  record in the console.
- **Never use GraphQL / UI API from the portal for family data.** The guest user can't read it, and
  granting access would expose every family.
- The Data SDK makes two background calls as the guest (`ui-api/session/csrf`, `ui-telemetry`) that
  return 401. They're harmless platform noise.
- Developer Edition limits: 5 MB data storage, 15 emails/day. Sessions are deleted after 7 days by
  the hourly `VKF Session Cleanup` job, the weekly purge keeps the rest lean, and audit lives in a
  big object.
