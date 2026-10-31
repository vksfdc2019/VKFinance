/**
 * Keeps usernames normalised (trimmed, lower case) and the Name field in sync,
 * whether the record changes through the portal or the internal console.
 */
public without sharing class PortalUserTriggerHandler {
    public static void beforeSave(List<Portal_User__c> users) {
        for (Portal_User__c u : users) {
            if (u.Username__c != null) {
                u.Username__c = u.Username__c.trim().toLowerCase();
            }
            String fullName = ((u.First_Name__c == null ? '' : u.First_Name__c) + ' ' + (u.Last_Name__c == null ? '' : u.Last_Name__c)).trim();
            if (String.isNotBlank(fullName)) {
                u.Name = fullName.left(80);
            }
        }
    }
}