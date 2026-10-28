/**
 * The archive steps, one per queueable execution, started daily by ArchiveJob. For each family:
 *   COPY_RECORDS    - write new or changed records to the Archive_Record__b big object
 *   WRITE_SHEETS    - rebuild those months' Google Sheets and update Archive_Log__c (a few months per step)
 *   REMOVE_ARCHIVED - remove months that are copied, exported and past the grace period
 * Big-object writes, Google callouts and ordinary DML each need their own transaction, which
 * is why the steps are separate. A failing family is logged and the chain moves on.
 */
public without sharing class ArchiveWorker implements Queueable, Database.AllowsCallouts {
    public static final Integer MONTHS_PER_EXPORT = 3;
    public static final Integer MONTHS_PER_PURGE = 3;

    public enum Step {
        COPY_RECORDS,
        WRITE_SHEETS,
        REMOVE_ARCHIVED
    }

    private final List<Id> familyIds;
    private final Integer index;
    private final Step phase;
    private final List<String> months;
    private final Set<String> touched;

    public ArchiveWorker(List<Id> familyIds, Integer index, Step phase, List<String> months, Set<String> touched) {
        this.familyIds = familyIds;
        this.index = index;
        this.phase = phase;
        this.months = months;
        this.touched = touched;
    }

    public void execute(QueueableContext qc) {
        Id familyId = familyIds[index];
        ArchiveWorker next;
        try {
            next = runStage(familyId);
        } catch (Exception e) {
            // Nothing else ran in this transaction, so logging the failure is safe.
            AuditService.log(familyId, null, 'ARCHIVE_FAILED', 'Family__c', familyId, (phase + ': ' + e.getMessage()).left(1000));
            next = nextFamily();
        }
        if (next != null && !Test.isRunningTest()) {
            System.enqueueJob(next);
        }
    }

    private ArchiveWorker runStage(Id familyId) {
        if (phase == Step.COPY_RECORDS) {
            ArchiveService.Collected c = ArchiveService.collect(familyId, Date.today());
            Set<String> pending = ArchiveExporter.pendingExport(familyId);
            ArchiveStore.save(c.rows);
            pending.addAll(c.touched);
            List<String> toExport = new List<String>(pending);
            toExport.sort();
            return toExport.isEmpty()
                ? new ArchiveWorker(familyIds, index, Step.REMOVE_ARCHIVED, new List<String>(), new Set<String>())
                : new ArchiveWorker(familyIds, index, Step.WRITE_SHEETS, toExport, c.touched);
        }
        if (phase == Step.WRITE_SHEETS) {
            List<String> batch = new List<String>();
            List<String> rest = new List<String>();
            for (String m : months) {
                if (batch.size() < MONTHS_PER_EXPORT) {
                    batch.add(m);
                } else {
                    rest.add(m);
                }
            }
            ArchiveExporter.export(familyId, batch, touched);
            return rest.isEmpty()
                ? new ArchiveWorker(familyIds, index, Step.REMOVE_ARCHIVED, new List<String>(), new Set<String>())
                : new ArchiveWorker(familyIds, index, Step.WRITE_SHEETS, rest, touched);
        }
        List<Archive_Log__c> due = ArchiveService.purgeable(familyId, Date.today(), MONTHS_PER_PURGE + 1);
        if (due.isEmpty()) {
            return nextFamily();
        }
        // One month per transaction keeps each purge well inside the DML limits.
        Archive_Log__c log = due[0];
        ArchiveService.PurgeResult r = ArchiveService.purgeMonth(log);
        update as system new Archive_Log__c(
            Id = log.Id, Status__c = 'Purged', Purged_At__c = Datetime.now(),
            Purged__c = LedgerUtil.zeroIfNull(log.Purged__c) + r.removed, Kept__c = r.kept
        );
        AuditService.log(familyId, null, 'ARCHIVE_PURGED', 'Archive_Log__c', log.Id, ArchiveService.monthKey(log.Month__c) + ': removed ' + r.removed + ', kept ' + r.kept);
        return due.size() > 1 ? new ArchiveWorker(familyIds, index, Step.REMOVE_ARCHIVED, new List<String>(), new Set<String>()) : nextFamily();
    }

    private ArchiveWorker nextFamily() {
        return index + 1 < familyIds.size() ? new ArchiveWorker(familyIds, index + 1, Step.COPY_RECORDS, new List<String>(), new Set<String>()) : null;
    }
}
