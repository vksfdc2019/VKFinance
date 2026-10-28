// Optional Phase 6 maintenance only. Existing VKF schedules are left untouched.
if ([SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'VKF Enhancement Maintenance'] == 0) {
    System.schedule('VKF Enhancement Maintenance', '0 20 3 ? * SUN', new EnhancementMaintenanceJob());
}
