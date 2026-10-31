/**
 * Monthly family budgets: a planned amount per top-level expense category, compared with
 * what the family actually spent (expenses minus refunds, sub-categories rolled up).
 */
public without sharing class BudgetService {
    public static FinanceDtos.BudgetView getBudget(UserContext ctx, String month) {
        AccessGuard.require(ctx, 'BUDGETS', 'READ');
        return view(ctx, LedgerUtil.monthStart(month));
    }

    /** Replaces the month's plan. Lines with no amount (or zero) are removed. */
    public static FinanceDtos.BudgetView saveBudget(UserContext ctx, String month, Map<String, Object> body) {
        AccessGuard.require(ctx, 'BUDGETS', 'EDIT');
        Date start = LedgerUtil.monthStart(month);
        Object raw = body.get('lines');
        if (!(raw instanceof List<Object>)) {
            throw new PortalException('VALIDATION').withError('Send the budget as a list of lines.');
        }
        CategorySelector categories = CategoryService.ensureSeeded(ctx);
        Map<Id, Decimal> planned = new Map<Id, Decimal>();
        for (Object item : (List<Object>) raw) {
            if (!(item instanceof Map<String, Object>)) {
                throw new PortalException('VALIDATION').withError('Each budget line needs a category and an amount.');
            }
            Map<String, Object> line = (Map<String, Object>) item;
            Category__c c = categories.byId(VkfRest.toId(LedgerUtil.text(line, 'categoryId')));
            if (c.Kind__c != 'Expense' || c.Parent_Category__c != null) {
                throw new PortalException('VALIDATION').withError('Budgets are set on top-level expense categories.');
            }
            Decimal amount = LedgerUtil.dec(line, 'planned', 'Planned amount');
            if (amount != null && (amount < 0 || amount > LedgerUtil.MAX_AMOUNT)) {
                throw new PortalException('VALIDATION').withError('Planned amounts must be zero or more.');
            }
            planned.put(c.Id, amount == null ? 0 : amount.setScale(2, RoundingMode.HALF_UP));
        }
        writeLines(ctx, start, planned);
        AuditService.log(ctx, 'BUDGET_SAVED', 'Budget__c', null, LedgerUtil.monthKey(start));
        return view(ctx, start);
    }

    /** Starts a month from the previous month's plan. */
    public static FinanceDtos.BudgetView copyPrevious(UserContext ctx, String month) {
        AccessGuard.require(ctx, 'BUDGETS', 'EDIT');
        Date start = LedgerUtil.monthStart(month);
        BudgetSelector selector = new BudgetSelector(ctx);
        Budget__c previous = selector.forMonth(start.addMonths(-1));
        if (previous == null || previous.Lines__r.isEmpty()) {
            throw new PortalException('NOT_FOUND').withError('There is no budget for ' + LedgerUtil.monthKey(start.addMonths(-1)) + ' to copy.');
        }
        Map<Id, Decimal> planned = new Map<Id, Decimal>();
        for (Budget_Line__c line : previous.Lines__r) {
            planned.put(line.Category__c, line.Planned__c);
        }
        writeLines(ctx, start, planned);
        AuditService.log(ctx, 'BUDGET_COPIED', 'Budget__c', null, LedgerUtil.monthKey(start));
        return view(ctx, start);
    }

    private static void writeLines(UserContext ctx, Date start, Map<Id, Decimal> planned) {
        BudgetSelector selector = new BudgetSelector(ctx);
        Budget__c budget = selector.forMonth(start);
        if (budget == null) {
            budget = new Budget__c(
                Name = 'Budget ' + LedgerUtil.monthKey(start),
                Family__c = ctx.familyId,
                Month__c = start,
                Unique_Key__c = BudgetSelector.uniqueKey(ctx.familyId, start)
            );
            insert as system budget;
            budget = selector.forMonth(start);
        }
        Map<Id, Budget_Line__c> existing = new Map<Id, Budget_Line__c>();
        for (Budget_Line__c line : budget.Lines__r) {
            existing.put(line.Category__c, line);
        }
        List<Budget_Line__c> upserts = new List<Budget_Line__c>();
        List<Budget_Line__c> deletes = new List<Budget_Line__c>();
        for (Id categoryId : planned.keySet()) {
            Decimal amount = planned.get(categoryId);
            Budget_Line__c line = existing.get(categoryId);
            if (amount == null || amount == 0) {
                if (line != null) {
                    deletes.add(line);
                }
            } else if (line == null) {
                upserts.add(new Budget_Line__c(Budget__c = budget.Id, Family__c = ctx.familyId, Category__c = categoryId, Planned__c = amount));
            } else if (line.Planned__c != amount) {
                upserts.add(new Budget_Line__c(Id = line.Id, Planned__c = amount));
            }
        }
        upsert as system upserts;
        delete as system deletes;
    }

    public static FinanceDtos.BudgetView view(UserContext ctx, Date start) {
        Date finish = LedgerUtil.monthEnd(start);
        CategorySelector categories = CategoryService.ensureSeeded(ctx);
        Map<Id, Category__c> all = categories.byIdMap();
        Budget__c budget = new BudgetSelector(ctx).forMonth(start);

        FinanceDtos.BudgetView v = new FinanceDtos.BudgetView();
        v.month = LedgerUtil.monthKey(start);
        v.exists = budget != null && !budget.Lines__r.isEmpty();
        v.canEdit = AccessGuard.can(ctx, 'BUDGETS', 'EDIT');
        v.daysInMonth = Date.daysInMonth(start.year(), start.month());
        Date today = Date.today();
        v.daysElapsed = today < start ? 0 : today > finish ? v.daysInMonth : today.day();

        Map<Id, Decimal> spent = spentByTopCategory(ctx, categories, start, finish);
        Map<Id, FinanceDtos.BudgetLine> lines = new Map<Id, FinanceDtos.BudgetLine>();
        if (budget != null) {
            for (Budget_Line__c line : budget.Lines__r) {
                FinanceDtos.BudgetLine l = line(all.get(line.Category__c), all);
                l.planned = LedgerUtil.zeroIfNull(line.Planned__c);
                lines.put(line.Category__c, l);
            }
        }
        for (Id categoryId : spent.keySet()) {
            FinanceDtos.BudgetLine l = lines.get(categoryId);
            if (l != null) {
                l.spent = spent.get(categoryId);
            } else if (spent.get(categoryId) != 0 && all.containsKey(categoryId)) {
                FinanceDtos.BudgetLine u = line(all.get(categoryId), all);
                u.spent = spent.get(categoryId);
                v.unbudgeted.add(u);
            }
        }
        for (Category__c c : categories.all()) {
            if (lines.containsKey(c.Id)) {
                v.lines.add(lines.get(c.Id));
                v.totalPlanned += lines.get(c.Id).planned;
            }
        }
        for (Decimal s : spent.values()) {
            v.totalSpent += s;
        }
        return v;
    }

    /** Family-wide spending (expenses minus refunds) per top-level category for the period. */
    public static Map<Id, Decimal> spentByTopCategory(UserContext ctx, CategorySelector categories, Date start, Date finish) {
        TransactionSelector selector = new TransactionSelector(ctx);
        TransactionSelector.Filter f = new TransactionSelector.Filter();
        f.wholeFamily = true;
        f.fromDate = start;
        f.toDate = finish;
        f.types = new Set<String>{ 'Expense', 'Refund', 'Bill Payment' };
        Map<Id, Decimal> spent = new Map<Id, Decimal>();
        for (AggregateResult ar : selector.aggregate('Category__c c, Type__c t, SUM(Amount__c) s', f, 'Category__c, Type__c')) {
            Category__c top = categories.topLevel((Id) ar.get('c'));
            if (top == null) {
                continue;
            }
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            if ((String) ar.get('t') == 'Refund') {
                amount = -amount;
            }
            spent.put(top.Id, (spent.containsKey(top.Id) ? spent.get(top.Id) : 0) + amount);
        }
        return spent;
    }

    private static FinanceDtos.BudgetLine line(Category__c c, Map<Id, Category__c> all) {
        FinanceDtos.Category view = FinanceDtos.category(c, all);
        FinanceDtos.BudgetLine l = new FinanceDtos.BudgetLine();
        l.categoryId = c.Id;
        l.name = c.Name;
        l.icon = view.icon;
        l.color = view.color;
        l.essential = c.Is_Essential__c;
        return l;
    }
}