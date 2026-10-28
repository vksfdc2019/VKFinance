"""Build the implementation guide from narrative and repository metadata.

Python dependencies: python-docx, reportlab, pypdf, pymupdf.
Run from the repository root. No Salesforce connection is used.
"""
from pathlib import Path
import os
import re
import sys
import xml.etree.ElementTree as ET
from html import escape

local_libs = Path(os.environ.get('TEMP', '.')) / 'vkf-doc-libs'
if local_libs.exists():
    sys.path.insert(0, str(local_libs))

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from implementation_diagrams import build_assets

META = ROOT / 'force-app/main/default'
UI = META / 'uiBundles/VKFinancePortal'
OUT = ROOT / 'docs'
BASE = 'VKFinance_Implementation_Document'
FIGURES = build_assets(OUT / 'diagrams')
NS = {'m': 'http://soap.sforce.com/2006/04/metadata'}
blocks = []

def p(text): blocks.append(('p', text))
def h(text, level=1): blocks.append(('h', (level, text)))
def table(headers, rows, widths=None): blocks.append(('table', (headers, rows, widths)))
def code(text): blocks.append(('code', text.strip()))
def source(text): blocks.append(('source', 'Source: ' + text))
def get(el, key, default=''):
    return el.findtext('m:' + key, default, NS) or default
def values(path):
    root = ET.parse(path).getroot()
    return {get(v, 'field'): get(v, 'value') for v in root.findall('m:values', NS)}

roles = ['Family Admin', 'Co-Admin', 'Member', 'Child', 'Viewer']
permission_rows = [values(x) for x in sorted((META / 'customMetadata').glob('Role_Permission.*.xml'))]
objects = sorted((META / 'objects').iterdir())
classes = sorted((META / 'classes').glob('*.cls'))
test_classes = [x for x in classes if re.search(r'@isTest\b', x.read_text(encoding='utf-8'), re.I)]
fields = [(obj, sorted((obj / 'fields').glob('*.xml'))) for obj in objects if obj.is_dir()]
field_count = sum(len(fs) for _, fs in fields)
routes = []
for file in sorted((META / 'classes').glob('Vkf*Resource.cls')):
    text = file.read_text(encoding='utf-8')
    match = re.search(r"urlMapping='([^']+)'", text)
    if match:
        routes.append((file.stem, match.group(1), ', '.join(re.findall(r'@Http(\w+)', text))))

h('1. Purpose, scope and evidence')
p('VK Finance is a multi-family personal finance platform implemented on Salesforce. Families use a React portal on Experience Cloud to manage accounts, income, expenses, transfers, budgets, bills, loans, recurring entries and reports. Internal Salesforce users operate the VK Finance Console to onboard and support families. Portal members are custom records, rather than individual Salesforce users.')
p('This guide describes the checked-in implementation as reviewed on 28 October 2026. It is intended for developers, solution architects, administrators, testers and support owners. Source code and metadata determine the implementation tables. Existing README and security documents provide historical deployment and validation context. No org deployment, live security test or application test was run to prepare this guide.')
table(['Document control', 'Value'], [
    ['Document', 'VK Finance - Detailed Implementation Document'],
    ['Edition / date', '1.1 / 28 October 2026; expanded diagrams'],
    ['Scope', 'Repository implementation, metadata, UI, API, security, operations and handover'],
    ['Evidence boundary', 'Local source review; live org state and current scheduled jobs were not independently verified'],
    ['Outputs', BASE + '.docx and ' + BASE + '.pdf; Markdown, generator and 12 SVG/PNG diagrams included'],
    ['Existing design', 'docs/VKFinance_Solution_Blueprint.pdf is the separate solution blueprint'],
])
table(['Source inventory', 'Count / setting'], [
    ['Apex classes / test-annotated classes', f'{len(classes)} / {len(test_classes)} (includes Salesforce template code and test helpers)'],
    ['Apex REST resource classes', str(len(routes))],
    ['Object, event, big-object and custom-metadata definitions', str(len(fields))],
    ['Checked-in custom field definitions', str(field_count)],
    ['Role permission records', str(len(permission_rows))],
    ['Salesforce source API version', '68.0 in sfdx-project.json'],
])
source('README.md; sfdx-project.json; force-app/main/default; docs/Security_Checklist.md.')

h('2. Business capabilities and boundaries')
table(['Capability', 'Implementation', 'Result for a family'], [
    ['Identity and membership', 'AuthService, MemberService, MfaService, FamilyOnboardingService', 'Invite members, set passwords, manage roles, use authenticator codes and recovery codes.'],
    ['Core ledger', 'AccountService, CategoryService, TransactionService, TransferService, LedgerBalances', 'Record movements and maintain explainable balances across assets and liabilities.'],
    ['Planning', 'BudgetService, DashboardService', 'Plan monthly spending and compare actuals with category budgets.'],
    ['Commitments', 'BillService, LoanService, CardStatementService, RecurringService', 'Track upcoming obligations and record payments through the same ledger.'],
    ['Automation', 'DailyDuesBatch, DuesProcessor, NotificationService', 'Post recurring entries, attempt configured auto-pay, update dues and deliver reminders.'],
    ['Insights', 'ReportService, InsightService', 'Read 13 reports, export CSV, print, save filters and personalize the overview.'],
    ['Platform operations', 'VkfConsoleController, scheduled security jobs, AuditService', 'Onboard families, monitor failures, reconcile balances and control retention.'],
])
p('The portal is a bookkeeping application. A payment action records ledger entries; the reviewed implementation does not show bank payment rails or a bank-feed integration. Family base currency and time zone are stored, while reminder money formatting explicitly uses the rupee symbol. Foreign-exchange conversion and fully localized automation must not be inferred from those configuration fields.')
p('Family onboarding defaults to INR, Asia/Kolkata and 10 members; the service validates a configured member limit between 1 and 50. Categories are seeded from Default_Category__mdt when a family is created. Template Communities controllers also exist in the repository; they are distinct from the custom VK portal identity flow.')
source('FamilyOnboardingService.cls; DuesProcessor.money; package contents; docs/User_Guide.md.')

h('3. Architecture and request lifecycle')
table(['Step / layer', 'Component', 'Responsibility'], [
    ['1. Browser', 'React portal / routes.tsx', 'Render pages, route authenticated users, show actions from returned permissions.'],
    ['2. Transport', 'src/api/vkfClient.ts and endpoints.ts', 'Use Salesforce Data SDK fetch; send JSON and X-VKF-Session.'],
    ['3. REST boundary', 'Vkf*Resource and VkfRest', 'Dispatch verbs and paths, parse bodies, manage savepoints, normalize responses.'],
    ['4. Identity', 'SessionService.require -> UserContext', 'Validate token, user, family, scope and time limits; load current role from records.'],
    ['5. Authorization', 'AccessGuard.require + service checks', 'Enforce role/feature/action, then business and ownership rules.'],
    ['6. Data scope', 'FamilyScopedSelector subclasses + LedgerScope', 'Constrain family queries and narrow visible accounts and transactions.'],
    ['7. Persistence', 'Salesforce custom records + triggers', 'Use explicit system-mode access after application checks; update ledger balances.'],
    ['8. Audit / response', 'Audit_Event__e -> Audit_Log__b; VkfRest.respond', 'Publish audit events, flush deferred session activity, send uncached DTOs.'],
])
p('The site guest user is the Salesforce execution identity for portal calls. The VK session identifies the actual family member. Services and selectors intentionally use explicit system mode because the guest has no family-data CRUD/FLS access. Consequently, the application-level session, permission and tenant checks are critical security boundaries. Salesforce sharing alone does not implement portal isolation.')
p('Typical write: a resource opens a savepoint, authenticates the VK session, invokes a service, checks a feature action, resolves family-scoped records, applies business validation and saves records. A service returns a DTO rather than serializing unrestricted records. VkfRest sends JSON with Cache-Control: no-store. On failure the REST layer normally rolls back; PortalException.keep() preserves intended security writes such as failed-attempt counters.')
p('Typical read: authenticate, authorize, query the allowed scope, build a DTO and respond. Session activity is deferred until response time so audit big-object reads occur before ordinary DML. New audit reads must preserve this ordering.')
source('VkfRest.cls; SessionService.cls; AccessGuard.cls; FamilyScopedSelector.cls; FinanceDtos.cls; PortalDtos.cls.')

