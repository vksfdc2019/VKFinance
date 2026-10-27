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
System.debug('VKF jobs: ' + [SELECT CronJobDetail.Name, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE 'VKF %']);
