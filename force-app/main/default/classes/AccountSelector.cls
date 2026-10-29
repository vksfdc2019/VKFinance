public without sharing class AccountSelector extends FamilyScopedSelector {
    private static final String FIELDS =
        'Id, Name, Family__c, Owner_Member__c, Owner_Member__r.First_Name__c, Owner_Member__r.Last_Name__c, Type__c, ' +
        'Credit_Limit_Group__c, Institution__c, Last4__c, Opening_Balance__c, Archived_Net__c, Opening_Date__c, Current_Balance__c, Credit_Limit__c, ' +
        'Statement_Day__c, Payment_Due_Days__c, Min_Due_Pct__c, Is_Shared__c, Status__c, Color__c, Sort_Order__c, CreatedDate';

    public AccountSelector(UserContext ctx) {
        super(ctx);
    }

    public List<Financial_Account__c> inFamily(Boolean includeClosed) {
        Map<String, Object> binds = new Map<String, Object>{ 'fid' => familyId };
        String soql = 'SELECT ' + FIELDS + ' FROM Financial_Account__c WHERE Family__c = :fid' +
            (includeClosed ? '' : ' AND Status__c = \'Active\'') +
            ' ORDER BY Status__c, Sort_Order__c NULLS LAST, Name LIMIT 500';
        return (List<Financial_Account__c>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    /** Accounts the caller can see, in display order. */
    public List<Financial_Account__c> visible(Boolean includeClosed) {
        LedgerScope scope = new LedgerScope(ctx);
        List<Financial_Account__c> result = new List<Financial_Account__c>();
        for (Financial_Account__c a : inFamily(includeClosed)) {
            if (scope.canSeeAccount(a)) {
                result.add(a);
            }
        }
        return result;
    }

    public Set<Id> visibleIds() {
        return new Map<Id, Financial_Account__c>(visible(true)).keySet();
    }

    public Financial_Account__c byId(Id accountId) {
        Map<Id, Financial_Account__c> found = byIds(new Set<Id>{ accountId });
        if (!found.containsKey(accountId)) {
            Boolean elsewhere = accountId != null &&
                [SELECT COUNT() FROM Financial_Account__c WHERE Id = :accountId AND Family__c != :familyId WITH SYSTEM_MODE] > 0;
            throw notFound('Financial_Account__c', accountId, elsewhere);
        }
        return found.get(accountId);
    }

    public Map<Id, Financial_Account__c> byIds(Set<Id> accountIds) {
        accountIds.remove(null);
        Map<String, Object> binds = new Map<String, Object>{ 'fid' => familyId, 'ids' => accountIds };
        return new Map<Id, Financial_Account__c>(
            (List<Financial_Account__c>) Database.queryWithBinds(
                'SELECT ' + FIELDS + ' FROM Financial_Account__c WHERE Family__c = :fid AND Id IN :ids',
                binds,
                AccessLevel.SYSTEM_MODE
            )
        );
    }

    public Boolean hasTransactions(Id accountId) {
        return [SELECT COUNT() FROM Transaction__c WHERE Account__c = :accountId AND Family__c = :familyId WITH SYSTEM_MODE LIMIT 1] > 0;
    }

    public Integer countAccounts() {
        return [SELECT COUNT() FROM Financial_Account__c WHERE Family__c = :familyId WITH SYSTEM_MODE];
    }
}