h('4. Repository and technology map')
table(['Location / technology', 'Purpose / declared version'], [
    ['force-app/main/default/classes', 'Apex REST, services, selectors, DTOs, jobs and tests.'],
    ['force-app/main/default/objects', 'Custom objects, custom metadata, platform event and audit big object.'],
    ['force-app/main/default/customMetadata', 'Role grants, default security policy and category templates.'],
    ['force-app/main/default/uiBundles/VKFinancePortal', 'React Experience Cloud UI bundle; Node >=22.'],
    ['React / TypeScript / Vite', 'Declared React ^19.2.0, TypeScript ~5.9.3 and Vite ^7.2.4.'],
    ['Salesforce platform SDK / UI bundle', 'Both declared ^11.57.2; Data SDK transports custom REST calls.'],
    ['Tailwind / Radix / Zod', 'Styling, UI primitives and validation; declared ^4.1.17 / ^1.4.3 / ^4.3.5.'],
    ['Vitest / Playwright', 'Unit and browser test tooling; declared ^4.1.0 / ^1.49.0.'],
    ['lwc/vkfFamilyOnboarding', 'Internal family onboarding interface.'],
    ['scripts/apex and scripts/security', 'Scheduling, demo seeding and live black-box security checks.'],
    ['config/hardening', 'Scoped Salesforce security settings and guest profile changes.'],
    ['docs', 'User guide, security evidence, demo guidance, blueprint and this implementation guide.'],
])
p('Versions above are manifest declarations, not a statement about the currently installed environment. The UI package-lock.json records dependency resolution. Root npm scripts primarily target Salesforce LWC development; portal build and Vitest commands must run inside the UI bundle directory.')

h('5. Data model and relationships')
object_purpose = {
    'Family__c': 'Tenant root; family configuration, status, currency, time zone and member cap.',
    'Portal_User__c': 'Custom portal identity, family membership, role, password state, MFA and dashboard layout.',
    'Portal_Session__c': 'Hashed session token, user/family linkage, scope, activity and revocation.',
    'Password_History__c': 'Previous salted hashes used to enforce password reuse policy.',
    'Auth_Token__c': 'Hashed one-time reset, MFA challenge and recovery-token state.',
    'Rate_Limit__c': 'Hashed client-address or throttle bucket and window counters.',
    'Financial_Account__c': 'Bank, cash, wallet, card, loan and investment balances and ownership.',
    'Category__c': 'Family-specific category hierarchy, kinds and system categories.',
    'Transaction__c': 'One ledger movement; linked transfer/payment rows and commitment references.',
    'Budget__c': 'Monthly family budget header.',
    'Budget_Line__c': 'Category allocation belonging to a budget.',
    'Bill__c': 'Reusable bill definition, responsible person and payment/reminder configuration.',
    'Bill_Instance__c': 'Dated obligation with amounts due, paid and current status.',
    'Loan__c': 'Loan terms, borrower, loan account, EMI and outstanding principal.',
    'EMI_Installment__c': 'Persisted loan installment with principal/interest split and due status.',
    'Card_Statement__c': 'Card cycle snapshot, statement amount, minimum payment and due date.',
    'Recurring_Rule__c': 'Recurring transaction configuration, cadence and next-run state.',
    'Notification__c': 'Recipient-specific alert, severity, read state and deduplication key.',
    'Saved_Report__c': 'Report type and saved filters; private or family shared.',
    'Monthly_Summary__c': 'Monthly snapshots supporting older historical trends.',
    'Audit_Event__e': 'Immediate-publish event transporting audit facts to the writer.',
    'Audit_Log__b': 'Indexed audit history held outside normal custom-object storage.',
    'Role_Permission__mdt': 'Role x feature x action grants plus descriptive scope.',
    'Security_Policy__mdt': 'Default timeouts, password, hashing, throttling and portal URL configuration.',
    'Default_Category__mdt': 'Category template copied into each family.',
}
table(['Entity', 'Purpose'], [[o.name, object_purpose.get(o.name, '')] for o, _ in fields], [0.30, 0.70])
h('5.1 Relationship interpretation', 2)
p('Family__c is the application tenant. Most operational records carry a direct family reference so selectors can apply a tenant predicate. Some child records reach the family through their parent. A lookup field alone does not prove that both referenced records belong to the same family: services must resolve and validate every client-supplied reference.')
table(['Relationship', 'Implementation meaning'], [
    ['Family -> Portal User -> Session', 'The session must match the user\'s current family and active state.'],
    ['Account -> Transaction -> Category / Member', 'Transactions explain balance changes and attribution; category and member filters are scoped.'],
    ['Transaction <-> counter transaction', 'Transfer_Group_Id__c and Counter_Transaction__c connect related movements.'],
    ['Budget -> Budget Line -> Category', 'A month carries planned allocations; actual spending is derived from the ledger.'],
    ['Bill -> Bill Instance -> Transaction', 'A recurring definition yields dated obligations; payment rows reference the obligation.'],
    ['Loan -> EMI Installment -> Transaction', 'Terms generate installments; principal and interest rows are linked to payment state.'],
    ['Financial Account -> Card Statement', 'Statement records are cycle snapshots; payment status is evaluated against ledger credits.'],
    ['Portal User -> Notification / Saved Report', 'Recipient and owner scope applies inside the family boundary.'],
])
source('objects/**/fields/*.field-meta.xml; IdentitySelector.cls; CommitmentSelector.cls; TransactionSelector.cls.')

h('6. Authentication, sessions and account security')
h('6.1 Identity flows', 2)
table(['Flow', 'Sequence and persisted effects'], [
    ['Family onboarding', 'Internal console authorizes the platform owner; creates family, seeded categories and first Family Admin; returns a temporary password once.'],
    ['First sign-in', 'Validate temporary credentials; create CHANGE_PASSWORD session; require a new password before full portal access.'],
    ['Normal sign-in', 'Normalize username, apply throttling and lockout, verify salted iterated hash; either issue full session or require MFA challenge completion.'],
    ['MFA sign-in', 'Validate expiring hashed challenge and TOTP/recovery code; enforce challenge attempts and account lockout; issue full session only after success.'],
    ['Forgot / reset', 'Return generic forgot-password response, limit reset emails, validate single-use expiring token and apply password policy.'],
    ['Password change', 'Verify current password, enforce length/history, apply new hash and revoke other devices.'],
    ['Sign-out', 'Revoke session on the server and clear the browser token.'],
    ['Member removal', 'Disable sign-in and clear identity secrets while retaining financial history attribution.'],
])
h('6.2 Security policy defaults', 2)
policy = values(META / 'customMetadata/Security_Policy.Default.md-meta.xml')
policy_notes = {
    'Idle_Timeout_Minutes__c': 'Idle session expiration, minutes', 'Absolute_Timeout_Hours__c': 'Maximum session lifetime, hours',
    'Max_Sessions_Per_User__c': 'Concurrent session cap', 'Max_Failed_Logins__c': 'Failures before account lockout',
    'Lockout_Minutes__c': 'Initial lockout duration, minutes; repeat lockouts escalate',
    'Throttle_Window_Minutes__c': 'Per-username throttle window, minutes', 'Throttle_Max_Attempts__c': 'Per-username attempts per window',
    'Min_Password_Length__c': 'Minimum member password length', 'Min_Admin_Password_Length__c': 'Minimum admin password length',
    'Password_History_Count__c': 'Previous passwords checked', 'Hash_Iterations__c': 'Salted HMAC-SHA256 iteration setting',
    'Reset_Token_Minutes__c': 'Password-reset token lifetime, minutes', 'Temp_Password_Hours__c': 'Temporary password lifetime, hours',
    'Session_Retention_Days__c': 'Closed session retention, days', 'MFA_Challenge_Minutes__c': 'MFA login challenge lifetime, minutes',
    'Ip_Max_Failures__c': 'Client-address failure cap per window', 'Portal_Base_Url__c': 'Email and onboarding destination; change for each environment',
}
table(['Metadata field', 'Default', 'Meaning'], [[k, ('Environment-specific URL' if k == 'Portal_Base_Url__c' else v), policy_notes.get(k, '')] for k, v in policy.items()], [0.40, 0.18, 0.42])
p('Passwords use per-password salt and iterative HMAC-SHA256. Raw session tokens are 256-bit random values and only SHA-256 hashes are persisted. The portal stores the raw token per tab in sessionStorage under vkf.session and sends it in X-VKF-Session. Treat browser script integrity as part of token protection.')
p('SessionService checks active session status, absolute and idle expiration, active user and family, user/session family equality and session scope. A nonblank differing user agent is rejected when a binding hash exists; the code tolerates a missing user-agent header. This is a supplemental check, not a cryptographic device binding.')
h('6.3 MFA, recovery and step-up', 2)
p('MfaService implements RFC 6238 authenticator codes, a 30-second period, one window of clock drift and replay protection. The secret is stored in an encrypted field. Setup is confirmed by a valid code. Ten single-use recovery codes are provided; persisted verification state is hashed. Login challenges expire and allow five attempts, with wrong codes also contributing to account lockout.')
p('Sensitive role/status changes, administrative password and MFA resets, MFA disable and recovery-code renewal require step-up verification: current password and, where enabled, an authenticator or recovery code. Failures count toward lockout; lockout revokes sessions. Family-admin MFA reset cannot target the caller or another family. The existing runbook describes platform-owner recovery for a locked-out Family Admin.')
source('AuthService.cls; PasswordService.cls; TokenService.cls; SessionService.cls; MfaService.cls; AccountSecurityService.cls; Security_Policy.Default metadata; src/api/vkfClient.ts.')

