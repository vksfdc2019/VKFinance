# VK Finance: security checklist (v1.0)

This is the go-live security pass for the `VKFinance` org, last run on **28 October 2026**. Re-run
it before every release; the commands are at the end.

| Area | Result |
| --- | --- |
| Live black-box checks (`scripts/security/pentest.mjs`) | **20 / 20 pass** |
| Apex tests | All pass, 93% org-wide coverage; isolation, role, lockout, two-step and throttling tests included |
| Browser checks (two-step setup, sign-in with a code, admin reset) | **8 / 8 pass** |
| Salesforce Code Analyzer (Security rules) | No open issues in VK code; findings triaged below |
| Salesforce Health Check | **85** (was 64); the rest needs the org owner's sign-in choices, see below |

## 1. Live checks against the portal

`scripts/security/pentest.mjs` runs these against the published site, using three demo logins. It
changes nothing when the portal is behaving.

| # | Check | Proves |
| --- | --- | --- |
| 1 | Plain HTTP redirects to HTTPS | No unencrypted access |
| 2 | Portal pages send CSP `frame-ancestors`, `nosniff` and HSTS | Clickjacking and MIME-sniffing blocked; HTTPS pinned |
| 3 | API responses are JSON with `Cache-Control: no-store` | Financial data isn't cached by browsers or proxies |
| 4 | All 16 protected endpoints return 401 without a session | No anonymous data access |
| 5 | A forged token is refused | Tokens can't be guessed (256-bit, stored only as SHA-256) |
| 6 | A real token replayed from another browser is refused | User-agent binding stops simple token theft |
| 7 | Unknown username and wrong password give byte-identical answers | No username enumeration |
| 8 | Password reset answers the same whether or not the account exists | No enumeration through reset |
| 9 | Signing out kills the token server-side | Sessions really end |
| 10 | A made-up two-step challenge is refused | The code step can't be skipped |
| 11 | Family B's admin gets 404 on 4 kinds of Family A records | Tenant isolation on reads |
| 12 | Family B's admin gets 404 on 5 kinds of writes to Family A | Tenant isolation on writes |
| 13 | A member gets 403 on the 5 admin-only reports and on adding members | Role matrix enforced on the server |
| 14 | A member sees no other family's people | Member scope |
| 15 | SOQL-injection text in search is treated as text | Bind variables only |
| 16 | Malformed JSON and bad ids get clean 400/404 | No 500s, no stack traces |
| 17 | No hashes, salts, secrets or stack traces in 16 endpoints' responses | DTO whitelists hold |
| 18 | Salesforce's REST data API gives the guest user nothing | The guest has no object access |
| 19 | Aura record APIs return no VK records to guests | The classic Experience Cloud guest exposure is closed |
| 20 | The template's self-registration page is closed to guests | No sign-up path |

## 2. Controls covered by Apex tests

- **Family isolation.** Every service is called with another family's ids and must return
  `NOT_FOUND`; each attempt is audited as `CROSS_FAMILY_ATTEMPT`. Tests: `FamilyIsolationTest`,
  `FinanceIsolationTest`.
- **Role matrix.** The role × feature × action rules in `Role_Permission__mdt` are checked for every
  endpoint.
- **Passwords**
  - Salted, iterated HMAC-SHA256.
  - Policy, history, temporary-password expiry.
  - Lockout after 5 failures, and each repeat lockout doubles the wait.
- **Throttling**
  - 10 attempts per username per 15 minutes.
  - 30 failures per client address per 15 minutes; only a SHA-256 hash of the address is stored.
  - 10 reset requests per address, and 3 reset emails per member per hour.
- **Two-step verification**
  - RFC 6238 test vectors.
  - Codes can't be replayed.
  - One window of clock drift.
  - Five tries per challenge, and wrong codes count toward lockout across challenges.
  - Recovery codes are single-use.
  - The admin reset can't be used on yourself or across families.
- **Step-up checks.** Sensitive actions need your password again, plus a code when two-step is on:
  - role and status changes
  - admin password and two-step resets
  - turning two-step off, and new recovery codes

  Wrong answers count toward lockout, and a lockout ends every session, so a stolen session can't
  be used to guess the password.
- **Sessions**
  - 30-minute idle and 12-hour absolute limits.
  - At most 3 sessions per person.
  - Changing your password signs out your other devices.
  - Admins are notified of a sign-in from a new device.

## 3. Code Analyzer triage

`sf code-analyzer run --rule-selector Security` over `classes/` and `triggers/` reported 58
findings.

