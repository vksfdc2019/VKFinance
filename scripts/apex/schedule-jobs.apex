// Schedules VK Finance background jobs. Safe to re-run: existing schedules are kept.
Set<String> existing = new Set<String>();
for (CronTrigger ct : [SELECT CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'VKF %']) {
    existing.add(ct.CronJobDetail.Name);
}
if (!existing.contains('VKF Session Cleanup')) {
    System.schedule('VKF Session Cleanup', '0 0 * * * ?', new SessionCleanupJob());
}
System.debug('VKF jobs: ' + [SELECT CronJobDetail.Name, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE 'VKF %']);