h('7. Authorization and family isolation')
p('AccessGuard loads Role_Permission__mdt once into a transaction-local map keyed by Role__c + "|" + Feature__c. Actions__c is split on commas, trimmed and uppercased. can() denies a missing grant; require() audits ACCESS_DENIED and throws NOT_AUTHORIZED. permissionsFor() returns sorted FEATURE:ACTION values for UI visibility. Services use uppercase action constants.')
p('Scope__c is not read by AccessGuard. It describes intended scope in metadata; it does not automatically enforce ownership or family visibility. Selectors and service rules implement that scope. Changing a Scope__c value alone does not change record access.')
h('7.1 Exact role/action matrix', 2)
p('Cells below are generated from the checked-in role metadata. A dash means no metadata record or no granted actions. Additional service restrictions continue to apply even when an action is listed. Abbreviations: FA = Family Admin; CA = Co-Admin.')
features = sorted({x['Feature__c'] for x in permission_rows})
perm = {(x['Role__c'], x['Feature__c']): x for x in permission_rows}
table(['Feature', 'FA', 'CA', 'Member', 'Child', 'Viewer'], [[f] + [perm.get((r, f), {}).get('Actions__c', '-').replace(',', ', ') for r in roles] for f in features], [0.18, 0.19, 0.19, 0.17, 0.14, 0.13])
h('7.2 Row-level rules', 2)
table(['Role / concern', 'Actual scope rule'], [
    ['Family Admin / Co-Admin', 'Whole-family ledger visibility. Co-Admin member administration has additional protections around Family Admins.'],
    ['Member', 'Own and family-shared accounts; can manage own account settings; may edit own eligible transactions.'],
    ['Child', 'Own accounts; own non-void transaction edits only within 24 hours of CreatedDate.'],
    ['Viewer', 'Read only; whole-family scope when Viewer_Scope__c = Family; otherwise own-account scope. No posting or account use.'],
    ['Transaction visibility', 'Whole-family scope OR attributed to caller OR held on a visible account.'],
    ['Transfer destination', 'Any active account in the same family can receive funds; source use is restricted. This supports pocket money to a child\'s wallet.'],
    ['Cross-family record IDs', 'Family-scoped lookup returns NOT_FOUND/404 and can audit CROSS_FAMILY_ATTEMPT.'],
    ['Notifications', 'Family and Recipient__c must match the caller. Admins do not receive a family-wide notification feed.'],
])
h('7.3 FA_NOTIFICATIONS worked example', 2)
p('Role_Permission.FA_NOTIFICATIONS.md-meta.xml grants Family Admin the NOTIFICATIONS feature with the READ action and Scope__c = OWN. NotificationService.feed() requires NOTIFICATIONS:READ and reads the caller\'s latest 30 alerts and unread count. markRead() uses the same READ grant, then filters by family and recipient; an empty ids array means mark the caller\'s unread alerts read, capped at 2,000 in that branch. No separate EDIT grant is required by this implementation.')
p('When adding a protected feature, create the intended role grants, call AccessGuard in the service, resolve IDs through scoped selectors, enforce row-level business rules and return a safe DTO. Client route guards help navigation; server checks enforce access.')
source('AccessGuard.cls; LedgerScope.cls; FamilyScopedSelector.cls; MemberService.cls; NotificationService.cls; Role_Permission.FA_NOTIFICATIONS.md-meta.xml.')

h('8. Ledger and planning implementation')
h('8.1 Balance mechanics', 2)
p('TransactionTrigger invokes LedgerBalances to apply the difference between old and new net effects. Credit contributes +amount, Debit contributes -amount, and Void contributes zero. The handler locks affected accounts FOR UPDATE before updating balances. Incremental deltas keep posting cost independent of total ledger history; recalculate() is the full-ledger recovery path.')
table(['Account / operation', 'Rule', 'Example'], [
    ['Asset balance', 'Opening balance + net ledger effect', 'Bank starts at INR 10,000; an expense debit of INR 1,000 leaves INR 9,000.'],
    ['Liability balance', 'Opening amount owed - net ledger effect', 'Card owes INR 5,000; a purchase debit of INR 1,000 increases owed balance to INR 6,000.'],
    ['Transfer', 'Source debit + target credit, linked by group and counter IDs', 'Bank to wallet changes account balances, without increasing family income or spending.'],
    ['Credit-card payment', 'Linked Card Payment rows', 'Bank debit and card credit reduce cash and card debt; purchase expense was already recognized.'],
    ['Reconcile to statement', 'Post an Adjustment explaining the difference', 'Use Accounts -> Match to statement instead of manually overwriting the current balance.'],
    ['Void', 'Set status to Void; trigger removes the prior net effect', 'History remains visible while balances and commitment status are corrected.'],
])
h('8.2 Transactions and validation', 2)
p('Manual entry accepts Income, Expense and Refund; transfers use TransferService. Services validate account usability, category type, member attribution, amount and transaction date. Admins can attribute entries to a family member; other roles can post only for themselves. Transfer source must be a usable non-liability account, source and destination must differ, and destination must be active and in the family. General transfers reject Loan targets; loan payments use LoanService.')
p('Transaction edits update both transfer legs together for supported fields. Changing a transfer\'s accounts requires voiding and recreating it. Bill and EMI payments cannot be edited; void them and pay again. Voiding linked payment groups restores bill or installment state and rebuilds the loan window as needed.')
p('The transaction list supports month or from/to dates, types, account, category including children, member where allowed, search text and optional void records. Default page size is 50 with a maximum of 200. Pagination uses a date/name cursor; aggregate totals are returned on the initial page. This avoids deep OFFSET pagination.')
h('8.3 Categories, budgets and dashboard', 2)
p('Category templates are copied into family-specific records. Parent-child categories support drilldown and aggregation, while system categories identify transfers and card payments. A monthly Budget__c groups Budget_Line__c planned category amounts. BudgetService computes actuals from ledger activity and supports copying the prior month. DashboardService combines scoped balances and monthly figures; InsightService stores each person\'s overview layout.')
source('LedgerBalances.cls; TransactionTrigger.trigger; TransactionService.cls; TransferService.cls; AccountService.cls; CategoryService.cls; BudgetService.cls; DashboardService.cls.')

