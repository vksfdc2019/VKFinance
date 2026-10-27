/**
 * Ledger queries. Every query starts with Family__c = :fid and, for callers who can't see
 * the whole family, (Member__c = :selfId OR Account__c IN :scopeAccounts). Lists page with
 * a keyset cursor (date + transaction number), so deep pages cost the same as the first.
 */
public without sharing class TransactionSelector extends FamilyScopedSelector {
    public static final String FIELDS =
        'Id, Name, Type__c, Direction__c, Amount__c, Txn_Date__c, Account__c, Account__r.Name, Account__r.Type__c, ' +
        'Category__c, Member__c, Member__r.First_Name__c, Member__r.Last_Name__c, Payee__c, Notes__c, Payment_Mode__c, ' +
        'Reference_No__c, Status__c, Transfer_Group_Id__c, Counter_Transaction__c, Counter_Transaction__r.Account__r.Name, ' +
        'Source__c, Bill_Instance__c, EMI_Installment__c, CreatedDate';

    public class Filter {
        public Boolean wholeFamily = false;
        public Id selfId;
        public Set<Id> scopeAccountIds = new Set<Id>();
        public Date fromDate;
        public Date toDate;
        public Set<String> types;
        public Set<Id> accountIds;
        public Set<Id> categoryIds;
        public Id memberId;
        public String search;
        public Boolean includeVoid = false;
        public Date cursorDate;
        public String cursorName;

        public Filter copy() {
            Filter f = new Filter();
            f.wholeFamily = wholeFamily;
            f.selfId = selfId;
            f.scopeAccountIds = scopeAccountIds;
            f.memberId = memberId;
            f.accountIds = accountIds;
            return f;
        }
    }

    public TransactionSelector(UserContext ctx) {
        super(ctx);
    }

    /** A filter limited to what this caller may see. */
    public Filter scoped() {
        Filter f = new Filter();
        LedgerScope scope = new LedgerScope(ctx);
        f.wholeFamily = scope.wholeFamily();
        f.selfId = ctx.userId;
        if (!f.wholeFamily) {
            f.scopeAccountIds = new AccountSelector(ctx).visibleIds();
        }
        return f;
    }

    public Transaction__c byId(Id txnId) {
        List<Transaction__c> rows = txnId == null
            ? new List<Transaction__c>()
            : (List<Transaction__c>) Database.queryWithBinds(
                  'SELECT ' + FIELDS + ' FROM Transaction__c WHERE Id = :tid AND Family__c = :fid LIMIT 1',
                  new Map<String, Object>{ 'tid' => txnId, 'fid' => familyId },
                  AccessLevel.SYSTEM_MODE
              );
        if (rows.isEmpty()) {
            Boolean elsewhere = txnId != null &&
                [SELECT COUNT() FROM Transaction__c WHERE Id = :txnId AND Family__c != :familyId WITH SYSTEM_MODE] > 0;
            throw notFound('Transaction__c', txnId, elsewhere);
        }
        return rows[0];
    }

    public List<Transaction__c> byGroup(String groupId) {
        return (List<Transaction__c>) Database.queryWithBinds(
            'SELECT ' + FIELDS + ' FROM Transaction__c WHERE Transfer_Group_Id__c = :gid AND Family__c = :fid',
            new Map<String, Object>{ 'gid' => groupId, 'fid' => familyId },
            AccessLevel.SYSTEM_MODE
        );
    }

    public List<Transaction__c> page(Filter f, Integer pageSize) {
        Map<String, Object> binds = new Map<String, Object>();
        String soql = 'SELECT ' + FIELDS + ' FROM Transaction__c WHERE ' + whereClause(f, binds, true) +
            ' ORDER BY Txn_Date__c DESC, Name DESC LIMIT ' + Math.max(1, Math.min(pageSize, 201));
        return (List<Transaction__c>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    /** Aggregate over the filter (ignoring any cursor), e.g. ('Type__c t, SUM(Amount__c) s', f, 'Type__c'). */
    public List<AggregateResult> aggregate(String selectList, Filter f, String groupBy) {
        Map<String, Object> binds = new Map<String, Object>();
        String soql = 'SELECT ' + selectList + ' FROM Transaction__c WHERE ' + whereClause(f, binds, false) + ' GROUP BY ' + groupBy;
        return (List<AggregateResult>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    private String whereClause(Filter f, Map<String, Object> binds, Boolean withCursor) {
        List<String> parts = new List<String>{ 'Family__c = :fid' };
        binds.put('fid', familyId);
        if (!f.wholeFamily) {
            parts.add('(Member__c = :selfId OR Account__c IN :scopeAccounts)');
            binds.put('selfId', f.selfId);
            binds.put('scopeAccounts', f.scopeAccountIds == null ? new Set<Id>() : f.scopeAccountIds);
        }
        if (f.fromDate != null) {
            parts.add('Txn_Date__c >= :fromDate');
            binds.put('fromDate', f.fromDate);
        }
        if (f.toDate != null) {
            parts.add('Txn_Date__c <= :toDate');
            binds.put('toDate', f.toDate);
        }
        if (f.types != null && !f.types.isEmpty()) {
            parts.add('Type__c IN :types');
            binds.put('types', f.types);
        }
        if (f.accountIds != null) {
            parts.add('Account__c IN :accountIds');
            binds.put('accountIds', f.accountIds);
        }
        if (f.categoryIds != null) {
            parts.add('Category__c IN :categoryIds');
            binds.put('categoryIds', f.categoryIds);
        }
        if (f.memberId != null) {
            parts.add('Member__c = :memberId');
            binds.put('memberId', f.memberId);
        }
        if (f.includeVoid != true) {
            parts.add('Status__c != \'Void\'');
        }
        if (String.isNotBlank(f.search)) {
            parts.add('(Payee__c LIKE :q OR Notes__c LIKE :q OR Reference_No__c LIKE :q)');
            binds.put('q', '%' + f.search.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%');
        }
        if (withCursor && f.cursorDate != null && f.cursorName != null) {
            parts.add('(Txn_Date__c < :cursorDate OR (Txn_Date__c = :cursorDate AND Name < :cursorName))');
            binds.put('cursorDate', f.cursorDate);
            binds.put('cursorName', f.cursorName);
        }
        return String.join(parts, ' AND ');
    }
}
