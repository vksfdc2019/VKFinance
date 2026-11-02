/**
 * Analytics: a family month's money split into EMIs, bills, spending and savings, over up to two
 * years, plus that month's spending day by day and its top payees. Scoped like the overview:
 * admins see the family (optionally one member), members their own and shared accounts.
 *
 * An EMI is its principal (EMI Payment) plus its interest (an expense in Loan Interest), so EMIs
 * are not counted again as spending. Transfers and card payments are moves, not money out.
 */
public without sharing class AnalyticsService {
    public static final Integer DEFAULT_MONTHS = 12;
    public static final Integer MAX_MONTHS = 24;
    public static final Integer TOP_PAYEES = 8;
    /** Aggregates are grouped by day, so each query covers a few months to stay well under 2,000 rows. */
    private static final Integer MONTHS_PER_QUERY = 3;
    private static final Set<String> TYPES = new Set<String>{ 'Income', 'Expense', 'Refund', 'Bill Payment', 'EMI Payment' };

    public static AnalyticsDtos.Analytics build(UserContext ctx, Map<String, String> params) {
        AccessGuard.require(ctx, 'DASHBOARD', 'READ');
        LedgerScope scope = new LedgerScope(ctx);
        BudgetMonth.Period period = BudgetMonth.named(ctx.familyId, params.get('month'));
        Integer months = parseMonths(params.get('months'));
        TransactionSelector selector = new TransactionSelector(ctx);
        TransactionSelector.Filter base = selector.scoped();

        AnalyticsDtos.Analytics a = new AnalyticsDtos.Analytics();
        a.month = period.key;
        a.periodStart = period.startDate;
        a.periodEnd = period.endDate;
        a.currencyCode = ctx.currencyCode;
        if (scope.wholeFamily()) {
            PortalUserSelector members = new PortalUserSelector(ctx);
            for (Portal_User__c m : members.visibleMembers()) {
                FinanceDtos.MemberOption o = new FinanceDtos.MemberOption();
                o.id = m.Id;
                o.name = FinanceDtos.personName(m.First_Name__c, m.Last_Name__c);
                a.members.add(o);
            }
            if (String.isNotBlank(params.get('memberId'))) {
                base.memberId = members.memberInFamily(VkfRest.toId(params.get('memberId'))).Id;
                a.memberId = base.memberId;
            }
        }

        Map<String, AnalyticsDtos.MonthFlow> byKey = new Map<String, AnalyticsDtos.MonthFlow>();
        for (Integer i = months - 1; i >= 0; i--) {
            AnalyticsDtos.MonthFlow f = new AnalyticsDtos.MonthFlow();
            BudgetMonth.Period p = BudgetMonth.of(ctx.familyId, period.anchor.addMonths(-i));
            f.month = p.key;
            f.periodStart = p.startDate;
            f.periodEnd = p.endDate;
            byKey.put(f.month, f);
            a.series.add(f);
        }
        Map<Date, AnalyticsDtos.DayAmount> days = new Map<Date, AnalyticsDtos.DayAmount>();
        for (Date d = period.startDate; d <= period.endDate; d = d.addDays(1)) {
            AnalyticsDtos.DayAmount day = new AnalyticsDtos.DayAmount();
            day.day = d;
            days.put(d, day);
            a.days.add(day);
        }

        Id interest = interestCategory(ctx);
        for (Integer i = 0; i < a.series.size(); i += MONTHS_PER_QUERY) {
            TransactionSelector.Filter f = base.copy();
            f.fromDate = a.series[i].periodStart;
            f.toDate = a.series[Math.min(i + MONTHS_PER_QUERY, a.series.size()) - 1].periodEnd;
            f.types = TYPES;
            for (AggregateResult ar : selector.aggregate('Txn_Date__c day, Type__c t, Direction__c d, SUM(Amount__c) s', f, 'Txn_Date__c, Type__c, Direction__c')) {
                add(ctx, byKey, days, (Date) ar.get('day'), (String) ar.get('t'), (String) ar.get('d'), LedgerUtil.zeroIfNull(ar.get('s')));
            }
            if (interest != null) {
                f.types = new Set<String>{ 'Expense' };
                f.categoryIds = new Set<Id>{ interest };
                for (AggregateResult ar : selector.aggregate('Txn_Date__c day, SUM(Amount__c) s', f, 'Txn_Date__c')) {
                    moveInterest(ctx, byKey, days, (Date) ar.get('day'), LedgerUtil.zeroIfNull(ar.get('s')));
                }
            }
        }
        for (AnalyticsDtos.MonthFlow f : a.series) {
            f.saved = f.income - f.spending - f.bills - f.emis;
            f.savingsRate = f.income > 0 ? (f.saved / f.income * 100).setScale(1, RoundingMode.HALF_UP) : null;
        }
        a.current = byKey.get(period.key);
        a.payees = payees(selector, base, period, interest);
        return a;
    }

    private static Integer parseMonths(String value) {
        if (String.isBlank(value) || !value.isNumeric()) {
            return DEFAULT_MONTHS;
        }
        return Math.max(1, Math.min(MAX_MONTHS, Integer.valueOf(value)));
    }

    private static Id interestCategory(UserContext ctx) {
        for (Category__c c : CategoryService.ensureSeeded(ctx).all()) {
            if (c.Name == 'Loan Interest' && c.Kind__c == 'Expense') {
                return c.Id;
            }
        }
        return null;
    }

    private static void add(UserContext ctx, Map<String, AnalyticsDtos.MonthFlow> byKey, Map<Date, AnalyticsDtos.DayAmount> days, Date day, String type, String direction, Decimal amount) {
        AnalyticsDtos.MonthFlow f = byKey.get(BudgetMonth.containing(ctx.familyId, day).key);
        if (f == null) {
            return;
        }
        Decimal spent = 0;
        if (type == 'Income' && direction == 'Credit') {
            f.income += amount;
        } else if (type == 'Expense' && direction == 'Debit') {
            f.spending += amount;
            spent = amount;
        } else if (type == 'Refund' && direction == 'Credit') {
            f.spending -= amount;
            spent = -amount;
        } else if (type == 'Bill Payment' && direction == 'Debit') {
            f.bills += amount;
            spent = amount;
        } else if (type == 'EMI Payment' && direction == 'Debit') {
            f.emis += amount;
        }
        AnalyticsDtos.DayAmount d = days.get(day);
        if (d != null) {
            d.amount += spent;
        }
    }

    /** Interest was counted as spending; it belongs with the EMI it was paid in. */
    private static void moveInterest(UserContext ctx, Map<String, AnalyticsDtos.MonthFlow> byKey, Map<Date, AnalyticsDtos.DayAmount> days, Date day, Decimal amount) {
        AnalyticsDtos.MonthFlow f = byKey.get(BudgetMonth.containing(ctx.familyId, day).key);
        if (f == null) {
            return;
        }
        f.spending -= amount;
        f.emis += amount;
        AnalyticsDtos.DayAmount d = days.get(day);
        if (d != null) {
            d.amount -= amount;
        }
    }

    /** Top payees for everyday spending and bills - loan interest goes to the lender, and it is an EMI. */
    private static List<AnalyticsDtos.NamedAmount> payees(TransactionSelector selector, TransactionSelector.Filter base, BudgetMonth.Period period, Id interest) {
        TransactionSelector.Filter f = base.copy();
        f.fromDate = period.startDate;
        f.toDate = period.endDate;
        f.types = new Set<String>{ 'Expense', 'Bill Payment' };
        Map<String, AnalyticsDtos.NamedAmount> byName = new Map<String, AnalyticsDtos.NamedAmount>();
        for (AggregateResult ar : selector.aggregate('Payee__c p, Category__c c, COUNT(Id) n, SUM(Amount__c) s', f, 'Payee__c, Category__c')) {
            String name = (String) ar.get('p');
            if (String.isBlank(name) || (interest != null && (Id) ar.get('c') == interest)) {
                continue;
            }
            AnalyticsDtos.NamedAmount n = byName.get(name.toLowerCase());
            if (n == null) {
                n = new AnalyticsDtos.NamedAmount();
                n.name = name;
                n.amount = 0;
                n.count = 0;
                byName.put(name.toLowerCase(), n);
            }
            n.amount += LedgerUtil.zeroIfNull(ar.get('s'));
            n.count += (Integer) ar.get('n');
        }
        List<PayeeSort> sorted = new List<PayeeSort>();
        for (AnalyticsDtos.NamedAmount n : byName.values()) {
            sorted.add(new PayeeSort(n));
        }
        sorted.sort();
        List<AnalyticsDtos.NamedAmount> result = new List<AnalyticsDtos.NamedAmount>();
        for (Integer i = 0; i < Math.min(TOP_PAYEES, sorted.size()); i++) {
            result.add(sorted[i].payee);
        }
        return result;
    }

    private class PayeeSort implements Comparable {
        final AnalyticsDtos.NamedAmount payee;

        PayeeSort(AnalyticsDtos.NamedAmount payee) {
            this.payee = payee;
        }

        public Integer compareTo(Object other) {
            Decimal theirs = ((PayeeSort) other).payee.amount;
            return payee.amount > theirs ? -1 : payee.amount < theirs ? 1 : 0;
        }
    }
}
