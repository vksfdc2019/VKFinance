/**
 * Runs DuesProcessor for every active family, one family per batch execution, so each
 * family gets its own governor limits and one family's failure can't affect another.
 * Scheduled daily ("VKF Daily Dues"); also purges old read notifications.
 */
public without sharing class DailyDuesBatch implements Database.Batchable<SObject>, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id FROM Family__c WHERE Status__c = 'Active' WITH SYSTEM_MODE]);
    }

    public void execute(Database.BatchableContext bc, List<Family__c> scope) {
        for (Family__c f : scope) {
            Savepoint sp = Database.setSavepoint();
            try {
                DuesProcessor.run(f.Id, Date.today());
            } catch (Exception e) {
                Database.rollback(sp);
                System.debug(LoggingLevel.ERROR, 'Daily dues failed for ' + f.Id + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
                AuditService.log(f.Id, null, 'DAILY_DUES_FAILED', 'Family__c', f.Id, e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        NotificationService.purge();
    }

    public void execute(SchedulableContext sc) {
        // One family per execution in production; tests may run only one execution in total.
        Database.executeBatch(new DailyDuesBatch(), Test.isRunningTest() ? 200 : 1);
    }
}