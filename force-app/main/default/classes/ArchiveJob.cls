/**
 * 01:30 daily ("VKF Archive"): starts ArchiveWorker for the active families, which copies old
 * records to the big object and Google Sheets and then removes what is safely archived.
 * (A class can't be both Schedulable and Queueable, hence the two classes.)
 */
public without sharing class ArchiveJob implements Schedulable {
    public void execute(SchedulableContext sc) {
        List<Id> ids = new List<Id>(new Map<Id, Family__c>([SELECT Id FROM Family__c WHERE Status__c = 'Active' WITH SYSTEM_MODE ORDER BY CreatedDate]).keySet());
        if (!ids.isEmpty()) {
            System.enqueueJob(new ArchiveWorker(ids, 0, ArchiveWorker.Step.COPY_RECORDS, new List<String>(), new Set<String>()));
        }
    }
}
