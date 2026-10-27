/**
 * Everything the overview page shows for one month, in one call: income, spending and
 * savings, net worth, spending by category, a six-month trend, budget progress, accounts
 * and recent activity. Admins see the family (optionally one member); members see their
 * own and shared accounts; children their own.
 */
public without sharing class DashboardService {
    public static final Integer TREND_MONTHS = 6;

    public static FinanceDtos.Dashboard build(UserContext ctx, Map<String, String> params) {
        AccessGuard.require(ctx, 'DASHBOARD', 'READ');
        LedgerScope scope = new LedgerScope(ctx);
        Date start = LedgerUtil.monthStart(params.get('month'));
        Date finish = LedgerUtil.monthEnd(start);
        CategorySelector categories = CategoryService.ensureSeeded(ctx);
        TransactionSelector selector = new TransactionSelector(ctx);
        TransactionSelector.Filter base = selector.scoped();

        FinanceDtos.Dashboard d = new FinanceDtos.Dashboard();
        d.month = LedgerUtil.monthKey(start);
        d.currencyCode = ctx.currencyCode;
        d.wholeFamily = scope.wholeFamily();

        PortalUserSelector members = new PortalUserSelector(ctx);
        if (scope.wholeFamily()) {
            for (Portal_User__c m : members.visibleMembers()) {
                FinanceDtos.MemberOption o = new FinanceDtos.MemberOption();
                o.id = m.Id;
                o.name = FinanceDtos.personName(m.First_Name__c, m.Last_Name__c);
                d.members.add(o);
            }
            if (String.isNotBlank(params.get('memberId'))) {
                base.memberId = members.memberInFamily(VkfRest.toId(params.get('memberId'))).Id;
                d.memberId = base.memberId;
            }
        }

        addTrendAndKpis(d, selector, base, start, finish);
        addCategories(d, selector, base, categories, start, finish);
        addAccounts(d, ctx, base.memberId);
        if (base.memberId == null) {
            d.upcoming = DuesService.upcoming(ctx, 30);
        }

        TransactionSelector.Filter recent = base.copy();
        recent.toDate = Date.today() > finish ? finish : null;
        d.recent = TransactionService.toDtos(ctx, selector.page(recent, 8));

        if (scope.wholeFamily() && base.memberId == null && AccessGuard.can(ctx, 'BUDGETS', 'READ')) {
            FinanceDtos.BudgetView budget = BudgetService.view(ctx, start);
            if (budget.exists) {
                d.budget = new FinanceDtos.BudgetSummary();
                d.budget.planned = budget.totalPlanned;
                for (FinanceDtos.BudgetLine line : budget.lines) {
                    d.budget.spent += line.spent;
                    if (line.spent > line.planned) {
                        d.budget.overCount++;
                    }
                }
            }
        }
        return d;
    }

    private static void addTrendAndKpis(FinanceDtos.Dashboard d, TransactionSelector selector, TransactionSelector.Filter base, Date start, Date finish) {
        Map<String, FinanceDtos.MonthPoint> points = new Map<String, FinanceDtos.MonthPoint>();
        for (Integer i = TREND_MONTHS - 1; i >= 0; i--) {
            FinanceDtos.MonthPoint p = new FinanceDtos.MonthPoint();
            p.month = LedgerUtil.monthKey(start.addMonths(-i));
            points.put(p.month, p);
            d.trend.add(p);
        }
        TransactionSelector.Filter f = base.copy();
        f.fromDate = start.addMonths(-(TREND_MONTHS - 1));
        f.toDate = finish;
        f.types = new Set<String>{ 'Income', 'Expense', 'Refund', 'Bill Payment' };
        for (AggregateResult ar : selector.aggregate(
            'CALENDAR_YEAR(Txn_Date__c) y, CALENDAR_MONTH(Txn_Date__c) m, Type__c t, SUM(Amount__c) s',
            f,
            'CALENDAR_YEAR(Txn_Date__c), CALENDAR_MONTH(Txn_Date__c), Type__c'
        )) {
            String key = LedgerUtil.monthKey(Date.newInstance((Integer) ar.get('y'), (Integer) ar.get('m'), 1));
            FinanceDtos.MonthPoint p = points.get(key);
            if (p == null) {
                continue;
            }
            Decimal s = LedgerUtil.zeroIfNull(ar.get('s'));
            String type = (String) ar.get('t');
            if (type == 'Income') {
                p.income += s;
            } else if (type == 'Refund') {
                p.expenses -= s;
            } else {
                p.expenses += s;
            }
        }
        FinanceDtos.MonthPoint current = points.get(d.month);
        FinanceDtos.MonthPoint previous = points.get(LedgerUtil.monthKey(start.addMonths(-1)));
        d.kpis.income = current.income;
        d.kpis.expenses = current.expenses;
        d.kpis.net = current.income - current.expenses;
        d.kpis.savingsRate = current.income > 0 ? (d.kpis.net / current.income * 100).setScale(1, RoundingMode.HALF_UP) : null;
        d.kpis.prevIncome = previous.income;
        d.kpis.prevExpenses = previous.expenses;
    }

    private static void addCategories(
        FinanceDtos.Dashboard d, TransactionSelector selector, TransactionSelector.Filter base, CategorySelector categories, Date start, Date finish
    ) {
        Map<Id, Category__c> all = categories.byIdMap();
        TransactionSelector.Filter f = base.copy();
        f.fromDate = start;
        f.toDate = finish;
        f.types = new Set<String>{ 'Expense', 'Refund', 'Bill Payment' };
        Map<Id, FinanceDtos.CategorySpend> byTop = new Map<Id, FinanceDtos.CategorySpend>();
        for (AggregateResult ar : selector.aggregate('Category__c c, Type__c t, SUM(Amount__c) s', f, 'Category__c, Type__c')) {
            Id categoryId = (Id) ar.get('c');
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            if ((String) ar.get('t') == 'Refund') {
                amount = -amount;
            }
            Category__c own = all.get(categoryId);
            if (own != null && own.Is_Essential__c) {
                d.kpis.essential += amount;
            } else {
                d.kpis.discretionary += amount;
            }
            Category__c top = categories.topLevel(categoryId);
            if (top == null) {
                continue;
            }
            FinanceDtos.CategorySpend spend = byTop.get(top.Id);
            if (spend == null) {
                FinanceDtos.Category view = FinanceDtos.category(top, all);
                spend = new FinanceDtos.CategorySpend();
                spend.categoryId = top.Id;
                spend.name = top.Name;
                spend.icon = view.icon;
                spend.color = view.color;
                byTop.put(top.Id, spend);
            }
            spend.amount += amount;
        }
        List<SpendSort> sorted = new List<SpendSort>();
        for (FinanceDtos.CategorySpend s : byTop.values()) {
            if (s.amount > 0) {
                sorted.add(new SpendSort(s));
            }
        }
        sorted.sort();
        for (SpendSort s : sorted) {
            d.byCategory.add(s.spend);
        }
    }

    private static void addAccounts(FinanceDtos.Dashboard d, UserContext ctx, Id memberId) {
        List<Financial_Account__c> accounts = new List<Financial_Account__c>();
        for (Financial_Account__c a : new AccountSelector(ctx).visible(false)) {
            if (memberId == null || a.Owner_Member__c == memberId) {
                accounts.add(a);
            }
        }
        d.accounts = AccountService.toDtos(ctx, accounts);
        for (FinanceDtos.Account a : d.accounts) {
            if (a.isLiability) {
                d.netWorth.liabilities += a.balance;
            } else {
                d.netWorth.assets += a.balance;
            }
        }
        d.netWorth.net = d.netWorth.assets - d.netWorth.liabilities;
    }

    private class SpendSort implements Comparable {
        final FinanceDtos.CategorySpend spend;

        SpendSort(FinanceDtos.CategorySpend spend) {
            this.spend = spend;
        }

        public Integer compareTo(Object other) {
            Decimal theirs = ((SpendSort) other).spend.amount;
            return spend.amount > theirs ? -1 : spend.amount < theirs ? 1 : 0;
        }
    }
}
