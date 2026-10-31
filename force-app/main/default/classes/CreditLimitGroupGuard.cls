/** Enforces membership integrity even for direct Salesforce writes; ledger balance updates require no queries. */
public without sharing class CreditLimitGroupGuard {
    public static void validate(List<Financial_Account__c> rows, Map<Id, Financial_Account__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        List<Financial_Account__c> changed = new List<Financial_Account__c>();
        for (Financial_Account__c a : rows) {
            if (a.Credit_Limit_Group__c == null) continue;
            Financial_Account__c old = oldMap == null ? null : oldMap.get(a.Id);
            if (old != null && old.Credit_Limit_Group__c == a.Credit_Limit_Group__c && old.Type__c == a.Type__c && old.Family__c == a.Family__c) continue;
            ids.add(a.Credit_Limit_Group__c); changed.add(a);
        }
        if (ids.isEmpty()) return;
        Map<Id, Credit_Limit_Group__c> groups = new Map<Id, Credit_Limit_Group__c>([
            SELECT Id, Family__c, Active__c FROM Credit_Limit_Group__c WHERE Id IN :ids WITH SYSTEM_MODE
        ]);
        for (Financial_Account__c a : changed) {
            Credit_Limit_Group__c groupRow = groups.get(a.Credit_Limit_Group__c);
            if (a.Type__c != 'Credit Card' || groupRow == null || groupRow.Family__c != a.Family__c || !groupRow.Active__c)
                a.addError('Choose an active credit-limit group in the same family for a credit-card account.');
        }
    }
    /** Direct membership edits also invalidate stale group editors. Balance-only writes do nothing. */
    public static void touchVersions(List<Financial_Account__c> rows, Map<Id, Financial_Account__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Financial_Account__c a : rows) {
            Id beforeId = oldMap == null ? null : oldMap.get(a.Id).Credit_Limit_Group__c;
            if (beforeId == a.Credit_Limit_Group__c) continue;
            if (beforeId != null) ids.add(beforeId);
            if (a.Credit_Limit_Group__c != null) ids.add(a.Credit_Limit_Group__c);
        }
        if (ids.isEmpty()) return;
        List<Credit_Limit_Group__c> groups = [SELECT Id, Version__c FROM Credit_Limit_Group__c WHERE Id IN :ids WITH SYSTEM_MODE FOR UPDATE];
        // The group trigger advances the version from the locked database value.
        update as system groups;
    }

    public static void validateGroups(List<Credit_Limit_Group__c> rows, Map<Id, Credit_Limit_Group__c> oldMap) {
        Set<Id> guarded = new Set<Id>();
        for (Credit_Limit_Group__c groupRow : rows) {
            Credit_Limit_Group__c old = oldMap.get(groupRow.Id);
            groupRow.Version__c = LedgerUtil.zeroIfNull(old.Version__c) + 1;
            if (old.Family__c != groupRow.Family__c || (old.Active__c && !groupRow.Active__c)) guarded.add(groupRow.Id);
        }
        if (guarded.isEmpty()) return;
        Set<Id> linked = new Set<Id>();
        for (Financial_Account__c a : [SELECT Credit_Limit_Group__c FROM Financial_Account__c WHERE Credit_Limit_Group__c IN :guarded WITH SYSTEM_MODE]) linked.add(a.Credit_Limit_Group__c);
        for (Credit_Limit_Group__c groupRow : rows) if (linked.contains(groupRow.Id))
            groupRow.addError('Unlink all cards before archiving a shared limit or moving it to another family.');
    }
}