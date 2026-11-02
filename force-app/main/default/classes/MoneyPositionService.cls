/**
 * Money position for one family month: for bank accounts, credit cards, bills and loans, what is
 * available against what was spent or is still owed. Balances are as of today; money in, spent,
 * due and paid follow the family month. Each section needs its own read permission, and the same
 * scoping as its page - members see their own and shared accounts, their own bills and loans.
 *
 * Indian banking conventions: savings, current, cash and UPI wallets are spendable; FDs, RDs and
 * investments are locked; a shared credit limit counts once; a card bill is settled below one rupee.
 */
public without sharing class MoneyPositionService {
    public static final Set<String> LIQUID_TYPES = new Set<String>{ 'Savings', 'Current', 'Cash', 'UPI Wallet' };

    public static PositionDtos.Position build(UserContext ctx, Map<String, String> params) {
        AccessGuard.require(ctx, 'DASHBOARD', 'READ');
        BudgetMonth.Period period = BudgetMonth.named(ctx.familyId, params.get('month'));
        Date today = Date.today();
        PositionDtos.Position p = new PositionDtos.Position();
        p.month = period.key;
        p.periodStart = period.startDate;
        p.periodEnd = period.endDate;
        p.asOf = today;
        p.isCurrent = today >= period.startDate && today <= period.endDate;
        p.currencyCode = ctx.currencyCode;

        if (AccessGuard.can(ctx, 'ACCOUNTS', 'READ')) {
            List<FinanceDtos.Account> accounts = AccountService.toDtos(ctx, new AccountSelector(ctx).visible(false));
            Flows flows = new Flows(ctx, accounts, period);
            p.bank = bank(accounts, flows);
            p.cards = cards(accounts, flows);
        }
        if (AccessGuard.can(ctx, 'BILLS', 'READ')) {
            p.bills = bills(ctx, period, today);
        }
        if (AccessGuard.can(ctx, 'LOANS', 'READ')) {
            p.loans = loans(ctx, period, today);
        }
        summarise(p);
        return p;
    }

    /** Debits and credits per account in the month; transfers between spendable accounts are only moves. */
    private class Flows {
        final Map<Id, Decimal> debits = new Map<Id, Decimal>();
        final Map<Id, Decimal> credits = new Map<Id, Decimal>();
        final Map<Id, Decimal> refunds = new Map<Id, Decimal>();
        final Map<Id, Decimal> internalDebits = new Map<Id, Decimal>();
        final Map<Id, Decimal> internalCredits = new Map<Id, Decimal>();

        Flows(UserContext ctx, List<FinanceDtos.Account> accounts, BudgetMonth.Period period) {
            Set<Id> ids = new Set<Id>();
            Set<Id> liquid = new Set<Id>();
            for (FinanceDtos.Account a : accounts) {
                ids.add(a.id);
                if (LIQUID_TYPES.contains(a.type)) {
                    liquid.add(a.id);
                }
            }
            if (ids.isEmpty()) {
                return;
            }
            TransactionSelector selector = new TransactionSelector(ctx);
            TransactionSelector.Filter f = selector.scoped();
            f.fromDate = period.startDate;
            f.toDate = period.endDate;
            f.accountIds = ids;
            for (AggregateResult ar : selector.aggregate(
                'Account__c a, Direction__c d, Type__c t, Counter_Transaction__r.Account__c c, SUM(Amount__c) s',
                f,
                'Account__c, Direction__c, Type__c, Counter_Transaction__r.Account__c'
            )) {
                Id accountId = (Id) ar.get('a');
                Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
                Boolean debit = (String) ar.get('d') == 'Debit';
                add(debit ? debits : credits, accountId, amount);
                if (!debit && (String) ar.get('t') == 'Refund') {
                    add(refunds, accountId, amount);
                }
                Id counter = (Id) ar.get('c');
                if (counter != null && liquid.contains(accountId) && liquid.contains(counter)) {
                    add(debit ? internalDebits : internalCredits, accountId, amount);
                }
            }
        }

        Decimal get(Map<Id, Decimal> m, Id accountId) {
            return m.containsKey(accountId) ? m.get(accountId) : 0;
        }

        void add(Map<Id, Decimal> m, Id accountId, Decimal amount) {
            m.put(accountId, get(m, accountId) + amount);
        }
    }

    private static PositionDtos.BankSection bank(List<FinanceDtos.Account> accounts, Flows flows) {
        PositionDtos.BankSection s = new PositionDtos.BankSection();
        for (FinanceDtos.Account a : accounts) {
            if (a.isLiability) {
                continue;
            }
            PositionDtos.AccountLine line = new PositionDtos.AccountLine();
            line.id = a.id;
            line.name = a.name;
            line.type = a.type;
            line.institution = a.institution;
            line.last4 = a.last4;
            line.color = a.color;
            line.ownerName = a.ownerName;
            line.isShared = a.isShared;
            line.liquid = LIQUID_TYPES.contains(a.type);
            line.balance = a.balance;
            line.moneyIn = flows.get(flows.credits, a.id);
            line.moneyOut = flows.get(flows.debits, a.id);
            if (a.deposit != null) {
                line.maturityDate = a.deposit.maturityDate;
                line.maturityAmount = a.deposit.maturityAmount;
            }
            if (line.liquid) {
                s.available += a.balance;
                s.moneyIn += line.moneyIn - flows.get(flows.internalCredits, a.id);
                s.moneyOut += line.moneyOut - flows.get(flows.internalDebits, a.id);
                s.lowestBalance = s.lowestBalance == null || a.balance < s.lowestBalance ? a.balance : s.lowestBalance;
            } else {
                s.locked += a.balance;
            }
            s.accounts.add(line);
        }
        return s;
    }

    private static PositionDtos.CardSection cards(List<FinanceDtos.Account> accounts, Flows flows) {
        PositionDtos.CardSection s = new PositionDtos.CardSection();
        Map<Id, CreditLimitGroupService.GroupSummary> groups = new Map<Id, CreditLimitGroupService.GroupSummary>();
        for (FinanceDtos.Account a : accounts) {
            if (a.type != 'Credit Card') {
                continue;
            }
            PositionDtos.CardLine line = new PositionDtos.CardLine();
            line.id = a.id;
            line.name = a.name;
            line.institution = a.institution;
            line.last4 = a.last4;
            line.network = a.cardNetwork;
            line.color = a.color;
            line.ownerName = a.ownerName;
            line.used = a.balance;
            line.spent = flows.get(flows.debits, a.id) - flows.get(flows.refunds, a.id);
            line.paid = flows.get(flows.credits, a.id) - flows.get(flows.refunds, a.id);
            if (a.sharedCredit != null) {
                line.sharedLimitName = a.sharedCredit.name;
                line.creditLimit = a.sharedCredit.creditLimit;
                line.available = a.sharedCredit.available;
                line.utilisationPct = a.sharedCredit.utilisationPct;
                groups.put(a.sharedCredit.id, a.sharedCredit);
            } else if (a.creditLimit != null && a.creditLimit > 0) {
                line.creditLimit = a.creditLimit;
                line.available = a.creditLimit - a.balance;
                line.utilisationPct = (a.balance / a.creditLimit * 100).setScale(1, RoundingMode.HALF_UP);
                s.totalLimit += a.creditLimit;
                s.available += Math.max(0, line.available);
            }
            dues(line, a.card);
            s.used += a.balance;
            s.spent += line.spent;
            s.paid += line.paid;
            s.dueNow += line.dueRemaining;
            s.minimumDue += line.minimumDue == null ? 0 : Math.min(line.minimumDue, line.dueRemaining);
            if (line.dueRemaining > 0 && line.dueDate != null && (s.nextDueDate == null || line.dueDate < s.nextDueDate)) {
                s.nextDueDate = line.dueDate;
            }
            if (line.statementStatus == 'Overdue') {
                s.overdueCount++;
            }
            s.cards.add(line);
        }
        for (CreditLimitGroupService.GroupSummary g : groups.values()) {
            s.totalLimit += LedgerUtil.zeroIfNull(g.creditLimit);
            s.available += Math.max(0, LedgerUtil.zeroIfNull(g.available));
        }
        if (s.totalLimit > 0) {
            s.utilisationPct = ((s.totalLimit - s.available) / s.totalLimit * 100).setScale(1, RoundingMode.HALF_UP);
        }
        return s;
    }

    /** What the card still asks for: the generated statement, else the card's linked bill. */
    private static void dues(PositionDtos.CardLine line, FinanceDtos.CardCycle cycle) {
        if (cycle == null) {
            return;
        }
        line.nextStatementDate = cycle.nextStatementDate;
        line.dueDate = cycle.dueDate;
        line.lateFeeAfter = cycle.lateFeeAfter;
        if (cycle.statement != null) {
            CommitmentDtos.Statement st = cycle.statement;
            line.statementAmount = st.amount;
            line.minimumDue = st.minimumDue;
            line.amountPaid = st.amountPaid;
            line.statementStatus = st.status;
            line.dueDate = st.dueDate == null ? line.dueDate : st.dueDate;
            line.lateFeeAfter = line.dueDate.addDays(AccountService.LATE_FEE_GRACE_DAYS);
            if (st.status != 'Paid') {
                line.dueRemaining = Math.max(0, LedgerUtil.zeroIfNull(st.amount) - LedgerUtil.zeroIfNull(st.amountPaid));
            }
        } else if (cycle.bill != null && cycle.bill.status != 'Paid' && cycle.bill.status != 'Skipped') {
            line.statementAmount = cycle.bill.amount;
            line.amountPaid = cycle.bill.amountPaid;
            line.statementStatus = cycle.bill.status;
            line.dueDate = cycle.bill.dueDate == null ? line.dueDate : cycle.bill.dueDate;
            line.dueRemaining = Math.max(0, LedgerUtil.zeroIfNull(cycle.bill.amount) - LedgerUtil.zeroIfNull(cycle.bill.amountPaid));
        }
    }

    private static PositionDtos.BillSection bills(UserContext ctx, BudgetMonth.Period period, Date today) {
        PositionDtos.BillSection s = new PositionDtos.BillSection();
        CommitmentSelector selector = new CommitmentSelector(ctx);
        List<Bill__c> bills = selector.bills(new LedgerScope(ctx).wholeFamily() ? null : ctx.userId);
        Map<Id, Bill__c> byId = new Map<Id, Bill__c>();
        for (Bill__c b : bills) {
            // A card's own bill is counted with the card, not twice.
            if (b.Credit_Card_Account__c == null) {
                byId.put(b.Id, b);
            }
        }
        if (byId.isEmpty()) {
            return s;
        }
        Map<Id, Category__c> categories = new CategorySelector(ctx).byIdMap();
        List<Bill_Instance__c> rows = selector.instances(byId.keySet(), CommitmentSelector.OPEN_BILL, period.startDate.addDays(-1));
        rows.addAll(selector.instancesDueBetween(byId.keySet(), period.startDate, period.endDate));
        for (Bill_Instance__c i : rows) {
            if (i.Status__c == 'Skipped') {
                continue;
            }
            CommitmentDtos.BillInstance d = BillService.instance(ctx, i, byId.get(i.Bill__c), categories);
            Decimal due = LedgerUtil.zeroIfNull(i.Amount_Due__c);
            Decimal paid = LedgerUtil.zeroIfNull(i.Amount_Paid__c);
            Decimal left = d.status == 'Paid' ? 0 : Math.max(0, due - paid);
            if (i.Due_Date__c >= period.startDate) {
                s.count++;
                s.due += due;
                s.paid += Math.min(paid, due);
                if (d.status == 'Paid') {
                    s.paidCount++;
                }
            }
            s.remaining += left;
            if (d.status == 'Overdue' && left > 0) {
                s.overdue += left;
                s.overdueCount++;
            }
            s.items.add(d);
        }
        return s;
    }

    private static PositionDtos.LoanSection loans(UserContext ctx, BudgetMonth.Period period, Date today) {
        PositionDtos.LoanSection s = new PositionDtos.LoanSection();
        Map<Id, PositionDtos.LoanLine> byLoan = new Map<Id, PositionDtos.LoanLine>();
        for (CommitmentDtos.Loan l : LoanService.listLoans(ctx)) {
            PositionDtos.LoanLine line = new PositionDtos.LoanLine();
            line.loan = l;
            byLoan.put(l.id, line);
            s.loans.add(line);
            if (l.status != 'Active') {
                continue;
            }
            s.activeCount++;
            s.borrowed += LedgerUtil.zeroIfNull(l.principal);
            s.outstanding += LedgerUtil.zeroIfNull(l.outstanding);
            s.monthlyEmi += LedgerUtil.zeroIfNull(l.emi);
            s.interestRemaining += LedgerUtil.zeroIfNull(l.interestRemaining);
        }
        s.repaid = Math.max(0, s.borrowed - s.outstanding);
        if (s.borrowed > 0) {
            s.repaidPct = (s.repaid / s.borrowed * 100).setScale(1, RoundingMode.HALF_UP);
        }
        if (byLoan.isEmpty()) {
            return s;
        }
        Set<Id> overdueLoans = new Set<Id>();
        for (EMI_Installment__c i : new CommitmentSelector(ctx).installmentsDueBy(byLoan.keySet(), period.startDate, period.endDate)) {
            PositionDtos.LoanLine line = byLoan.get(i.Loan__c);
            Decimal emi = LedgerUtil.zeroIfNull(i.EMI_Amount__c);
            Boolean paid = i.Status__c == 'Paid';
            Boolean inMonth = i.Due_Date__c >= period.startDate;
            Boolean late = !paid && CommitmentSelector.OPEN_EMI.contains(i.Status__c) && i.Due_Date__c < today;
            if (inMonth && i.Status__c != 'Skipped') {
                line.emiThisMonth += emi;
                s.emiDue += emi;
                line.dueThisMonth = line.dueThisMonth == null ? i.Due_Date__c : line.dueThisMonth;
                if (paid) {
                    line.paidThisMonth += emi;
                    s.emiPaid += emi;
                }
            }
            if (!paid && CommitmentSelector.OPEN_EMI.contains(i.Status__c)) {
                s.emiRemaining += emi;
            }
            if (late) {
                overdueLoans.add(i.Loan__c);
            }
        }
        for (PositionDtos.LoanLine line : s.loans) {
            if (overdueLoans.contains(line.loan.id)) {
                line.monthStatus = 'Overdue';
            } else if (line.emiThisMonth > 0) {
                line.monthStatus = line.paidThisMonth >= line.emiThisMonth ? 'Paid' : 'Due';
            }
        }
        s.overdueCount = overdueLoans.size();
        return s;
    }

    private static void summarise(PositionDtos.Position p) {
        PositionDtos.Summary s = p.summary;
        if (p.bank != null) {
            s.liquid = p.bank.available;
            s.moneyIn = p.bank.moneyIn;
            s.moneyOut = p.bank.moneyOut;
        }
        if (p.cards != null) {
            s.cardAvailable = p.cards.available;
            s.owed += p.cards.used;
            s.duesRemaining += p.cards.dueNow;
        }
        if (p.bills != null) {
            s.duesRemaining += p.bills.remaining;
        }
        if (p.loans != null) {
            s.owed += p.loans.outstanding;
            s.duesRemaining += p.loans.emiRemaining;
        }
        if (p.isCurrent && p.bank != null) {
            s.leftAfterDues = s.liquid - s.duesRemaining;
        }
    }
}
