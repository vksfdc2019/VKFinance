# VK Finance: demo access

How to sign in to the VK Finance portal and the Salesforce org. These demo accounts exist only in
the `VKFinance` Developer Edition org.

> **The passwords below are now in this repo's git history.** If the repo is ever made public or
> shared, reset these passwords or delete the demo families first.

## Portal

**URL:** https://orgfarm-db588f31ab-dev-ed.develop.my.site.com/VKFinancePortal

| Username | Password | Family | Role |
| --- | --- | --- | --- |
| `demo.admin.a` | `Harbour#Lights2026` | Demo Family A (FAM-0001) | Family Admin |
| `demo.son.a` | `Mango#Tree2026x` | Demo Family A (FAM-0001) | Member |
| `demo.admin.b` | `Copper#Kettle2026` | Demo Family B (FAM-0002) | Family Admin |
| `demo.daughter.a` | *(not recorded; see below)* | Demo Family A (FAM-0001) | Child (Invited) |

### What to try

Demo Family A has about four months of sample money: salary, rent, groceries, bills, credit-card
spending and payments, SIPs and Arjun's pocket money, plus budgets for this month and last.

- **Overview:** sign in as `demo.admin.a`. You land on the family's net worth, this month's income,
  spending and savings, a six-month cash-flow chart (hover a month; **Table** shows the numbers),
  spending by category, budget progress, accounts and recent activity. Switch months with the
  arrows, or pick one family member in **Whole family**.
- **Add a transaction:** press **N** anywhere (or **Add transaction**). Choose Expense, Income or
  Transfer, type the amount, pick an account and search for a category. Transferring to the credit
  card records a card payment, which isn't counted as spending twice.
- **Transactions:** filter by month, type, account, category or person, search payees and notes,
  open any row to edit or void it, and export what you see to CSV.
- **Accounts:** each account is a card with its live balance. The credit card shows how much of
  the limit is used and the next statement and due dates. Use the **⋮** menu to add an expense
  there, pay the card, match the balance to a bank statement, or close the account.
- **Budgets:** see each category's progress. Amber means spending is running ahead of the month,
  red means over plan. **Edit plan** changes amounts and **Copy last month** starts a new month.
- **Categories:** rename, recolour, hide or add categories (Family Admin only).
- **Coming up and the bell:** the overview lists bills, EMIs and card bills due in the next 30
  days. The bell (top left) holds reminders and alerts from the daily 06:00 job - bills due soon,
  anything overdue, auto-payments, card bills and budgets passing 80% or 100%.
- **Bills:** pay a bill in two taps (watch the tick), skip one occurrence, or add a biller with
  auto-pay. Arjun (`demo.son.a`) sees and pays only the tuition bill assigned to him.
- **Loans & EMIs:** each loan shows how much is repaid, every EMI split into principal and
  interest, and the debt-free date. Try **Prepay** - the EMI stays the same and the loan ends
  sooner. **Schedule** shows every instalment. Adding a loan shows the EMI as you type.
- **Recurring:** salary, rent, SIP and pocket money repeat on their own (Auto-post) or ask first
  (Suggest). **Record now** posts the next one immediately.
- **Card statements:** Accounts → the card's **⋮** menu → **Statements**.
- **Family Admin view:** sign in as `demo.admin.a` and open **Family**. You see only Family A's
  members, and you can add, edit, unlock, reset passwords, sign out, disable and remove members.
  Role and status changes ask for your own password again.
- **Member view:** sign in as `demo.son.a`. Arjun sees his own pocket-money wallet and the shared
  household account, but not the salary account, the card or the investments. There is no
  **Family** or **Categories** link, and going to `/family` directly sends him back to Home.
- **Family isolation:** sign in as `demo.admin.b`. Family B starts empty with a setup guide and
  never sees Family A's money or members.
- **Your sessions:** open **Profile & security** to see your signed-in devices and sign them out.

### Getting `demo.daughter.a` working

The member was created with a one-time password that wasn't saved.

1. Sign in as `demo.admin.a`.
2. Open **Family**, then **Reset password** on `demo.daughter.a`.
3. Sign in as `demo.daughter.a` with the temporary password shown.
4. Set a new password when asked.

## Sign-in rules

| Rule | Value |
| --- | --- |
| Account lock | After 5 wrong passwords in a row the account locks for 30 minutes. A Family Admin can **Unlock** a member early. |
| Rapid attempts | More than 10 attempts on one username in 15 minutes are throttled. |
| Session timeout | 30 minutes idle, 12 hours at most. The portal warns you before it signs you out. |
| Devices | At most 3 signed-in sessions per person. Signing in on a 4th ends the least recently used one. |
| Temporary passwords | Valid for 24 hours. You must set your own password at first sign-in. |
| Reset links | "Forgot password" emails a link that is valid for 30 minutes. |

New passwords must:

- be at least 10 characters (12 for a Family Admin or Co-Admin)
- mix at least three of: upper-case letters, lower-case letters, digits and symbols
- not contain your name or username
- not match any of your last 5 passwords

All of these are set in the `Security_Policy__mdt` record `Default`.

## Salesforce org

- **Login:** https://login.salesforce.com as `vkfinance@agentforce.com`. The password isn't
  stored in this repo.
- **Console:** App Launcher → **VK Finance Console** (needs the `VKF_Platform_Admin` permission
  set, which is already assigned to the org admin).
  - The **Onboard Family** tab has two cards:
    - **Onboard a family** creates a new family and its first Family Admin, and shows their
      username and one-time password. Your own family will be FAM-0003.
    - **Reset a portal password** issues a new temporary password for any portal user.
- Demo families can be deleted from the **Families** tab when you no longer need them.

## Recreating the demo families

If the demo data is deleted, run:

```bash
sf apex run --target-org VKFinance --file scripts/apex/seed-demo-families.apex
sf apex run --target-org VKFinance --file scripts/apex/seed-demo-finance.apex
sf apex run --target-org VKFinance --file scripts/apex/seed-demo-commitments.apex
sf apex run --target-org VKFinance --file scripts/apex/seed-demo-commitments.apex
```

The finance script adds sample accounts, transactions and budgets to Demo Family A; the
commitments script (run twice) adds bills, loans and recurring rules and starts the daily job. It runs as
you, so you need the `VKF_Platform_Admin` permission set.

The script prints the new temporary passwords to the debug log (look for lines starting with
`VKF_SEED`). They will differ from the passwords above, and each user must set their own
password at first sign-in.
