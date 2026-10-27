/** Keeps account balances in step with every insert, edit, void, delete and undelete. */
trigger TransactionTrigger on Transaction__c(after insert, after update, after delete, after undelete) {
    LedgerBalances.apply(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap);
}
