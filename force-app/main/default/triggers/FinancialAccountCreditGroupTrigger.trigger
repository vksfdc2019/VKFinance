trigger FinancialAccountCreditGroupTrigger on Financial_Account__c(before insert, before update, after insert, after update) {
    if (Trigger.isBefore) CreditLimitGroupGuard.validate(Trigger.new, Trigger.isInsert ? null : Trigger.oldMap);
    else CreditLimitGroupGuard.touchVersions(Trigger.new, Trigger.isInsert ? null : Trigger.oldMap);
}