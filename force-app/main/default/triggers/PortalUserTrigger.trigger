trigger PortalUserTrigger on Portal_User__c(before insert, before update) {
    PortalUserTriggerHandler.beforeSave(Trigger.new);
}