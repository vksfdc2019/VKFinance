/**
 * 02:00 daily ("VKF Balance Reconcile"): recomputes every account balance from the ledger, one
 * family per batch execution, fixes any drift and records each fix in the audit trail so the
 * weekly security digest can report it. Balances are kept incrementally by the transaction
 * trigger; this is the safety net.
 */
public without sharing class BalanceReconcileJob implements Database.Batchable<SObject>, Schedulable {
    public void execute(SchedulableContext sc) {
        // One family per execution in production; tests may run only one execution in total.
        Database.executeBatch(new BalanceReconcileJob(), Test.isRunningTest() ? 200 : 1);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id FROM Family__c WHERE Status__c = 'Active' WITH SYSTEM_MODE]);
    }

    public void execute(Database.BatchableContext bc, List<Family__c> scope) {
        for (Family__c f : scope) {
            Savepoint sp = Database.setSavepoint();
            try {
                reconcileFamily(f.Id);
            } catch (Exception e) {
                Database.rollback(sp);
                AuditService.log(f.Id, null, 'BALANCE_RECONCILE_FAILED', 'Family__c', f.Id, e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
    }

    /** Returns how many balances were wrong (and are now fixed). */
    public static Integer reconcileFamily(Id familyId) {
        Set<Id> accountIds = new Map<Id, Financial_Account__c>(
                [SELECT Id FROM Financial_Account__c WHERE Family__c = :familyId WITH SYSTEM_MODE]
            )
            .keySet();
        if (accountIds.isEmpty()) {
            return 0;
        }
        List<Financial_Account__c> drifted = LedgerBalances.reconcile(accountIds);
        if (drifted.isEmpty()) {
            return 0;
        }
        Map<Id, Financial_Account__c> fixedRows = new Map<Id, Financial_Account__c>(
            [SELECT Id, Current_Balance__c FROM Financial_Account__c WHERE Id IN :new Map<Id, Financial_Account__c>(drifted).keySet() WITH SYSTEM_MODE]
        );
        for (Financial_Account__c a : drifted) {
            AuditService.log(
                familyId,
                null,
                'BALANCE_DRIFT_FIXED',
                'Financial_Account__c',
                a.Id,
                a.Name + ': ' + LedgerUtil.zeroIfNull(a.Current_Balance__c) + ' -> ' + fixedRows.get(a.Id).Current_Balance__c
            );
        }
        return drifted.size();
    }
}
