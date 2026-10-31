# Owner alerts — push, email and Telegram

Every morning at **07:30** ("VKF Owner Alerts") the platform owner gets one digest across every active family. A quiet day sends nothing.

| What's in it                                                                               | Source                                                                                                                         |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| Bills, EMIs and card bills **overdue** or **due within N days** (default 3)                | `DuesService` — the same list as the Dues section                                                                              |
| Transactions **at or above the family's Large Transaction Threshold** in the last 24 hours | `Family__c.Large_Txn_Threshold__c` (blank = off for that family); incoming transfer legs are skipped so a transfer counts once |
| **Balances corrected** overnight and **failed nightly runs** for the family                | Audit trail (`BALANCE_DRIFT_FIXED`, `BALANCE_RECONCILE_FAILED`, `DAILY_DUES_FAILED`)                                           |
| Failed background Apex jobs in the last 24 hours                                           | `AsyncApexJob`                                                                                                                 |
| Families with no active Family Admin                                                       | Noted, because their dues can't be checked                                                                                     |

## Channels

| Channel             | Arrives as                                                                                       | Cost                                                       | Set up                                                            |
| ------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- | ----------------------------------------------------------------- |
| **Salesforce push** | Phone notification from the Salesforce app (and the desktop bell); tap opens the Owner Workspace | Free                                                       | Nothing — allow notifications for the Salesforce app on the phone |
| **Email**           | Plain-text email to each recipient's Salesforce email                                            | Free (internal-user email doesn't use the daily allowance) | Nothing (Setup → Deliverability must allow all email)             |
| **Telegram**        | Message from your own bot                                                                        | Free                                                       | Once, below                                                       |

Recipients for push and email: every active user with the **VKF Platform Admin** permission set.

## Settings — Setup → Custom Settings → VKF Owner Alerts → Manage

Create the **org default** row the first time (without one, the defaults below apply).

| Field                       | Default | Meaning                                                         |
| --------------------------- | ------- | --------------------------------------------------------------- |
| Alerts On                   | ✓       | Master switch for all channels                                  |
| Salesforce Push             | ✓       |                                                                 |
| Email                       | ✓       |                                                                 |
| Telegram                    | ✗       | Turn on after the Telegram setup                                |
| Telegram Chat ID            | —       | Your chat ID (not a secret)                                     |
| Warn Days Ahead             | 3       | Overdue items are always included; 0–30                         |
| Repeat Overdue Every (Days) | 1       | Portal bell: how often an overdue reminder comes back; 0 = once |
| Portal Daily Summary Off    | ✗       | Portal bell: tick to stop the admins' daily summary             |

The **bell button** at the top of the Owner Workspace sends a test on every enabled channel and shows what happened to each one ("Push sent · Email sent · Telegram off").

## Telegram setup (once)

1. **Create the bot.** In Telegram, open **@BotFather** → `/newbot` → pick a name → copy the **token** it gives you (looks like `123456789:AA…`).
2. **Start a chat with your bot** — open it and send any message (a bot can't message you first).
3. **Find your chat ID.** In a browser open `https://api.telegram.org/bot<TOKEN>/getUpdates` and copy the number at `"chat":{"id": …}`.
4. **Deploy the credential once** (redeploying resets the URL you set in step 5):
   ```bash
   sf project deploy start --target-org VKFINANCE --metadata-dir config/telegram-alerts
   ```
5. **Put the token in Salesforce, not in code.** Setup → **Named Credentials** → **VKF Telegram** → Edit → URL: `https://api.telegram.org/bot<TOKEN>` (replace the placeholder) → Save.
6. **Grant the callout.** Assign the **VKF Telegram Alerts** permission set to yourself — the user who schedules the jobs.
7. **Switch it on.** VKF Owner Alerts → tick **Telegram**, paste the **Telegram Chat ID** → Save.
8. **Test.** Press the bell in the Owner Workspace.

The token lives only in the named credential URL in your org. The repo holds a placeholder (`PASTE_YOUR_BOT_TOKEN_IN_SETUP`).

## Scheduling

`scripts/apex/schedule-jobs.apex` now also schedules **VKF Owner Alerts** at 07:30 (safe to re-run; existing schedules are kept). The digest runs after the 06:00 dues job, so statuses are fresh.

## Family portal bell (06:00 dues job)

Separate from the owner digest, the families' own bell in VK Finance Portal gets:

| What                                                                                           | Who                                   | Behaviour                                                                                                                                                                                               |
| ---------------------------------------------------------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Daily summary** — "Today: 3 overdue, 1 due in the next 3 days", naming the first three items | Family Admin and Co-Admins            | One entry per day; the previous day's is removed. Tap opens Bills. Off with **Portal Daily Summary Off**                                                                                                |
| **Overdue reminders** — each overdue bill, EMI and card bill                                   | The responsible member and the admins | Re-posted every **Repeat Overdue Every (Days)** days (default 1 = daily) until paid; the older copy for the same item is removed, so the bell holds one current reminder per item. 0 = remind once only |

Card statements with **less than ₹1** left to pay count as paid everywhere (bell, Dues, digest, card screens) — paise left after rounding are never chased.

## WhatsApp

Not included. Sending to WhatsApp reliably requires the WhatsApp Business Platform (Meta Business account, a dedicated number, approved templates, per-message charges). Unofficial tools that drive a personal WhatsApp break its terms and risk a ban. If you set up the Business Platform later, it can be added as a fourth channel in `OwnerAlertService` without changing the digest.

## Troubleshooting

| Bell result / symptom                             | Fix                                                                                |
| ------------------------------------------------- | ---------------------------------------------------------------------------------- |
| "Alerts are switched off"                         | VKF Owner Alerts → Alerts On                                                       |
| Telegram: "Add your Telegram chat ID"             | Fill in Telegram Chat ID                                                           |
| Telegram: "HTTP 401 … check the bot token"        | The named credential URL has a wrong or missing token                              |
| Telegram: "HTTP 400: Bad Request: chat not found" | Wrong chat ID, or you haven't messaged the bot yet                                 |
| Telegram: "Could not reach Telegram…"             | Credential not deployed, or VKF Telegram Alerts not assigned                       |
| Email: "Email is blocked"                         | Setup → Deliverability → Access level: All email                                   |
| Push sent but nothing on the phone                | Allow notifications for the Salesforce app; sign in to the app at least once       |
| No morning digest                                 | Nothing needed attention, or the job isn't scheduled — re-run `schedule-jobs.apex` |

Failed channels are written to the audit trail as `OWNER_ALERT_FAILED`.
