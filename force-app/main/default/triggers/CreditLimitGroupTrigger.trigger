trigger CreditLimitGroupTrigger on Credit_Limit_Group__c(before update) {
    CreditLimitGroupGuard.validateGroups(Trigger.new, Trigger.oldMap);
}