h('9. Bills, loans, cards and recurring commitments')
table(['Module', 'State / calculation', 'Payment and reversal behavior'], [
    ['Bills', 'Bill definition produces dated Bill_Instance records; refresh derives due/overdue state and tracks amount due/paid.', 'Pay creates Bill Payment ledger activity; skip is explicit; voiding payment reopens the corresponding obligation.'],
    ['Loans / EMIs', 'EmiCalculator computes amortization; only the next 12 open installments are persisted, plus historical paid records.', 'EMI splits principal transfer legs from interest expense. Payment updates paid count and rebuilds the next installment window.'],
    ['Loan prepayment', 'Principal-only payment, no greater than outstanding.', 'EMI remains the same; remaining tenure shortens. Ledger reversal rebuilds future installments.'],
    ['Cards', 'Statements snapshot cycle-end owed amount, minimum due and due date; unique cycle keys prevent duplicate creation.', 'Card Payment/Adjustment credits determine payment progress. The card is paid through linked ledger movements.'],
    ['Recurring entries', 'Weekly, Monthly, Quarterly or Yearly; next-run date advances after post/skip; MAX_CATCH_UP = 3.', 'Configured auto-post reuses normal transaction/transfer services; manual confirmation can post or skip.'],
])
h('9.1 EMI calculation and accounting example', 2)
p('For principal P, monthly rate r = annual percentage / 1200 and tenure n, EMI = P*r*(1+r)^n / ((1+r)^n - 1). Zero-rate loans use P/n. Each period rounds interest to two decimal places, principal is EMI minus interest, and the final payment absorbs the remaining principal. An EMI too small to repay the balance is rejected.')
p('For INR 1,000,000 at 9% for 60 months, the calculated EMI is approximately INR 20,758.36. First-month interest is INR 7,500.00 and principal is INR 13,258.36. LoanService records the principal as linked movements from the paying account to the loan account and the interest as an Expense from the paying account. This keeps principal reduction separate from expense reporting. The full computed schedule is capped at 600 rows in current service calls.')
h('9.2 Daily processing and reruns', 2)
p('DuesProcessor first ensures the prior monthly snapshot, refreshes bill instances and loan windows, generates card statements and processes recurring rules. It then attempts configured bill/EMI auto-pay, sends bill/EMI/card reminders and evaluates budget thresholds. Automation builds a real member context through SystemContext so the reused services still apply role and scope checks.')
p('DailyDuesBatch uses one family per production batch execution. Each family has a savepoint; an exception rolls back that family\'s work and emits DAILY_DUES_FAILED. Completion purges read notifications beyond retention. Unique keys, due-state advancement and notification dedupe keys support reruns; they should not be interpreted as a general distributed exactly-once guarantee for every concurrent payment request.')
p('Bill/EMI reminder buckets include 7, 3, 1 and 0 days; card reminders inspect a five-day horizon. Budget notifications go to admins at 80% and 100%. Dedupe keys include family, event identity and recipient. Auto-pay records bookkeeping movements inside Salesforce; it does not initiate an external bank payment.')
source('BillService.cls; LoanService.cls; EmiCalculator.cls; CardStatementService.cls; RecurringService.cls; DuesProcessor.cls; DailyDuesBatch.cls; SystemContext.cls.')

h('10. Reports, snapshots and export')
p('ReportService uses a shared response shape: type/title/subtitle, date range, KPI list, one chart, a primary table, optional detail table, note and drilldown information. ReportView renders that contract across report types. Default period is the selected/current month; the service rejects reversed ranges and spans beyond MAX_DAYS = 1,100. Member, category and account filters are revalidated against the caller\'s scope.')
report_descriptions = [
    ('summary', 'Monthly summary', 'Income, spending and net position.'), ('category', 'Category spending', 'Category and subcategory drilldown.'),
    ('members', 'Member comparison', 'Family member attribution and comparison.'), ('trend', 'Spending / income trend', 'Historical month series, using snapshots for older months where applicable.'),
    ('budget', 'Budget versus actual', 'Planned allocations compared with ledger actuals.'), ('forecast', 'Cash-flow forecast', 'Upcoming commitments and available liquid funds.'),
    ('account', 'Account view', 'Scoped account activity and balances.'), ('cards', 'Credit cards', 'Card balances, utilization and payment view.'),
    ('loans', 'Loan view', 'Outstanding amounts and installment context.'), ('bills', 'Bills view', 'Family obligations and payment state.'),
    ('modes', 'Payment modes', 'Spending grouped by payment mode.'), ('annual', 'Annual summary', 'Family year-level comparison.'),
    ('security', 'Security activity', 'Family security/audit view.'),
]
admin_reports = {'members', 'forecast', 'bills', 'annual', 'security'}
table(['Type', 'Report', 'Access', 'Purpose'], [[k, title, 'Admins only' if k in admin_reports else 'REPORTS:READ + scope', detail] for k, title, detail in report_descriptions], [0.12, 0.23, 0.22, 0.43])
p('Saved_Report__c stores report type and filter configuration rather than a frozen data extract. Sharing a saved report does not share the owner\'s access: the report is rerun using the viewer\'s current scope. Dashboard widget order/visibility is saved in Portal_User__c.Dashboard_Layout__c. Monthly_Summary__c snapshots support trend months older than three; the daily job ensures the previous month exists.')
p('CSV export and browser print are portal capabilities. The Print workflow can be saved as PDF by the browser. These are separate from the DOCX/PDF project documentation generated with this guide.')
source('ReportService.cls; InsightService.cls; src/features/reports/ReportView.tsx; src/api/reportTypes.ts.')

h('11. Portal implementation and API contract')
h('11.1 Frontend organization', 2)
table(['Area', 'Implementation'], [
    ['Routing', 'routes.tsx: public login/forgot; reset-password and first-login; authenticated AppLayout with feature guards.'],
    ['Lazy loading', 'Pages beyond the overview are loaded on demand using React.lazy.'],
    ['Authentication state', 'AuthContext, RouteGuards and SessionTimeout coordinate session state and sign-in transitions.'],
    ['Shared finance state', 'LedgerContext and typed API DTOs support common account/category/transaction interactions.'],
    ['API adapter', 'vkfClient caches Data SDK initialization, attaches session header and converts errors to ApiError.'],
    ['Session expiration', 'A 401 SESSION_EXPIRED with a token clears storage and dispatches vkf:session-expired.'],
    ['Feature pages', 'Accounts, transactions, categories, budgets, bills, loans, recurring, family, profile/security, reports and help.'],
    ['UI system', 'Tailwind styling, shared UI primitives, finance components, charts, QR and OTP controls.'],
])
h('11.2 REST resource map', 2)
p('Base path: /services/apexrest/vkf/v1. The mappings below are read directly from Apex annotations. Wildcard resources dispatch child paths internally. Most protected resources require a full session; login/reset/MFA and ping have flow-specific authentication rules.')
table(['Resource class', 'Mapping (after /services/apexrest)', 'HTTP handlers'], routes, [0.36, 0.40, 0.24])
h('11.3 Client operation catalog', 2)
p('The following operations are extracted from endpoints.ts. {id} represents a URL-encoded client identifier or path parameter; query expressions are omitted from the path column. Request fields and return types are defined in src/api/types.ts, financeTypes.ts, commitmentTypes.ts and reportTypes.ts. Server handlers remain authoritative.')
endpoint_text = (UI / 'src/api/endpoints.ts').read_text(encoding='utf-8')
endpoint_rows = []
group = ''
pending = ''
for line in endpoint_text.splitlines():
    g = re.match(r'export const (\w+) =', line)
    if g: group = g.group(1)
    op = re.match(r'\s+(\w+):\s*\(', line)
    if op: pending = op.group(1)
    m = re.search(r'vkf<.*?>\("(GET|POST|PUT|PATCH|DELETE)",\s*(["`])(.+?)\2', line)
    if m:
        path = m.group(3)
        path = re.sub(r'\$\{queryString\(.*', '', path)
        if 'skip ?' in path:
            path = '/recurring/{id}/{post|skip}'
        else:
            path = re.sub(r'\$\{[^}]+\}', '{id}', path)
        endpoint_rows.append([group + '.' + pending, m.group(1), path])
