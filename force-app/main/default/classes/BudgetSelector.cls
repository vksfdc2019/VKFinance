public without sharing class BudgetSelector extends FamilyScopedSelector {
    public BudgetSelector(UserContext ctx) {
        super(ctx);
    }

    public Budget__c forMonth(Date monthStart) {
        Id fid = familyId;
        List<Budget__c> rows = [
            SELECT Id, Name, Month__c, Notes__c, (SELECT Id, Category__c, Planned__c FROM Lines__r)
            FROM Budget__c
            WHERE Family__c = :fid AND Month__c = :monthStart
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static String uniqueKey(Id familyId, Date monthStart) {
        return familyId + '-' + LedgerUtil.monthKey(monthStart);
    }
}