| Findings | Disposition |
| --- | --- |
| 30 × `DatabaseOperationsMustUseWithSharing`, 19 × `ApexFlsViolation`, 1 × `ApexCRUDViolation` (`AuditLogWriter`) | **By design.** The API runs as the site guest user, who has no object access at all. Services run in explicit system mode (`WITH SYSTEM_MODE`, `as system`). Every request goes through `SessionService.require` → `AccessGuard.require` → family-scoped selectors, and the tenant id always comes from the session record, never from the request. |
| 2 × `AvoidHardcodedCredentialsInFieldDecls` | **False positives.** `UNKNOWN_SALT` is a dummy salt that equalises timing, and `SCOPE_CHANGE_PASSWORD` is a session-scope name. Marked `NOPMD` with the reason. |
| 4 × findings in `LightningForgotPasswordController`, `LightningSelfRegisterController` and `MyProfilePageController` | **Not reachable.** These are stock Communities-template controllers, and the React portal doesn't use them. The guest profile has no Apex class access; it reaches only the `Vkf*` REST resources through `VKF_Guest_Api_Access`. Self-registration is off, and guest access to the sign-up page was removed (`config/hardening`). |

## 4. Salesforce Health Check

The score went from **64 to 85** with the hardening package in `config/hardening`. It changes only
the settings it lists, so later choices you make in Setup are left alone:

- Clickjack protection for customer Visualforce pages, with and without headers.
- `HttpOnly` session cookies.
- Sign a user out everywhere when an admin resets their password.
- Identity check on email-address changes.
- Passwords need a special character; one-day minimum lifetime; obscured secret answer; 30-minute
  lockout.
- Record names in lookups require the "View All Lookup Record Names" permission.
- The site guest profile can't open the template's self-registration page.

**Still open. These change how you sign in to Salesforce, so they're your call:**

| Setting | Why it's not applied automatically |
| --- | --- |
| MFA for Salesforce UI logins | You'd register Salesforce Authenticator (or a TOTP app) at your next sign-in. **Strongly recommended**, and the biggest single gain in score. |
| Maximum invalid login attempts: 3 (now 10) | Three typos lock your own admin login. |
| Lock sessions to the originating IP / enforce login IP ranges | Breaks sessions on mobile networks and VPNs; needs fixed IP ranges. |
| Percentage of System Administrators | 1 of 2 internal users is an admin. That's normal for a single-owner Developer Edition org. |
| SAML | Not used. |
| One standard object with public external access | A standard CRM object the portal never uses. Every VK object is Private, internally and externally. |

## 5. Monitoring and housekeeping

| Job | When | What |
| --- | --- | --- |
| VKF Session Cleanup | Hourly | Expires idle sessions; deletes closed sessions and spent tokens after 7 days |
| VKF Balance Reconcile | 02:00 daily | Recomputes every balance from the ledger; fixes and audits any drift |
| VKF Daily Dues | 06:00 daily | Bills, EMIs, card statements, recurring entries, reminders, monthly snapshots |
| VKF Retention Purge | Sundays 04:00 | Read notifications after 60 days, spent one-time tokens, surplus or removed members' password history, old rate-limit rows |
| VKF Security Digest | Mondays 07:00 | One email to the org owner (see below) |

The weekly digest covers, per family:
- sign-ins and failures, lockouts, throttling and cross-family attempts
- two-step changes, password resets and new admins
- admins without two-step
- balance fixes, failed jobs and data storage

It goes to the user who scheduled it, and email to an internal user doesn't use the org's daily
email allowance.

The first live reconcile corrected one demo account. The seed script had created "SBI Fixed
Deposit" with a ₹0 current balance instead of its ₹3,00,000 opening balance.

## 6. How to re-run

```bash
# Apex tests
sf apex run test --target-org VKFinance --test-level RunLocalTests --code-coverage --wait 30

# Live black-box checks (demo logins without two-step)
VKF_SITE=https://orgfarm-db588f31ab-dev-ed.develop.my.site.com/VKFinancePortal \
VKF_ADMIN_A='demo.admin.a:<password>' VKF_MEMBER_A='demo.son.a:<password>' VKF_ADMIN_B='demo.admin.b:<password>' \
node scripts/security/pentest.mjs

# Code Analyzer
sf code-analyzer run --workspace force-app/main/default/classes --workspace force-app/main/default/triggers --rule-selector Security

# Health Check score
sf data query --target-org VKFinance --use-tooling-api --query "SELECT Score FROM SecurityHealthCheck"

# Re-apply the org hardening
sf project deploy start --target-org VKFinance --metadata-dir config/hardening
```
