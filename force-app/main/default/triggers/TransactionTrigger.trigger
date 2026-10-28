/**
 * Blocks entries dated in an archived period, and keeps account balances in step with every
 * insert, edit, void, delete and undelete.
 */
trigger TransactionTrigger on Transaction__c(before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        ArchiveService.assertOpen(Trigger.new, Trigger.oldMap);
        return;
    }
    LedgerBalances.apply(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap);
}