table(['Client operation', 'Verb', 'Path'], endpoint_rows, [0.44, 0.12, 0.44])
h('11.4 Errors, status codes and payloads', 2)
table(['HTTP status', 'Application codes / meaning'], [
    ['200 / 201 / 204', 'Successful response, created entity or empty success according to handler.'],
    ['400', 'BAD_REQUEST, MFA_EXPIRED; malformed JSON object or invalid request.'],
    ['401', 'INVALID_CREDENTIALS or SESSION_EXPIRED.'],
    ['403', 'NOT_AUTHORIZED, PASSWORD_CHANGE_REQUIRED or LOCKED.'],
    ['404', 'NOT_FOUND, including out-of-family record references.'],
    ['409', 'CONFLICT, such as an already closed commitment.'],
    ['422', 'VALIDATION or INVALID_CODE.'],
    ['429', 'THROTTLED.'],
    ['500', 'UNEXPECTED; generic client message, diagnostics restricted to server logging.'],
])
code('''Request header: X-VKF-Session: <raw session token>
Content-Type: application/json

Example transaction body (use real in-scope record IDs):
{
  "type": "Expense", "accountId": "<account-id>",
  "categoryId": "<expense-category-id>", "amount": 1250,
  "date": "2026-10-28", "notes": "Groceries"
}

Error contract:
{"code":"NOT_AUTHORIZED","errors":["You don't have access to do that."]}''')
source('src/routes.tsx; src/api/endpoints.ts; src/api/vkfClient.ts; Vkf*Resource.cls; VkfRest.cls; PortalException.cls.')

h('12. Audit, scheduled jobs and retention')
p('AuditService publishes Audit_Event__e immediately. AuditEventTrigger delegates to AuditLogWriter, which persists Audit_Log__b. Immediate publishing means security evidence can survive a rolled-back business transaction; an event is evidence of the logged action/attempt and must be interpreted with its outcome. AuditService is intentionally pinned to API 66.0 in this repository because of guest platform-event access behavior documented by the project.')
table(['Job', 'Schedule expression', 'Purpose'], [
    ['VKF Session Cleanup', '0 0 * * * ?', 'Hourly: expire stale sessions and remove old closed sessions/spent token state.'],
    ['VKF Balance Reconcile', '0 0 2 * * ?', 'Daily 02:00: compare balances with ledger, correct drift and audit changes.'],
    ['VKF Daily Dues', '0 0 6 * * ?', 'Daily 06:00: commitments, recurring entries, reminders and monthly snapshots.'],
    ['VKF Retention Purge', '0 0 4 ? * SUN', 'Sunday 04:00: remove stale notifications, tokens, password history and rate windows.'],
    ['VKF Security Digest', '0 0 7 ? * MON', 'Monday 07:00: email a security/operations summary to the scheduling user.'],
])
p('The schedule script retains jobs whose names already exist, so rerunning it does not update an existing cron expression. When changing schedules, inspect and replace the intended existing jobs. Cron expressions do not embed a family time zone; verify the scheduling Salesforce user\'s time zone and NextFireTime. Family.Time_Zone__c does not by itself prove family-specific execution times.')
table(['Record / concern', 'Retention or operational behavior'], [
    ['Closed sessions', 'Default seven days; hourly cleanup also marks stale active sessions expired.'],
    ['Read notifications', 'Older than 60 days are purged; unread notifications are not covered by this read-only deletion rule.'],
    ['Auth tokens', 'Weekly purge removes used or expired tokens older than one day, with a 5,000-row query cap.'],
    ['Password history', 'Retain configured history depth; remove surplus and history belonging to removed members.'],
    ['Rate limits', 'Weekly purge deletes windows older than one day, capped at 5,000 per query.'],
    ['Financial ledger / audit', 'No general ledger or audit deletion policy is established by these housekeeping rules. Define archival separately if required.'],
])
p('The existing security checklist reports a Developer Edition constraint of 5 MB normal data storage and 15 external emails/day; treat these as the recorded environment assumptions, not a newly checked quota. Monitor actual org storage and email limits before adding families. Several purge paths have row caps and the recurring catch-up has a cap, so review backlogs after downtime or growth.')
source('AuditService.cls and metadata; AuditEventTrigger.trigger; AuditLogWriter.cls; schedule-jobs.apex; SessionService.cleanup; RetentionPurgeJob.cls; docs/Security_Checklist.md.')

h('13. Build, configuration and deployment runbook')
h('13.1 Prerequisites and environment settings', 2)
table(['Prerequisite', 'Preparation'], [
    ['Salesforce access', 'Use the intended org alias, Experience Cloud site and internal deployment user. This guide follows the repository alias VKFinance.'],
    ['Platform owner', 'Assign VKF_Platform_Admin permission set for console and administrative scripts.'],
    ['Local tools', 'Node >=22, npm and Salesforce CLI; authenticated connection to the intended org.'],
    ['Portal configuration', 'Review Security_Policy.Default.Portal_Base_Url__c and Experience Cloud routing for each environment.'],
    ['Guest API boundary', 'Preserve VKF_Guest_Api_Access and hardening; do not grant guest family-object CRUD/FLS access.'],
    ['Scheduler', 'Confirm scheduler identity, time zone and email destination for the security digest.'],
    ['Email and recovery', 'Verify reset email delivery, portal reset links and owner support procedures before onboarding.'],
])
h('13.2 Build and deploy commands', 2)
p('Run commands from the project root in PowerShell. Review the target-org alias before any mutating command. npm ci uses the checked-in portal lockfile. Unscheduling is needed where Salesforce blocks deployments of classes referenced by pending jobs; the repository documents a Deployment Settings alternative. These commands are instructions and were not executed as part of this document task.')
code('''# Build portal
Push-Location force-app/main/default/uiBundles/VKFinancePortal
npm ci
npm run build
Pop-Location

# Deploy source, restore schedules and publish the site
sf apex run --target-org VKFinance --file scripts/apex/unschedule-jobs.apex
sf project deploy start --target-org VKFinance --source-dir force-app
sf apex run --target-org VKFinance --file scripts/apex/schedule-jobs.apex
sf community publish --name VKFinancePortal --target-org VKFinance

# Apply the reviewed hardening package
sf project deploy start --target-org VKFinance --metadata-dir config/hardening''')
p('If deployment fails after jobs are unscheduled, assess the deployed state and restore appropriate schedules using the reviewed script. Publishing and Apex tests are separate steps. Keep a prior known-good source revision and build artifact for recovery; redeploying source does not reverse data mutations or financial entries.')
h('13.3 Onboarding and demo preparation', 2)
table(['Step', 'Action / expected result'], [
    ['1', 'Open VK Finance Console -> Onboard Family as an authorized internal user.'],
    ['2', 'Enter family and first Family Admin details; inspect currency, time zone and member cap.'],
    ['3', 'Share the one-time temporary password privately; first sign-in requires a personal password.'],
    ['4', 'Enable MFA for administrators; save recovery codes; add members and assign minimal roles.'],
    ['5', 'Add accounts with opening balances, confirm category templates and configure budgets/commitments.'],
    ['6', 'For an isolated demo only, use seed-demo-families.apex, seed-demo-finance.apex and seed-demo-commitments.apex (the README says to run the last twice).'],
])
p('Demo credentials are intentionally not reproduced here. Use the existing Demo_Access.md only in the appropriate trusted environment. Demo scripts change records and are not part of a normal production deployment.')
source('README.md; scripts/apex/*.apex; config/hardening; VKF_Platform_Admin.permissionset-meta.xml; VKF_Guest_Api_Access.permissionset-meta.xml.')

