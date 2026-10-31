/**
 * The archive run, started daily by ArchiveJob as three batch passes, each starting the next
 * from finish() (batch hand-offs aren't limited like chained queueables, which Developer
 * Edition caps at five):
 *   COPY_RECORDS    - per family: write new or changed records to the Archive_Record__b big object
 *   WRITE_SHEETS    - per family: rebuild the changed months' Google Sheets and update Archive_Log__c
 *   REMOVE_ARCHIVED - per archive log: remove a month that is copied, exported and past the grace period
 * Scope is one family (or one month) per execution: big-object writes, Google callouts and
 * ordinary DML each need their own transaction, and a big-object read must precede any DML.
 * A failure is logged and the pass moves on.
 */
public without sharing class ArchiveWorker implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    public static final Integer MONTHS_PER_FAMILY = 10;

    public enum Step {
        COPY_RECORDS,
        WRITE_SHEETS,
        REMOVE_ARCHIVED
    }

    private final Step phase;
    /** Family id -> months that gained records during COPY_RECORDS. */
    private final Map<Id, Set<String>> touched;

    public ArchiveWorker(Step phase, Map<Id, Set<String>> touched) {
        this.phase = phase;
        this.touched = touched == null ? new Map<Id, Set<String>>() : touched;
    }

    public static Id start() {
        // Tests may run only one batch execution, so they take every family at once.
        return Database.executeBatch(new ArchiveWorker(Step.COPY_RECORDS, null), Test.isRunningTest() ? 200 : 1);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (phase == Step.REMOVE_ARCHIVED) {
            Date cut = ArchiveService.cutoff(Date.today());
            Datetime graceEnd = Datetime.now().addDays(-ArchiveService.graceDays());
            return Database.getQueryLocator([
                SELECT Id, Family__c, Month__c, Unique_Key__c, Status__c, Copied_At__c, Exported_At__c, Purged__c, Kept__c
                FROM Archive_Log__c
                WHERE Status__c = 'Copied' AND Month__c < :cut AND Copied_At__c <= :graceEnd AND Family__r.Status__c = 'Active'
                WITH SYSTEM_MODE ORDER BY Family__c, Month__c
            ]);
        }
        return Database.getQueryLocator([SELECT Id FROM Family__c WHERE Status__c = 'Active' WITH SYSTEM_MODE ORDER BY CreatedDate]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        for (SObject row : scope) {
            Id familyId = phase == Step.REMOVE_ARCHIVED ? (Id) row.get('Family__c') : row.Id;
            try {
                if (phase == Step.COPY_RECORDS) {
                    copy(familyId);
                } else if (phase == Step.WRITE_SHEETS) {
                    writeSheets(familyId);
                } else {
                    remove((Archive_Log__c) row);
                }
            } catch (Exception e) {
                // Logging is a DML publish; after a big-object write it may itself be refused.
                try {
                    AuditService.log(familyId, null, 'ARCHIVE_FAILED', 'Family__c', familyId, (phase + ': ' + e.getMessage()).left(1000));
                } catch (Exception ignored) {
                    System.debug(LoggingLevel.ERROR, 'Archive ' + phase + ' failed for ' + familyId + ': ' + e.getMessage());
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (Test.isRunningTest()) {
            return;
        }
        if (phase == Step.COPY_RECORDS) {
            Database.executeBatch(new ArchiveWorker(Step.WRITE_SHEETS, touched), 1);
        } else if (phase == Step.WRITE_SHEETS) {
            Database.executeBatch(new ArchiveWorker(Step.REMOVE_ARCHIVED, null), 1);
        }
    }

    private void copy(Id familyId) {
        ArchiveService.Collected c = ArchiveService.collect(familyId, Date.today());
        ArchiveStore.save(c.rows);
        if (!c.touched.isEmpty()) {
            touched.put(familyId, c.touched);
        }
    }

    private void writeSheets(Id familyId) {
        Set<String> changed = touched.containsKey(familyId) ? touched.get(familyId) : new Set<String>();
        Set<String> months = ArchiveExporter.pendingExport(familyId);
        months.addAll(changed);
        if (months.isEmpty()) {
            return;
        }
        List<String> ordered = new List<String>(months);
        ordered.sort();
        // Stay well inside the callout limit; any rest is picked up as pending on the next run.
        while (ordered.size() > MONTHS_PER_FAMILY) {
            ordered.remove(ordered.size() - 1);
        }
        ArchiveExporter.export(familyId, ordered, changed);
    }

    private void remove(Archive_Log__c log) {
        if (ArchiveService.googleCopy() && (log.Exported_At__c == null || log.Exported_At__c < log.Copied_At__c)) {
            return;
        }
        ArchiveService.PurgeResult r = ArchiveService.purgeMonth(log);
        update as system new Archive_Log__c(
            Id = log.Id, Status__c = 'Purged', Purged_At__c = Datetime.now(),
            Purged__c = LedgerUtil.zeroIfNull(log.Purged__c) + r.removed, Kept__c = r.kept
        );
        AuditService.log(log.Family__c, null, 'ARCHIVE_PURGED', 'Archive_Log__c', log.Id, ArchiveService.monthKey(log.Month__c) + ': removed ' + r.removed + ', kept ' + r.kept);
    }
}