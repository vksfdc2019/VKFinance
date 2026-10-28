/**
 * Keeps Financial_Account__c.Current_Balance__c in step with the ledger.
 *
 * apply() runs from TransactionTrigger and moves each affected balance by the change in
 * that account's net effect, so posting cost doesn't grow with history. Accounts are
 * locked FOR UPDATE first, so two entries saved at once can't lose an update.
 * recalculate() rebuilds balances from the whole ledger as a safety net.
 *
 * Net effect: Credit = +amount, Debit = -amount, Void = 0. Assets hold opening + net;
 * liabilities (cards, loans) owe opening - net, because spending on a card is a Debit.
 */
public without sharing class LedgerBalances {
    public static Decimal netEffect(Transaction__c t) {
        if (t == null || t.Status__c == 'Void' || t.Amount__c == null || t.Account__c == null) {
            return 0;
        }
        return t.Direction__c == 'Credit' ? t.Amount__c : -t.Amount__c;
    }

    public static void apply(List<Transaction__c> newRows, Map<Id, Transaction__c> oldMap) {
        Map<Id, Decimal> deltas = new Map<Id, Decimal>();
        if (newRows != null) {
            for (Transaction__c t : newRows) {
                add(deltas, t.Account__c, netEffect(t));
            }
        }
        if (oldMap != null) {
            for (Transaction__c t : oldMap.values()) {
                add(deltas, t.Account__c, -netEffect(t));
            }
        }
        for (Id accountId : new List<Id>(deltas.keySet())) {
            if (deltas.get(accountId) == 0) {
                deltas.remove(accountId);
            }
        }
        if (deltas.isEmpty()) {
            return;
        }
        Set<Id> accountIds = deltas.keySet();
        List<Financial_Account__c> accounts = [
            SELECT Id, Type__c, Opening_Balance__c, Current_Balance__c
            FROM Financial_Account__c
            WHERE Id IN :accountIds
            WITH SYSTEM_MODE
            FOR UPDATE
        ];
        for (Financial_Account__c a : accounts) {
            Decimal current = a.Current_Balance__c == null ? LedgerUtil.zeroIfNull(a.Opening_Balance__c) : a.Current_Balance__c;
            Decimal net = deltas.get(a.Id);
            a.Current_Balance__c = LedgerUtil.isLiability(a.Type__c) ? current - net : current + net;
        }
        update as system accounts;
    }

    /** Rebuilds balances from opening balance plus every non-void transaction. */
    public static void recalculate(Set<Id> accountIds) {
        List<Financial_Account__c> accounts = lockAccounts(accountIds);
        Map<Id, Decimal> expected = expected(accounts);
        for (Financial_Account__c a : accounts) {
            a.Current_Balance__c = expected.get(a.Id);
        }
        update as system accounts;
    }

    /**
     * Nightly check: recomputes each balance from the ledger and fixes only the ones that drifted.
     * Returns the accounts that were wrong, with Current_Balance__c still holding the old value.
     */
    public static List<Financial_Account__c> reconcile(Set<Id> accountIds) {
        List<Financial_Account__c> accounts = lockAccounts(accountIds);
        Map<Id, Decimal> expected = expected(accounts);
        List<Financial_Account__c> drifted = new List<Financial_Account__c>();
        List<Financial_Account__c> fixes = new List<Financial_Account__c>();
        for (Financial_Account__c a : accounts) {
            Decimal right = expected.get(a.Id);
            if (LedgerUtil.zeroIfNull(a.Current_Balance__c) != right) {
                drifted.add(a.clone(true, true));
                fixes.add(new Financial_Account__c(Id = a.Id, Current_Balance__c = right));
            }
        }
        update as system fixes;
        return drifted;
    }

    private static List<Financial_Account__c> lockAccounts(Set<Id> accountIds) {
        return [
            SELECT Id, Name, Family__c, Type__c, Opening_Balance__c, Current_Balance__c
            FROM Financial_Account__c
            WHERE Id IN :accountIds
            WITH SYSTEM_MODE
            FOR UPDATE
        ];
    }

    private static Map<Id, Decimal> expected(List<Financial_Account__c> accounts) {
        Map<Id, Decimal> net = new Map<Id, Decimal>();
        Set<Id> ids = new Map<Id, Financial_Account__c>(accounts).keySet();
        for (AggregateResult ar : [
            SELECT Account__c acct, Direction__c dir, SUM(Amount__c) total
            FROM Transaction__c
            WHERE Account__c IN :ids AND Status__c != 'Void'
            WITH SYSTEM_MODE
            GROUP BY Account__c, Direction__c
        ]) {
            Decimal total = LedgerUtil.zeroIfNull(ar.get('total'));
            add(net, (Id) ar.get('acct'), (String) ar.get('dir') == 'Credit' ? total : -total);
        }
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        for (Financial_Account__c a : accounts) {
            Decimal opening = LedgerUtil.zeroIfNull(a.Opening_Balance__c);
            Decimal n = net.containsKey(a.Id) ? net.get(a.Id) : 0;
            result.put(a.Id, LedgerUtil.isLiability(a.Type__c) ? opening - n : opening + n);
        }
        return result;
    }

    private static void add(Map<Id, Decimal> totals, Id key, Decimal value) {
        if (key == null) {
            return;
        }
        totals.put(key, (totals.containsKey(key) ? totals.get(key) : 0) + value);
    }
}