h('14. Verification strategy and existing evidence')
p('This documentation task validates generated artifacts and repository-derived tables. It does not certify runtime correctness. The figures below are recorded claims from docs/Security_Checklist.md dated 28 October 2026, not test results produced during this task.')
table(['Existing evidence', 'Recorded result', 'Interpretation'], [
    ['Live black-box security checks', '20 / 20 passed', 'Historical published-site checks of isolation, auth, guest data access and response hygiene.'],
    ['Apex tests', 'All pass; 93% org-wide coverage', 'Historical org test run; this guide does not include a newly generated test report.'],
    ['Browser MFA checks', '8 / 8 passed', 'Historical setup, sign-in and admin reset verification.'],
    ['Code Analyzer security review', '58 findings triaged; no open VK issues reported', 'Includes deliberate system-mode access and template-code findings; review the original rationale.'],
    ['Salesforce Health Check', '85, improved from 64', 'Remaining Salesforce login/configuration choices are listed in the security checklist.'],
])
h('14.1 Test coverage map', 2)
table(['Concern', 'Representative repository tests', 'Release expectation'], [
    ['Identity and password rules', 'AuthServiceTest, PasswordServiceTest, SessionServiceTest', 'Reject wrong/expired/revoked credentials and enforce password history and restricted sessions.'],
    ['MFA / security jobs', 'MfaServiceTest, SecurityJobsTest', 'Check TOTP vectors, replay, recovery, lockout and housekeeping behavior.'],
    ['Family and finance isolation', 'FamilyIsolationTest, FinanceIsolationTest', 'Use another family\'s IDs on reads and writes; require 404 and audit behavior.'],
    ['Ledger / planning', 'LedgerServiceTest, PlanningServiceTest', 'Verify debit/credit/liability math, paired transfers, voids, scope and budget totals.'],
    ['Commitments / automation', 'CommitmentServiceTest, DuesAutomationTest', 'Verify payment splits, reopen behavior, reruns, dedupe and due-date changes.'],
    ['REST / console', 'VkfResourcesTest, VkfLedgerResourcesTest, VkfCommitmentResourcesTest, VkfConsoleControllerTest', 'Verify dispatch, status codes, safe payloads and internal authorization.'],
    ['Insights', 'ReportServiceTest', 'Verify report scope, admin-only types, aggregates and saved-filter behavior.'],
    ['Portal unit / browser tooling', 'src/api/vkfClient.test.ts; src/lib/finance.test.ts; e2e/', 'Run available portal checks; inspect browser paths for affected features.'],
])
code('''# Apex validation
sf apex run test --target-org VKFinance --test-level RunLocalTests --code-coverage --wait 30

# Portal validation
Push-Location force-app/main/default/uiBundles/VKFinancePortal
npx vitest run
npm run build
Pop-Location

# Security static analysis
sf code-analyzer run --workspace force-app/main/default/classes --workspace force-app/main/default/triggers --rule-selector Security

# Live checks require environment-specific test accounts and variables.
# Follow docs/Security_Checklist.md, then run:
node scripts/security/pentest.mjs''')
p('Release acceptance should include: a fresh login and first-login path; MFA and recovery; a cross-family denial; Member/Child/Viewer restrictions; posting and voiding a transfer; a bill and EMI payment/reversal; budget actuals; report scope; and scheduled-job status. Use dedicated test data and check both UI and API outcomes.')

h('15. Troubleshooting, limitations and handover')
table(['Symptom / constraint', 'Likely cause', 'Action'], [
    ['Guest API cannot read family objects', 'Expected absence of direct guest CRUD/FLS', 'Use the custom REST route and VK session; preserve application checks.'],
    ['Apex deployment blocked by jobs', 'Scheduled jobs reference edited classes', 'Follow unschedule/deploy/reschedule or the reviewed Deployment Settings alternative.'],
    ['Audit read fails after writes', 'Big-object query ordering restriction documented by project', 'Perform audit reads before DML; keep session activity deferred.'],
    ['Locked account returned as 403', 'PortalException maps LOCKED to supported status', 'Use application code to distinguish lockout from a general access denial.'],
    ['MFA codes consistently fail', 'Clock skew, replay or expired challenge', 'Check automatic device time; restart sign-in; use a recovery code if necessary.'],
    ['Duplicate or missing dues after outage', 'Backlog, due state or capped catch-up', 'Review rule dates, unique keys, job failures and catch-up bounds before rerunning.'],
    ['Balance drift', 'Bypassed service/trigger path or imported opening data', 'Inspect ledger and reconcile job audit; correct through approved adjustments or recalculation.'],
    ['401 background UI API calls', 'README identifies SDK csrf/telemetry guest calls', 'Distinguish them from failed VK REST requests; inspect the actual request path.'],
    ['Data or email quota pressure', 'Developer Edition scale assumptions', 'Inspect live limits, retention backlog, unread alerts and user growth.'],
])
h('15.1 Implementation cautions', 2)
p('Do not raise AuditService\'s API version without revalidating guest audit publishing. Preserve explicit WITH SYSTEM_MODE queries and as system DML only behind authorization. Anonymous Apex scripts follow a different access context and the project explicitly warns against copying those system-mode clauses into anonymous scripts. Avoid variable names that shadow Apex identifiers because Apex is case-insensitive.')
p('General TransferService still contains a legacy validation message describing loan repayment as a later-release feature, although LoanService implements EMI and prepayment. Treat the route behavior as authoritative and consider updating that message during future product maintenance. Loan creation initializes its liability account balance; ongoing balance corrections belong to ledger movements and reconciliation.')
p('Configured family time zones and currency fields should be reviewed before broader geographic rollout: daily processing uses Date.today(), cron follows the scheduler context, and reminder money text is INR-specific. The checked-in project does not establish disaster-recovery objectives, automated backup/restore evidence or an external archival policy. Define and verify those operational requirements before relying on them.')
h('15.2 Handover checklist', 2)
table(['Owner', 'Required handover item'], [
    ['Platform owner', 'Org/site ownership, VKF_Platform_Admin assignment, scheduler identity and verified next-run times.'],
    ['Security owner', 'Admin MFA/recovery, guest access review, open Health Check decisions and fresh release security evidence.'],
    ['Developer', 'Build/deploy process, API 66 audit exception, system-mode boundary, tenant checks and typed DTO contracts.'],
    ['Finance support', 'Opening balances, adjustment policy, payment void/repost behavior and reconciliation review.'],
    ['Operations', 'Storage/email monitoring, failed jobs, purge backlog, snapshot freshness and backup/restore procedure.'],
    ['Tester', 'Two-family test dataset, all five roles and fresh unit/integration/browser/security results.'],
])

h('Appendix A. Complete custom-field dictionary')
p('This appendix is generated from every checked-in objects/*/fields/*.field-meta.xml file. It lists custom fields only; standard Salesforce fields such as Id, Name, CreatedDate and system audit fields are omitted. Required means the metadata required flag, not every conditional requirement enforced by Apex. Relationship targets, formulas, enumerated values and uniqueness are included where present. No runtime records or credential values are included.')
for obj, files in fields:
    h(obj.name, 2)
    p(object_purpose.get(obj.name, 'Repository metadata entity.'))
    rows = []
    for file in files:
        root = ET.parse(file).getroot()
        detail = []
        if get(root, 'referenceTo'): detail.append('Target: ' + get(root, 'referenceTo'))
        if get(root, 'length'): detail.append('Length ' + get(root, 'length'))
        if get(root, 'precision'): detail.append('Precision ' + get(root, 'precision') + ', scale ' + get(root, 'scale', '0'))
        if get(root, 'unique') == 'true': detail.append('Unique')
        if get(root, 'externalId') == 'true': detail.append('External ID')
        if get(root, 'defaultValue'): detail.append('Default: ' + get(root, 'defaultValue'))
        vals = [get(x, 'fullName') for x in root.findall('m:valueSet/m:valueSetDefinition/m:value', NS)]
        if vals: detail.append('Values: ' + ', '.join(vals))
        if get(root, 'formula'): detail.append('Formula: ' + get(root, 'formula'))
        if get(root, 'description'): detail.append(get(root, 'description'))
        rows.append([get(root, 'fullName', file.name.split('.')[0]), get(root, 'type', 'Derived'), 'Yes' if get(root, 'required') == 'true' else '-', '; '.join(detail) or get(root, 'label')])
    table(['Field API name', 'Type', 'Req.', 'Definition / constraints'], rows, [0.32, 0.16, 0.07, 0.45])
source('force-app/main/default/objects/**/fields/*.field-meta.xml; standard fields and Apex-only validations are outside this generated inventory.')

