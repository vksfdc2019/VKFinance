/**
 * Credit-card statements. A statement freezes the card's outstanding at the cycle end;
 * what has been paid since (and so its status) is always read from the ledger.
 */
public without sharing class CardStatementService {
    public static final Decimal MINIMUM_FLOOR = 200;

    /** Creates the statement for each card's most recent closed cycle, if missing. */
    public static Integer generate(Id familyId, Date today) {
        List<Financial_Account__c> cards = [
            SELECT Id, Family__c, Opening_Balance__c, Archived_Net__c, Statement_Day__c, Payment_Due_Days__c, Min_Due_Pct__c, Credit_Limit__c, Type__c
            FROM Financial_Account__c
            WHERE Family__c = :familyId AND Type__c = 'Credit Card' AND Status__c = 'Active' AND Statement_Day__c != NULL
            WITH SYSTEM_MODE
        ];
        Map<String, Card_Statement__c> byKey = new Map<String, Card_Statement__c>();
        for (Financial_Account__c card : cards) {
            FinanceDtos.CardCycle cycle = AccountService.cardCycle(card, today);
            Date cycleEnd = cycle.lastStatementDate;
            Date previousEnd = AccountService.cardCycle(card, cycleEnd).lastStatementDate;
            Decimal owed = Math.max(0, balanceAsOf(card, cycleEnd));
            Decimal pct = card.Min_Due_Pct__c == null ? 5 : card.Min_Due_Pct__c;
            Decimal minimum = owed == 0 ? 0 : Math.min(owed, Math.max(MINIMUM_FLOOR, (owed * pct / 100).setScale(0, RoundingMode.CEILING)));
            Integer dueDays = card.Payment_Due_Days__c == null ? 20 : card.Payment_Due_Days__c.intValue();
            String key = card.Id + '-' + String.valueOf(cycleEnd);
            byKey.put(key, new Card_Statement__c(
                Family__c = familyId, Account__c = card.Id, Cycle_Start__c = previousEnd.addDays(1), Cycle_End__c = cycleEnd,
                Statement_Amount__c = owed, Minimum_Due__c = minimum, Due_Date__c = cycleEnd.addDays(dueDays), Unique_Key__c = key
            ));
        }
        Set<String> keys = byKey.keySet();
        for (Card_Statement__c existing : [SELECT Unique_Key__c FROM Card_Statement__c WHERE Unique_Key__c IN :keys WITH SYSTEM_MODE]) {
            byKey.remove(existing.Unique_Key__c);
        }
        insert as system byKey.values();
        return byKey.size();
    }

    /** What the card owed at the end of a day: opening + debits - credits up to and including it (archived entries included). */
    public static Decimal balanceAsOf(Financial_Account__c card, Date asOf) {
        Decimal owed = LedgerUtil.zeroIfNull(card.Opening_Balance__c) - LedgerUtil.zeroIfNull(card.Archived_Net__c);
        Id cardId = card.Id;
        for (AggregateResult ar : [
            SELECT Direction__c dir, SUM(Amount__c) total
            FROM Transaction__c
            WHERE Account__c = :cardId AND Status__c != 'Void' AND Txn_Date__c <= :asOf
            WITH SYSTEM_MODE
            GROUP BY Direction__c
        ]) {
            Decimal total = LedgerUtil.zeroIfNull(ar.get('total'));
            owed += (String) ar.get('dir') == 'Debit' ? total : -total;
        }
        return owed;
    }

    /** Statements for one card the caller can see, newest first, with payments and status. */
    public static List<CommitmentDtos.Statement> listStatements(UserContext ctx, Id accountId) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'READ');
        Financial_Account__c card = new AccountSelector(ctx).byId(accountId);
        if (!new LedgerScope(ctx).canSeeAccount(card)) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        if (card.Type__c != 'Credit Card') {
            throw new PortalException('VALIDATION').withError('Statements are only for credit cards.');
        }
        generate(ctx.familyId, Date.today());
        List<Card_Statement__c> rows = new CommitmentSelector(ctx).statements(new Set<Id>{ card.Id }, 12);
        return toDtos(rows, card.Id);
    }

    public static List<CommitmentDtos.Statement> toDtos(List<Card_Statement__c> rows, Id cardId) {
        List<CommitmentDtos.Statement> result = new List<CommitmentDtos.Statement>();
        if (rows.isEmpty()) {
            return result;
        }
        Date earliest = rows[rows.size() - 1].Cycle_End__c;
        List<Transaction__c> credits = [
            SELECT Txn_Date__c, Amount__c FROM Transaction__c
            WHERE Account__c = :cardId AND Direction__c = 'Credit' AND Status__c != 'Void' AND Txn_Date__c > :earliest AND Type__c IN ('Card Payment', 'Adjustment')
            WITH SYSTEM_MODE
            LIMIT 5000
        ];
        Date today = Date.today();
        Date nextEnd;
        for (Card_Statement__c s : rows) {
            CommitmentDtos.Statement d = new CommitmentDtos.Statement();
            d.id = s.Id;
            d.accountId = s.Account__c;
            d.cycleStart = s.Cycle_Start__c;
            d.cycleEnd = s.Cycle_End__c;
            d.amount = s.Statement_Amount__c;
            d.minimumDue = s.Minimum_Due__c;
            d.dueDate = s.Due_Date__c;
            // Payments after this statement closes and before the next one closes settle it.
            for (Transaction__c t : credits) {
                if (t.Txn_Date__c > s.Cycle_End__c && (nextEnd == null || t.Txn_Date__c <= nextEnd)) {
                    d.amountPaid += t.Amount__c;
                }
            }
            d.status = statusFor(d, today);
            result.add(d);
            nextEnd = s.Cycle_End__c;
        }
        return result;
    }

    public static String statusFor(CommitmentDtos.Statement s, Date today) {
        if (s.amount == null || s.amount <= 0 || s.amountPaid >= s.amount) {
            return 'Paid';
        }
        if (s.dueDate != null && today > s.dueDate) {
            return 'Overdue';
        }
        return s.amountPaid > 0 ? 'Partially Paid' : 'Unpaid';
    }
}
