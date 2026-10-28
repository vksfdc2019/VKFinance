// Schedules VK Finance background jobs. Safe to re-run: existing schedules are kept.
Set<String> existing = new Set<String>();
for (CronTrigger ct : [SELECT CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'VKF %']) {
    existing.add(ct.CronJobDetail.Name);
}
if (!existing.contains('VKF Session Cleanup')) {
    System.schedule('VKF Session Cleanup', '0 0 * * * ?', new SessionCleanupJob());
}
if (!existing.contains('VKF Daily Dues')) {
    // 06:00 every day: bills, EMIs, card statements, recurring entries, reminders.
    System.schedule('VKF Daily Dues', '0 0 6 * * ?', new DailyDuesBatch());
}
if (!existing.contains('VKF Balance Reconcile')) {
    // 02:00 every day: recompute balances from the ledger and fix any drift.
    System.schedule('VKF Balance Reconcile', '0 0 2 * * ?', new BalanceReconcileJob());
}
if (!existing.contains('VKF Retention Purge')) {
    // 04:00 on Sundays: old notifications, spent tokens, surplus password history, rate-limit rows.
    System.schedule('VKF Retention Purge', '0 0 4 ? * SUN', new RetentionPurgeJob());
}
if (!existing.contains('VKF Security Digest')) {
    // 07:00 on Mondays: one email to whoever runs this script (the platform owner).
    System.schedule('VKF Security Digest', '0 0 7 ? * MON', new SecurityDigestJob());
}
System.debug('VKF jobs: ' + [SELECT CronJobDetail.Name, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE 'VKF %']);