h('Appendix B. Role metadata scope reference')
p('Exact Actions__c and Scope__c values are preserved here for traceability. As explained in section 7, Scope__c is descriptive metadata; AccessGuard consumes role, feature and actions only.')
table(['Role', 'Feature', 'Actions', 'Scope'], [[x['Role__c'], x['Feature__c'], x.get('Actions__c', '-'), x.get('Scope__c', '-')] for x in permission_rows], [0.20, 0.23, 0.38, 0.19])

h('Appendix C. Source references and glossary')
table(['Reference', 'Use in this document'], [
    ['README.md', 'Project status, architecture summary, commands and operational cautions.'],
    ['docs/User_Guide.md', 'Family workflows and user-facing feature descriptions.'],
    ['docs/Security_Checklist.md', 'Historical security results, Health Check decisions and rerun guidance.'],
    ['docs/VKFinance_Solution_Blueprint.pdf', 'Existing design artifact; consult separately for original solution intent.'],
    ['classes/AccessGuard.cls; LedgerScope.cls; FamilyScopedSelector.cls', 'Role actions, in-family visibility and family tenant boundary.'],
    ['customMetadata/Role_Permission.*; Security_Policy.Default', 'Generated permission matrix and default policy values.'],
    ['objects/**; classes/Vkf*Resource.cls; src/api/endpoints.ts', 'Generated data dictionary, REST mappings and client operation catalog.'],
    ['scripts/apex/schedule-jobs.apex; unschedule-jobs.apex', 'Job names, cron expressions and deployment preparation.'],
    ['scripts/build_implementation_document.py', 'Narrative source and repeatable DOCX/PDF/Markdown generation.'],
])
table(['Term', 'Meaning'], [
    ['Tenant', 'One family whose records are isolated from other families.'],
    ['DTO', 'Data transfer object exposing approved response fields.'],
    ['EMI', 'Equated monthly installment, split into principal and interest.'],
    ['TOTP', 'Time-based one-time password generated by an authenticator app.'],
    ['Step-up', 'Re-verification of credentials before a sensitive action.'],
    ['System mode', 'Elevated Salesforce data access; application guards must supply member authorization.'],
    ['Dedupe key', 'Persisted event/recipient identity used to suppress duplicate alerts.'],
    ['Snapshot', 'Persisted monthly aggregate supporting historical insight.'],
])

# Place diagrams directly after their associated section headings, numbering
# them in reading order rather than filesystem or factory order.
illustrated_blocks = []
figure_number = 0
for kind, payload in blocks:
    illustrated_blocks.append((kind, payload))
    if kind == 'h':
        for figure in FIGURES.values():
            if figure['section'] == payload[1]:
                figure_number += 1
                figure['title'] = 'Figure ' + str(figure_number) + '. ' + figure['title'].split('. ', 1)[1]
                illustrated_blocks.append(('figure', figure))
blocks = illustrated_blocks


def markdown():
    lines = ['# VK Finance - Detailed Implementation Document', '', 'Version 1.1 | 28 October 2026', '']
    for kind, payload in blocks:
        if kind == 'h':
            level, txt = payload
            lines += ['#' * (level + 1) + ' ' + txt, '']
        elif kind == 'table':
            headers, rows, _ = payload
            clean = lambda x: str(x).replace('|', '\\|').replace('\n', '<br>')
            lines += ['| ' + ' | '.join(map(clean, headers)) + ' |', '| ' + ' | '.join(['---'] * len(headers)) + ' |']
            lines += ['| ' + ' | '.join(map(clean, row)) + ' |' for row in rows]
            lines += ['']
        elif kind == 'code': lines += ['```text', payload, '```', '']
        elif kind == 'figure':
            relative = payload['svg'].relative_to(OUT).as_posix()
            lines += ['![' + payload['title'] + '](' + relative + ')', '', '**' + payload['title'] + '**', '', payload['explanation'], '', 'Source: ' + payload['source'], '']
        else: lines += [payload, '']
    (OUT / (BASE + '.md')).write_text('\n'.join(lines), encoding='utf-8')


def docx():
    from docx import Document
    from docx.shared import Inches, Pt, RGBColor
    from docx.oxml import OxmlElement
    from docx.oxml.ns import qn
    doc = Document()
    sec = doc.sections[0]
    sec.page_width, sec.page_height = Inches(8.27), Inches(11.69)
    sec.top_margin = sec.bottom_margin = Inches(.65)
    sec.left_margin = sec.right_margin = Inches(.65)
    normal = doc.styles['Normal']
    normal.font.name, normal.font.size = 'Calibri', Pt(10)
    normal.paragraph_format.space_after = Pt(7)
    for name in ['Title', 'Heading 1', 'Heading 2']:
        doc.styles[name].font.color.rgb = RGBColor.from_string('12334B')
    doc.styles['Heading 1'].font.size = Pt(19)
    doc.styles['Heading 2'].font.size = Pt(13)
    header = sec.header.paragraphs[0]
    header.text = 'VK FINANCE  /  IMPLEMENTATION GUIDE'
    header.style = doc.styles['Caption']
    footer = sec.footer.paragraphs[0]
    footer.text = '28 October 2026  |  v1.1                                      Page '
    fld = OxmlElement('w:fldSimple'); fld.set(qn('w:instr'), 'PAGE'); footer._p.append(fld)
    doc.add_paragraph('VK FINANCE', 'Subtitle')
    doc.add_paragraph('Detailed Implementation\nDocument', 'Title')
    doc.add_paragraph('Architecture, security, data model, APIs and operations', 'Subtitle')
    doc.add_paragraph('Version 1.1  |  28 October 2026')
    doc.add_paragraph('A source-based guide to the Salesforce finance platform and React Experience Cloud portal.')
    doc.add_paragraph('Includes 12 architecture, use-case, workflow and sequence diagrams, generated role/action tables, REST catalogs and the complete custom-field dictionary.')
    doc.add_page_break()
    doc.add_heading('Contents', 1)
    for kind, payload in blocks:
        if kind == 'h' and payload[0] == 1: doc.add_paragraph(payload[1])
    doc.add_page_break()
    doc.add_heading('List of figures', 1)
    for kind, payload in blocks:
        if kind == 'figure': doc.add_paragraph(payload['title'])
    for kind, payload in blocks:
        if kind == 'h':
            level, txt = payload
            if level == 1: doc.add_page_break()
            doc.add_heading(txt, level)
        elif kind == 'figure':
            para = doc.add_paragraph()
            para.paragraph_format.keep_with_next = True
            picture = para.add_run().add_picture(str(payload['png']), width=Inches(6.97))
            picture._inline.docPr.set('descr', payload['explanation'])
            picture._inline.docPr.set('title', payload['title'])
            caption = doc.add_paragraph(payload['title'], 'Caption')
            caption.paragraph_format.keep_with_next = True
            doc.add_paragraph(payload['explanation'])
            evidence = doc.add_paragraph('Source: ' + payload['source'])
            for run in evidence.runs: run.font.size = Pt(8); run.italic = True
        elif kind == 'table':
            headers, rows, widths = payload
            t = doc.add_table(rows=1, cols=len(headers))
            t.style = 'Light Shading Accent 1'
            t.autofit = False
            fractions = widths or [1 / len(headers)] * len(headers)
            for col, fraction in zip(t.columns, fractions): col.width = Inches(6.97 * fraction)
            for i, txt in enumerate(headers): t.rows[0].cells[i].text = str(txt)
            trpr = t.rows[0]._tr.get_or_add_trPr()
            repeat = OxmlElement('w:tblHeader'); trpr.append(repeat)
            for row in rows:
                cells = t.add_row().cells
                for i, txt in enumerate(row): cells[i].text = str(txt)
            for n, row in enumerate(t.rows):
                no_split = OxmlElement('w:cantSplit'); row._tr.get_or_add_trPr().append(no_split)
                for i, cell in enumerate(row.cells):
                    cell.width = Inches(6.97 * fractions[i])
                    for paragraph in cell.paragraphs:
                        paragraph.paragraph_format.space_after = Pt(4)
                        paragraph.paragraph_format.space_before = Pt(3)
                        for run in paragraph.runs:
                            run.font.size = Pt(8)
                            if n == 0: run.bold = True
            doc.add_paragraph().paragraph_format.space_after = Pt(1)
        elif kind == 'code':
            para = doc.add_paragraph()
            para.paragraph_format.space_after = Pt(9)
            run = para.add_run(payload); run.font.name = 'Consolas'; run.font.size = Pt(8)
        else:
            para = doc.add_paragraph(payload)
            if kind == 'source':
                for run in para.runs: run.font.size = Pt(8); run.italic = True
    doc.core_properties.title = 'VK Finance - Detailed Implementation Document'
    doc.core_properties.subject = 'Source-based architecture, implementation and operations guide'
    doc.core_properties.author = 'VK Finance Project'
    doc.save(OUT / (BASE + '.docx'))


