// Removes VK Finance scheduled jobs so classes they depend on can be deployed.
// Re-run schedule-jobs.apex after the deploy.
for (CronTrigger ct : [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'VKF %']) {
    System.abortJob(ct.Id);
    System.debug('Unscheduled ' + ct.CronJobDetail.Name);
}
