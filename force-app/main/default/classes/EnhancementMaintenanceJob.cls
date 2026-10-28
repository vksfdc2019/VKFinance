/** Optional weekly housekeeping. Financial entries, receipt photos and approval history are retained. */
public without sharing class EnhancementMaintenanceJob implements Database.Batchable<SObject>, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = Datetime.now().addDays(-30);
        return Database.getQueryLocator([SELECT Id, Family__c FROM Statement_Import__c
            WHERE CreatedDate < :cutoff AND Status__c IN ('Draft','Partial','Completed','Cancelled') WITH SYSTEM_MODE]);
    }
    public void execute(Database.BatchableContext bc, List<Statement_Import__c> scope) {
        for (Statement_Import__c batch : scope) {
            // Keep the job away from a concurrently started retry; lock and recheck status.
            Statement_Import__c locked = [SELECT Id, Status__c FROM Statement_Import__c WHERE Id = :batch.Id AND Family__c = :batch.Family__c WITH SYSTEM_MODE FOR UPDATE];
            if (locked.Status__c == 'Processing') continue;
            delete as system [SELECT Id FROM Statement_Row__c WHERE Import__c = :batch.Id AND Family__c = :batch.Family__c WITH SYSTEM_MODE LIMIT 500];
            update as system new Statement_Import__c(Id = batch.Id, Status__c = 'Archived', Error__c = 'Reviewed row details were removed after 30 days. Ledger entries are retained.');
            AuditService.log(batch.Family__c, null, 'STATEMENT_ARCHIVED', 'Statement_Import__c', batch.Id, null);
        }
    }
    public void finish(Database.BatchableContext bc) {
        Date cutoff = Date.today().addDays(-30);
        delete as system [SELECT Id FROM Insight_Preference__c WHERE Hidden_Until__c < :cutoff WITH SYSTEM_MODE LIMIT 5000];
    }
    public void execute(SchedulableContext sc) { Database.executeBatch(new EnhancementMaintenanceJob(), 1); }
}