def pdf():
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, LongTable, TableStyle, Preformatted, KeepTogether
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_LEFT
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    fonts = Path('C:/Windows/Fonts')
    pdfmetrics.registerFont(TTFont('Guide', str(fonts / 'calibri.ttf')))
    pdfmetrics.registerFont(TTFont('GuideBold', str(fonts / 'calibrib.ttf')))
    pdfmetrics.registerFontFamily('Guide', normal='Guide', bold='GuideBold', italic='Guide', boldItalic='GuideBold')
    styles = getSampleStyleSheet()
    for key in ['BodyText', 'Normal', 'Heading1', 'Heading2', 'Title']:
        styles[key].fontName = 'Guide'
    styles.add(ParagraphStyle(name='Body', fontName='Guide', fontSize=10, leading=14, spaceAfter=8))
    styles.add(ParagraphStyle(name='Cell', fontName='Guide', fontSize=8, leading=10.5, splitLongWords=True))
    styles.add(ParagraphStyle(name='CellHead', fontName='GuideBold', fontSize=8, leading=10.5, textColor=colors.white))
    styles.add(ParagraphStyle(name='Source', fontName='Guide', fontSize=8, leading=11, textColor=colors.HexColor('#536878'), spaceAfter=9))
    styles.add(ParagraphStyle(name='FigureCaption', fontName='GuideBold', fontSize=10, leading=13, textColor=colors.HexColor('#12334B'), spaceBefore=5, spaceAfter=5))
    styles['Heading1'].fontName = 'GuideBold'; styles['Heading1'].fontSize = 19; styles['Heading1'].leading = 23
    styles['Heading2'].fontName = 'GuideBold'; styles['Heading2'].fontSize = 13; styles['Heading2'].leading = 17
    styles['Heading1'].textColor = styles['Heading2'].textColor = colors.HexColor('#12334B')
    for key in ['Heading1', 'Heading2']: styles[key].spaceAfter = 10
    styles.add(ParagraphStyle(name='CoverTitle', fontName='GuideBold', fontSize=34, leading=40, textColor=colors.HexColor('#12334B'), spaceAfter=20))
    styles.add(ParagraphStyle(name='CodeGuide', fontName='Courier', fontSize=7.1, leading=10, backColor=colors.HexColor('#F1F4F7'), borderPadding=7, spaceAfter=10))
    safe = lambda txt: escape(str(txt)).replace('\n', '<br/>')
    story = [Spacer(1, 60), Paragraph('VK FINANCE', styles['Heading2']), Spacer(1, 16), Paragraph('Detailed<br/>Implementation<br/>Document', styles['CoverTitle']), Paragraph('Architecture, security, data model, APIs and operations', styles['Body']), Spacer(1, 25), Paragraph('Version 1.1 | 28 October 2026', styles['Body']), Paragraph('A source-based guide to the Salesforce finance platform and React Experience Cloud portal.', styles['Body']), Spacer(1, 20), Paragraph('Includes 12 architecture, use-case, workflow and sequence diagrams, generated role/action tables, REST catalogs and the complete custom-field dictionary.', styles['Body']), PageBreak(), Paragraph('Contents', styles['Heading1'])]
    for kind, payload in blocks:
        if kind == 'h' and payload[0] == 1: story.append(Paragraph(safe(payload[1]), styles['Body']))
    story += [PageBreak(), Paragraph('List of figures', styles['Heading1'])]
    for kind, payload in blocks:
        if kind == 'figure': story.append(Paragraph(safe(payload['title']), styles['Body']))
    width = A4[0] - 92
    for kind, payload in blocks:
        if kind == 'h':
            level, txt = payload
            if level == 1: story.append(PageBreak())
            story.append(Paragraph(safe(txt), styles['Heading1' if level == 1 else 'Heading2']))
        elif kind == 'figure':
            drawing = payload['drawing']
            factor = width / drawing.width
            drawing.scale(factor, factor)
            drawing.width *= factor
            drawing.height *= factor
            story.append(KeepTogether([
                drawing,
                Paragraph(safe(payload['title']), styles['FigureCaption']),
                Paragraph(safe(payload['explanation']), styles['Body']),
                Paragraph('Source: ' + safe(payload['source']), styles['Source']),
                Spacer(1, 10),
            ]))
        elif kind == 'table':
            headers, rows, widths = payload
            data = [[Paragraph(safe(x), styles['CellHead']) for x in headers]]
            data += [[Paragraph(safe(x), styles['Cell']) for x in row] for row in rows]
            fractions = widths or [1 / len(headers)] * len(headers)
            t = LongTable(data, colWidths=[width * x for x in fractions], repeatRows=1, hAlign=TA_LEFT)
            t.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#12334B')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F0F5F8')]),
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ('LEFTPADDING', (0, 0), (-1, -1), 6), ('RIGHTPADDING', (0, 0), (-1, -1), 6),
                ('TOPPADDING', (0, 0), (-1, -1), 6), ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
                ('LINEBELOW', (0, 0), (-1, 0), .6, colors.HexColor('#198B9A')),
                ('LINEBELOW', (0, 1), (-1, -1), .25, colors.HexColor('#D5E1E8')),
            ]))
            story += [t, Spacer(1, 10)]
        elif kind == 'code':
            import textwrap
            wrapped = '\n'.join('\n'.join(textwrap.wrap(line, 103, replace_whitespace=False, drop_whitespace=False)) if len(line) > 103 else line for line in payload.splitlines())
            story += [Preformatted(wrapped, styles['CodeGuide']), Spacer(1, 5)]
        else: story.append(Paragraph(safe(payload), styles['Source' if kind == 'source' else 'Body']))
    def page(canvas, doc):
        canvas.saveState()
        canvas.setFont('Guide', 8)
        canvas.setFillColor(colors.HexColor('#536878'))
        canvas.drawString(46, A4[1] - 28, 'VK FINANCE / IMPLEMENTATION GUIDE')
        canvas.setStrokeColor(colors.HexColor('#D5E1E8'))
        canvas.line(46, 35, A4[0] - 46, 35)
        canvas.drawString(46, 23, '28 October 2026 | v1.1')
        canvas.drawRightString(A4[0] - 46, 23, 'Page ' + str(doc.page))
        canvas.restoreState()
    class GuideDoc(SimpleDocTemplate):
        def afterFlowable(self, flowable):
            if isinstance(flowable, Paragraph) and flowable.style.name == 'Heading1':
                key = 'section-' + str(self.page)
                self.canv.bookmarkPage(key)
                self.canv.addOutlineEntry(flowable.getPlainText(), key, 0, False)
    document = GuideDoc(str(OUT / (BASE + '.pdf')), pagesize=A4, rightMargin=46, leftMargin=46, topMargin=48, bottomMargin=48, title='VK Finance - Detailed Implementation Document', author='VK Finance Project')
    document.build(story, onFirstPage=page, onLaterPages=page)


if __name__ == '__main__':
    OUT.mkdir(exist_ok=True)
    markdown()
    docx()
    pdf()
    print(f'Generated {len(blocks)} content blocks, {field_count} fields, {len(permission_rows)} role records and {len(endpoint_rows)} client operations.')
    for suffix in ['md', 'docx', 'pdf']:
        file = OUT / (BASE + '.' + suffix)
        print(f'{file.relative_to(ROOT)}: {file.stat().st_size:,} bytes')
