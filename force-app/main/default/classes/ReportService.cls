/**
 * The family reports. Every report returns the same shape - headline figures, one chart and a
 * table - so the portal renders them all with one component and exports any of them as CSV.
 * Figures come from aggregate queries within the caller's scope (admins: the family or one
 * member; members: own + shared accounts; children: own). Admin-only reports say so.
 */
public without sharing class ReportService {
    public static final List<String> TYPES = new List<String>{
        'summary', 'category', 'members', 'trend', 'budget', 'forecast', 'account', 'cards', 'loans', 'bills', 'modes', 'annual', 'security'
    };
    public static final Set<String> ADMIN_ONLY = new Set<String>{ 'members', 'forecast', 'bills', 'annual', 'security' };
    private static final Set<String> SPEND_TYPES = new Set<String>{ 'Expense', 'Refund', 'Bill Payment' };
    private static final Set<String> LIQUID = new Set<String>{ 'Savings', 'Current', 'Cash', 'UPI Wallet' };
    public static final Integer MAX_DAYS = 1100;

    public class Kpi {
        public String label;
        public Decimal value;
        public String format;
        public String caption;

        public Kpi(String label, Decimal value, String format, String caption) {
            this.label = label;
            this.value = value;
            this.format = format;
            this.caption = caption;
        }
    }

    public class Point {
        public String label;
        public String id;
        public String icon;
        public String color;
        public Decimal target;
        public Map<String, Decimal> values = new Map<String, Decimal>();
    }

    public class Chart {
        public String kind;
        public List<Map<String, String>> series = new List<Map<String, String>>();
        public List<Point> points = new List<Point>();

        public Chart(String kind) {
            this.kind = kind;
        }

        public Chart serie(String key, String label) {
            series.add(new Map<String, String>{ 'key' => key, 'label' => label });
            return this;
        }
    }

    public class Column {
        public String key;
        public String label;
        public String format;

        public Column(String key, String label, String format) {
            this.key = key;
            this.label = label;
            this.format = format;
        }
    }

    public class Table {
        public String title;
        public List<Column> columns = new List<Column>();
        public List<Map<String, Object>> rows = new List<Map<String, Object>>();

        public Table col(String key, String label, String format) {
            columns.add(new Column(key, label, format));
            return this;
        }
    }

    public class Report {
        public String type;
        public String title;
        public String subtitle;
        public Date fromDate;
        public Date toDate;
        public List<Kpi> kpis = new List<Kpi>();
        public Chart chart;
        public Table table;
        public Table detail;
        public String note;
        public String drill;
    }

    private class Scope {
        UserContext ctx;
        Date fromDate;
        Date toDate;
        Map<String, String> params;
        TransactionSelector selector;
        TransactionSelector.Filter base;
        CategorySelector categories;
        Map<Id, Category__c> cats;

        Scope(UserContext ctx, Date fromDate, Date toDate, Map<String, String> params) {
            this.ctx = ctx;
            this.fromDate = fromDate;
            this.toDate = toDate;
            this.params = params;
            selector = new TransactionSelector(ctx);
            base = selector.scoped();
            if (String.isNotBlank(params.get('memberId')) && base.wholeFamily) {
                base.memberId = new PortalUserSelector(ctx).memberInFamily(VkfRest.toId(params.get('memberId'))).Id;
            }
            categories = CategoryService.ensureSeeded(ctx);
            cats = categories.byIdMap();
        }

        TransactionSelector.Filter period(Date f, Date t, Set<String> types) {
            TransactionSelector.Filter x = base.copy();
            x.fromDate = f;
            x.toDate = t;
            x.types = types;
            return x;
        }
    }

    public static Report run(UserContext ctx, String type, Map<String, String> params) {
        AccessGuard.require(ctx, 'REPORTS', 'READ');
        if (!TYPES.contains(type)) {
            throw new PortalException('NOT_FOUND').withError('There is no report called "' + type + '".');
        }
        if (ADMIN_ONLY.contains(type) && !ctx.isAdmin()) {
            throw new PortalException('NOT_AUTHORIZED').withError('This report is for family admins.');
        }
        Date fromDate = LedgerUtil.dateValue(params.get('from'), 'From');
        Date toDate = LedgerUtil.dateValue(params.get('to'), 'To');
        if (fromDate == null) {
            fromDate = Date.today().toStartOfMonth();
        }
        if (toDate == null) {
            toDate = LedgerUtil.monthEnd(fromDate.toStartOfMonth());
        }
        if (toDate < fromDate || fromDate.daysBetween(toDate) > MAX_DAYS) {
            throw new PortalException('VALIDATION').withError('Choose a period of up to three years, ending after it starts.');
        }
        Scope s = new Scope(ctx, fromDate, toDate, params);
        Report r = new Report();
        r.type = type;
        r.fromDate = fromDate;
        r.toDate = toDate;
        switch on type {
            when 'summary' {
                summary(s, r);
            }
            when 'category' {
                category(s, r);
            }
            when 'members' {
                members(s, r);
            }
            when 'trend' {
                trend(s, r);
            }
            when 'budget' {
                budget(s, r);
            }
            when 'forecast' {
                forecast(s, r);
            }
            when 'account' {
                account(s, r);
            }
            when 'cards' {
                cards(s, r);
            }
            when 'loans' {
                loans(s, r);
            }
            when 'bills' {
                bills(s, r);
            }
            when 'modes' {
                modes(s, r);
            }
            when 'annual' {
                annual(s, r);
            }
            when 'security' {
                security(s, r);
            }
        }
        archiveNote(ctx, r);
        return r;
    }

    /** Says so when the period reaches back into archived months. */
    private static void archiveNote(UserContext ctx, Report r) {
        Date through = archivedThrough(ctx.familyId);
        if (through == null || r.fromDate == null || r.fromDate > through || r.type == 'forecast' || r.type == 'security') {
            return;
        }
        String note = 'Entries up to ' + through.format() + ' are archived and appear under Archive. Family monthly totals still include them.';
        r.note = String.isBlank(r.note) ? note : r.note + ' ' + note;
    }

    private static Date archivedThrough(Id familyId) {
        List<Family__c> rows = [SELECT Archived_Through__c FROM Family__c WHERE Id = :familyId WITH SYSTEM_MODE LIMIT 1];
        return rows.isEmpty() ? null : rows[0].Archived_Through__c;
    }

    // ------------------------------------------------------------------ shared aggregates

    private class Totals {
        Decimal income = 0;
        Decimal expenses = 0;
        Integer count = 0;
    }

    private static Totals totals(Scope s, Date f, Date t) {
        Totals x = new Totals();
        for (AggregateResult ar : s.selector.aggregate(
            'Type__c t, SUM(Amount__c) s, COUNT(Id) n', s.period(f, t, new Set<String>{ 'Income', 'Expense', 'Refund', 'Bill Payment' }), 'Type__c'
        )) {
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            String type = (String) ar.get('t');
            x.count += (Integer) ar.get('n');
            if (type == 'Income') {
                x.income += amount;
            } else if (type == 'Refund') {
                x.expenses -= amount;
            } else {
                x.expenses += amount;
            }
        }
        return x;
    }

    /** Spending (expenses minus refunds) per category, with entry counts. */
    private static Map<Id, Decimal[]> spendByCategory(Scope s, TransactionSelector.Filter f) {
        Map<Id, Decimal[]> result = new Map<Id, Decimal[]>();
        for (AggregateResult ar : s.selector.aggregate('Category__c c, Type__c t, SUM(Amount__c) s, COUNT(Id) n', f, 'Category__c, Type__c')) {
            Id categoryId = (Id) ar.get('c');
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            if ((String) ar.get('t') == 'Refund') {
                amount = -amount;
            }
            Decimal[] row = result.containsKey(categoryId) ? result.get(categoryId) : new List<Decimal>{ 0, 0 };
            row[0] += amount;
            row[1] += (Integer) ar.get('n');
            result.put(categoryId, row);
        }
        return result;
    }

    /** Rolls category spend up to `level`: top-level categories, or the children of one parent. */
    private static Map<Id, Decimal[]> rollUp(Scope s, Map<Id, Decimal[]> spend, Id parentId) {
        Map<Id, Decimal[]> result = new Map<Id, Decimal[]>();
        for (Id categoryId : spend.keySet()) {
            Category__c c = s.cats.get(categoryId);
            Id key;
            if (parentId == null) {
                Category__c top = s.categories.topLevel(categoryId);
                key = top == null ? null : top.Id;
            } else if (c != null && (c.Id == parentId || c.Parent_Category__c == parentId)) {
                key = c.Id;
            } else {
                continue;
            }
            Decimal[] row = result.containsKey(key) ? result.get(key) : new List<Decimal>{ 0, 0 };
            row[0] += spend.get(categoryId)[0];
            row[1] += spend.get(categoryId)[1];
            result.put(key, row);
        }
        return result;
    }

    private static void rankedCategories(Scope s, Report r, Map<Id, Decimal[]> byCategory, String drill) {
        Decimal total = 0;
        List<Ranked> ranked = new List<Ranked>();
        for (Id key : byCategory.keySet()) {
            if (byCategory.get(key)[0] != 0) {
                ranked.add(new Ranked(key, byCategory.get(key)[0]));
                total += byCategory.get(key)[0];
            }
        }
        ranked.sort();
        r.chart = new Chart('ranked').serie('amount', 'Spent');
        r.table = new Table().col('name', 'Category', 'text').col('amount', 'Spent', 'money').col('share', 'Share', 'percent').col('count', 'Entries', 'number');
        for (Ranked item : ranked) {
            Category__c c = item.id == null ? null : s.cats.get((Id) item.id);
            FinanceDtos.Category view = c == null ? null : FinanceDtos.category(c, s.cats);
            Point p = new Point();
            p.label = c == null ? 'Uncategorised' : c.Name;
            p.id = item.id;
            p.icon = view?.icon;
            p.color = view?.color;
            p.values.put('amount', item.amount);
            r.chart.points.add(p);
            r.table.rows.add(new Map<String, Object>{
                'id' => item.id, 'name' => p.label, 'amount' => item.amount,
                'share' => total == 0 ? 0 : (item.amount / total * 100).setScale(1, RoundingMode.HALF_UP),
                'count' => byCategory.get((Id) item.id)[1], 'icon' => p.icon, 'color' => p.color
            });
        }
        r.drill = drill;
    }

    private static void kpiTotals(Report r, Totals t) {
        r.kpis.add(new Kpi('Income', t.income, 'money', null));
        r.kpis.add(new Kpi('Spending', t.expenses, 'money', null));
        r.kpis.add(new Kpi('Saved', t.income - t.expenses, 'money', null));
        r.kpis.add(new Kpi('Savings rate', t.income > 0 ? ((t.income - t.expenses) / t.income * 100).setScale(1, RoundingMode.HALF_UP) : null, 'percent', null));
    }

    // ------------------------------------------------------------------ reports

    private static void summary(Scope s, Report r) {
        r.title = 'Monthly summary';
        r.subtitle = 'Where the money came from and where it went';
        Totals t = totals(s, s.fromDate, s.toDate);
        kpiTotals(r, t);
        r.kpis.add(new Kpi('Transactions', t.count, 'number', null));
        rankedCategories(s, r, rollUp(s, spendByCategory(s, s.period(s.fromDate, s.toDate, SPEND_TYPES)), null), 'category');
    }

    private static void category(Scope s, Report r) {
        Id parentId = VkfRest.toId(s.params.get('categoryId'));
        Category__c parent = parentId == null ? null : s.categories.byId(parentId);
        r.title = parent == null ? 'Spending by category' : 'Spending on ' + parent.Name;
        r.subtitle = parent == null ? 'Open a category to see its sub-categories' : 'Sub-categories of ' + parent.Name;
        Map<Id, Decimal[]> spend = spendByCategory(s, s.period(s.fromDate, s.toDate, SPEND_TYPES));
        Map<Id, Decimal[]> rolled = rollUp(s, spend, parent == null ? null : parent.Id);
        Decimal total = 0;
        for (Decimal[] row : rolled.values()) {
            total += row[0];
        }
        r.kpis.add(new Kpi('Spent', total, 'money', null));
        r.kpis.add(new Kpi('Categories', rolled.size(), 'number', null));
        rankedCategories(s, r, rolled, parent == null ? 'category' : 'transactions');
    }

    private static void members(Scope s, Report r) {
        r.title = 'Member spending';
        r.subtitle = 'Who spent what, against their monthly limit';
        Map<Id, Decimal> spent = new Map<Id, Decimal>();
        Map<Id, Decimal> earned = new Map<Id, Decimal>();
        for (AggregateResult ar : s.selector.aggregate(
            'Member__c m, Type__c t, SUM(Amount__c) s', s.period(s.fromDate, s.toDate, new Set<String>{ 'Income', 'Expense', 'Refund', 'Bill Payment' }), 'Member__c, Type__c'
        )) {
            Id m = (Id) ar.get('m');
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            String type = (String) ar.get('t');
            if (type == 'Income') {
                earned.put(m, (earned.containsKey(m) ? earned.get(m) : 0) + amount);
            } else {
                spent.put(m, (spent.containsKey(m) ? spent.get(m) : 0) + (type == 'Refund' ? -amount : amount));
            }
        }
        Boolean monthly = s.fromDate.daysBetween(s.toDate) <= 31;
        Id fid = s.ctx.familyId;
        r.chart = new Chart('ranked').serie('amount', 'Spent');
        r.table = new Table().col('name', 'Member', 'text').col('role', 'Role', 'text').col('spent', 'Spent', 'money').col('income', 'Income', 'money')
            .col('limit', 'Monthly limit', 'money').col('used', 'Of limit', 'percent');
        Decimal total = 0;
        for (Portal_User__c m : [
            SELECT Id, First_Name__c, Last_Name__c, Role__c, Monthly_Spend_Limit__c FROM Portal_User__c
            WHERE Family__c = :fid AND Status__c != 'Removed' WITH SYSTEM_MODE ORDER BY First_Name__c
        ]) {
            Decimal amount = spent.containsKey(m.Id) ? spent.get(m.Id) : 0;
            total += amount;
            Decimal limitAmount = monthly ? m.Monthly_Spend_Limit__c : null;
            Point p = new Point();
            p.label = FinanceDtos.personName(m.First_Name__c, m.Last_Name__c);
            p.id = m.Id;
            p.target = limitAmount;
            p.values.put('amount', amount);
            r.chart.points.add(p);
            r.table.rows.add(new Map<String, Object>{
                'id' => m.Id, 'name' => p.label, 'role' => m.Role__c, 'spent' => amount, 'income' => earned.containsKey(m.Id) ? earned.get(m.Id) : 0,
                'limit' => limitAmount, 'used' => limitAmount == null || limitAmount == 0 ? null : (amount / limitAmount * 100).setScale(1, RoundingMode.HALF_UP)
            });
        }
        r.kpis.add(new Kpi('Family spending', total, 'money', null));
        r.kpis.add(new Kpi('Members', r.table.rows.size(), 'number', null));
        if (!monthly) {
            r.note = 'Monthly limits show when the period is one month or shorter.';
        }
        r.drill = 'member';
    }

    private static void trend(Scope s, Report r) {
        r.title = 'Income vs spending';
        r.subtitle = 'Twelve months to ' + LedgerUtil.monthKey(s.toDate);
        Date endMonth = s.toDate.toStartOfMonth();
        Date startMonth = endMonth.addMonths(-11);
        r.fromDate = startMonth;
        r.toDate = LedgerUtil.monthEnd(endMonth);
        Map<String, Decimal[]> months = new Map<String, Decimal[]>();
        for (Integer i = 0; i < 12; i++) {
            months.put(LedgerUtil.monthKey(startMonth.addMonths(i)), new List<Decimal>{ 0, 0 });
        }
        // Closed months older than three months come from Monthly_Summary__c snapshots when present.
        Date liveFrom = startMonth;
        Set<String> fromSnapshot = new Set<String>();
        if (s.base.wholeFamily && s.base.memberId == null) {
            Date cutoff = Date.today().toStartOfMonth().addMonths(-3);
            Id fid = s.ctx.familyId;
            for (Monthly_Summary__c m : [
                SELECT Month__c, Income__c, Expense__c FROM Monthly_Summary__c
                WHERE Family__c = :fid AND Member__c = NULL AND Month__c >= :startMonth AND Month__c < :cutoff
                WITH SYSTEM_MODE ORDER BY Month__c
            ]) {
                String key = LedgerUtil.monthKey(m.Month__c);
                if (months.containsKey(key)) {
                    months.put(key, new List<Decimal>{ LedgerUtil.zeroIfNull(m.Income__c), LedgerUtil.zeroIfNull(m.Expense__c) });
                    fromSnapshot.add(key);
                }
            }
            while (liveFrom <= endMonth && fromSnapshot.contains(LedgerUtil.monthKey(liveFrom))) {
                liveFrom = liveFrom.addMonths(1);
            }
        }
        if (liveFrom <= endMonth) {
            for (AggregateResult ar : s.selector.aggregate(
                'CALENDAR_YEAR(Txn_Date__c) y, CALENDAR_MONTH(Txn_Date__c) m, Type__c t, SUM(Amount__c) s',
                s.period(liveFrom, LedgerUtil.monthEnd(endMonth), new Set<String>{ 'Income', 'Expense', 'Refund', 'Bill Payment' }),
                'CALENDAR_YEAR(Txn_Date__c), CALENDAR_MONTH(Txn_Date__c), Type__c'
            )) {
                String key = LedgerUtil.monthKey(Date.newInstance((Integer) ar.get('y'), (Integer) ar.get('m'), 1));
                if (fromSnapshot.contains(key)) {
                    continue;
                }
                Decimal[] row = months.get(key);
                Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
                String type = (String) ar.get('t');
                if (type == 'Income') {
                    row[0] += amount;
                } else {
                    row[1] += type == 'Refund' ? -amount : amount;
                }
            }
        }
        r.chart = new Chart('columns').serie('income', 'Income').serie('expenses', 'Spending');
        r.table = new Table().col('month', 'Month', 'month').col('income', 'Income', 'money').col('expenses', 'Spending', 'money')
            .col('saved', 'Saved', 'money').col('rate', 'Savings rate', 'percent');
        Decimal income = 0;
        Decimal expenses = 0;
        for (String key : months.keySet()) {
            Decimal[] row = months.get(key);
            income += row[0];
            expenses += row[1];
            Point p = new Point();
            p.label = key;
            p.values.put('income', row[0]);
            p.values.put('expenses', row[1]);
            r.chart.points.add(p);
            r.table.rows.add(new Map<String, Object>{
                'month' => key, 'income' => row[0], 'expenses' => row[1], 'saved' => row[0] - row[1],
                'rate' => row[0] > 0 ? ((row[0] - row[1]) / row[0] * 100).setScale(1, RoundingMode.HALF_UP) : null
            });
        }
        r.kpis.add(new Kpi('Average income', (income / 12).setScale(0, RoundingMode.HALF_UP), 'money', 'per month'));
        r.kpis.add(new Kpi('Average spending', (expenses / 12).setScale(0, RoundingMode.HALF_UP), 'money', 'per month'));
        r.kpis.add(new Kpi('Saved in 12 months', income - expenses, 'money', null));
        r.kpis.add(new Kpi('Savings rate', income > 0 ? ((income - expenses) / income * 100).setScale(1, RoundingMode.HALF_UP) : null, 'percent', null));
    }

    private static void budget(Scope s, Report r) {
        AccessGuard.require(s.ctx, 'BUDGETS', 'READ');
        Date month = s.fromDate.toStartOfMonth();
        FinanceDtos.BudgetView v = BudgetService.view(s.ctx, month);
        r.title = 'Budget vs actual';
        r.subtitle = 'Plan and spending for ' + LedgerUtil.monthKey(month);
        r.fromDate = month;
        r.toDate = LedgerUtil.monthEnd(month);
        r.kpis.add(new Kpi('Planned', v.totalPlanned, 'money', null));
        r.kpis.add(new Kpi('Spent', v.totalSpent, 'money', null));
        r.kpis.add(new Kpi('Left', v.totalPlanned - v.totalSpent, 'money', null));
        Integer over = 0;
        r.chart = new Chart('ranked').serie('amount', 'Spent');
        r.table = new Table().col('name', 'Category', 'text').col('planned', 'Planned', 'money').col('spent', 'Spent', 'money')
            .col('left', 'Left', 'money').col('used', 'Used', 'percent');
        for (FinanceDtos.BudgetLine line : v.lines) {
            if (line.spent > line.planned) {
                over++;
            }
            Point p = new Point();
            p.label = line.name;
            p.id = line.categoryId;
            p.icon = line.icon;
            p.color = line.color;
            p.target = line.planned;
            p.values.put('amount', line.spent);
            r.chart.points.add(p);
            r.table.rows.add(new Map<String, Object>{
                'id' => line.categoryId, 'name' => line.name, 'planned' => line.planned, 'spent' => line.spent, 'left' => line.planned - line.spent,
                'used' => line.planned == 0 ? null : (line.spent / line.planned * 100).setScale(1, RoundingMode.HALF_UP)
            });
        }
        r.kpis.add(new Kpi('Over plan', over, 'number', 'categories'));
        if (!v.exists) {
            r.note = 'There is no budget for this month yet.';
        }
    }

    private class Flow implements Comparable {
        Date d;
        String label;
        Decimal amount;

        Flow(Date d, String label, Decimal amount) {
            this.d = d;
            this.label = label;
            this.amount = amount;
        }

        public Integer compareTo(Object other) {
            Date o = ((Flow) other).d;
            return d < o ? -1 : d > o ? 1 : 0;
        }
    }

    private static void forecast(Scope s, Report r) {
        Date today = Date.today();
        Date horizon = today.addDays(90);
        r.title = 'Cash-flow forecast';
        r.subtitle = 'Bank, cash and wallet money over the next 90 days';
        r.fromDate = today;
        r.toDate = horizon;
        Map<Id, Financial_Account__c> accounts = new Map<Id, Financial_Account__c>(new AccountSelector(s.ctx).visible(false));
        Decimal start = 0;
        for (Financial_Account__c a : accounts.values()) {
            if (LIQUID.contains(a.Type__c)) {
                start += a.Current_Balance__c == null ? LedgerUtil.zeroIfNull(a.Opening_Balance__c) : a.Current_Balance__c;
            }
        }
        List<Flow> flows = new List<Flow>();
        CommitmentSelector commitments = new CommitmentSelector(s.ctx);
        for (Recurring_Rule__c rule : commitments.rules(null)) {
            if (rule.Active__c != true || rule.Next_Run_Date__c == null) {
                continue;
            }
            Financial_Account__c source = accounts.get(rule.Account__c);
            Financial_Account__c target = accounts.get(rule.To_Account__c);
            Boolean fromLiquid = source != null && LIQUID.contains(source.Type__c);
            Boolean toLiquid = target != null && LIQUID.contains(target.Type__c);
            Decimal sign = rule.Type__c == 'Income' ? (fromLiquid ? 1 : 0) : rule.Type__c == 'Expense' ? (fromLiquid ? -1 : 0) : (fromLiquid && !toLiquid ? -1 : !fromLiquid && toLiquid ? 1 : 0);
            Date d = rule.Next_Run_Date__c;
            for (Integer i = 0; i < 100 && d <= horizon && sign != 0 && (rule.End_Date__c == null || d <= rule.End_Date__c); i++) {
                flows.add(new Flow(d < today ? today : d, rule.Name, sign * rule.Amount__c));
                d = RecurringService.advance(d, rule.Frequency__c);
            }
        }
        List<Bill__c> billList = commitments.bills(null);
        Map<Id, Bill__c> bills = new Map<Id, Bill__c>(billList);
        Map<Id, Date> lastDue = new Map<Id, Date>();
        // Bills paid by card leave the bank later, through the card bill - count them only there.
        for (Bill__c b : billList) {
            Financial_Account__c payFrom = accounts.get(b.Pay_From_Account__c);
            if (payFrom != null && !LIQUID.contains(payFrom.Type__c)) {
                bills.remove(b.Id);
            }
        }
        for (Bill_Instance__c i : commitments.instances(bills.keySet(), CommitmentSelector.OPEN_BILL, horizon)) {
            flows.add(new Flow(i.Due_Date__c < today ? today : i.Due_Date__c, bills.get(i.Bill__c).Name, -(LedgerUtil.zeroIfNull(i.Amount_Due__c) - LedgerUtil.zeroIfNull(i.Amount_Paid__c))));
            lastDue.put(i.Bill__c, i.Due_Date__c);
        }
        for (Bill__c b : bills.values()) {
            if (b.Active__c != true || !lastDue.containsKey(b.Id) || b.Expected_Amount__c == null) {
                continue;
            }
            Date d = BillService.nextDate(lastDue.get(b.Id), b.Frequency__c);
            for (Integer i = 0; i < 20 && d != null && d <= horizon; i++) {
                flows.add(new Flow(d, b.Name, -b.Expected_Amount__c));
                d = BillService.nextDate(d, b.Frequency__c);
            }
        }
        Map<Id, Loan__c> loans = new Map<Id, Loan__c>(commitments.loans(null));
        for (EMI_Installment__c i : commitments.installments(loans.keySet(), CommitmentSelector.OPEN_EMI)) {
            if (i.Due_Date__c <= horizon) {
                flows.add(new Flow(i.Due_Date__c < today ? today : i.Due_Date__c, DuesProcessor.emiLabel(loans.get(i.Loan__c).Name), -i.EMI_Amount__c));
            }
        }
        for (CommitmentDtos.DueItem due : DuesService.upcoming(s.ctx, 90)) {
            if (due.kind == 'card') {
                flows.add(new Flow(due.dueDate < today ? today : due.dueDate, due.title, -due.amount));
            }
        }
        flows.sort();

        r.chart = new Chart('line').serie('balance', 'Projected balance');
        r.table = new Table().col('date', 'Date', 'date').col('item', 'Item', 'text').col('amount', 'Amount', 'money').col('balance', 'Balance after', 'money');
        r.table.title = 'Expected money in and out';
        Decimal balance = start;
        Decimal lowest = start;
        Date lowestOn = today;
        Integer next = 0;
        Map<Integer, Decimal> checkpoints = new Map<Integer, Decimal>();
        for (Integer week = 0; week <= 13; week++) {
            Date until = today.addDays(week * 7);
            while (next < flows.size() && flows[next].d <= until) {
                Flow f = flows[next++];
                balance += f.amount;
                r.table.rows.add(new Map<String, Object>{ 'date' => f.d, 'item' => f.label, 'amount' => f.amount, 'balance' => balance });
                if (balance < lowest) {
                    lowest = balance;
                    lowestOn = f.d;
                }
            }
            Point p = new Point();
            p.label = String.valueOf(until);
            p.values.put('balance', balance);
            r.chart.points.add(p);
            checkpoints.put(week, balance);
        }
        r.kpis.add(new Kpi('Today', start, 'money', 'bank, cash and wallets'));
        r.kpis.add(new Kpi('In 30 days', checkpoints.get(4), 'money', null));
        r.kpis.add(new Kpi('In 90 days', checkpoints.get(13), 'money', null));
        r.kpis.add(new Kpi('Lowest point', lowest, 'money', String.valueOf(lowestOn)));
        r.note = 'Built from recurring entries, bills, EMIs and card bills. Day-to-day spending you haven\'t set up as recurring isn\'t included.';
    }

    private static void account(Scope s, Report r) {
        AccessGuard.require(s.ctx, 'ACCOUNTS', 'READ');
        Id accountId = VkfRest.toId(s.params.get('accountId'));
        if (accountId == null) {
            throw new PortalException('VALIDATION').withError('Choose an account.');
        }
        Financial_Account__c a = new AccountSelector(s.ctx).byId(accountId);
        if (!new LedgerScope(s.ctx).canSeeAccount(a)) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        Boolean liability = LedgerUtil.isLiability(a.Type__c);
        r.title = a.Name + ' statement';
        r.subtitle = (liability ? 'Amount owed' : 'Running balance') + ' · ' + a.Type__c;
        // Archived entries are gone from the ledger: their net effect is part of the opening position,
        // so the statement can't start inside the archived period.
        Decimal archived = LedgerUtil.zeroIfNull(a.Archived_Net__c);
        Decimal opening = LedgerUtil.zeroIfNull(a.Opening_Balance__c) + (liability ? -archived : archived);
        Date start = s.fromDate;
        Date through = archivedThrough(s.ctx.familyId);
        if (through != null && start <= through) {
            start = through.addDays(1);
            r.fromDate = start;
        }
        TransactionSelector.Filter before = new TransactionSelector.Filter();
        before.wholeFamily = true;
        before.accountIds = new Set<Id>{ a.Id };
        before.toDate = start.addDays(-1);
        for (AggregateResult ar : s.selector.aggregate('Direction__c d, SUM(Amount__c) s', before, 'Direction__c')) {
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            Boolean credit = (String) ar.get('d') == 'Credit';
            opening += (credit != liability) ? amount : -amount;
        }
        Decimal balance = opening;
        Decimal moneyIn = 0;
        Decimal moneyOut = 0;
        r.chart = new Chart('line').serie('balance', liability ? 'Owed' : 'Balance');
        r.table = new Table().col('date', 'Date', 'date').col('description', 'Description', 'text').col('out', 'Money out', 'money')
            .col('in', 'Money in', 'money').col('balance', liability ? 'Owed' : 'Balance', 'money');
        Map<String, Decimal> byDay = new Map<String, Decimal>();
        for (Transaction__c t : s.selector.forAccount(a.Id, start, s.toDate, 2000)) {
            Boolean credit = t.Direction__c == 'Credit';
            balance += (credit != liability) ? t.Amount__c : -t.Amount__c;
            if (credit) {
                moneyIn += t.Amount__c;
            } else {
                moneyOut += t.Amount__c;
            }
            r.table.rows.add(new Map<String, Object>{
                'id' => t.Id, 'date' => t.Txn_Date__c, 'description' => String.isNotBlank(t.Payee__c) ? t.Payee__c : t.Type__c,
                'out' => credit ? null : t.Amount__c, 'in' => credit ? t.Amount__c : null, 'balance' => balance
            });
            byDay.put(String.valueOf(t.Txn_Date__c), balance);
        }
        Point first = new Point();
        first.label = String.valueOf(start);
        first.values.put('balance', opening);
        r.chart.points.add(first);
        for (String day : byDay.keySet()) {
            Point p = new Point();
            p.label = day;
            p.values.put('balance', byDay.get(day));
            r.chart.points.add(p);
        }
        r.kpis.add(new Kpi(liability ? 'Owed at start' : 'Opening balance', opening, 'money', null));
        r.kpis.add(new Kpi('Money in', moneyIn, 'money', null));
        r.kpis.add(new Kpi('Money out', moneyOut, 'money', null));
        r.kpis.add(new Kpi(liability ? 'Owed at end' : 'Closing balance', balance, 'money', null));
    }

    private static void cards(Scope s, Report r) {
        AccessGuard.require(s.ctx, 'ACCOUNTS', 'READ');
        r.title = 'Credit cards';
        r.subtitle = 'Card spending by category, payments and how much of each limit is used';
        List<Financial_Account__c> cards = new List<Financial_Account__c>();
        for (Financial_Account__c a : new AccountSelector(s.ctx).visible(false)) {
            if (a.Type__c == 'Credit Card') {
                cards.add(a);
            }
        }
        Set<Id> cardIds = new Map<Id, Financial_Account__c>(cards).keySet();
        TransactionSelector.Filter f = s.period(s.fromDate, s.toDate, null);
        f.accountIds = cardIds;
        Map<Id, Decimal> spent = new Map<Id, Decimal>();
        Map<Id, Decimal> paid = new Map<Id, Decimal>();
        for (AggregateResult ar : s.selector.aggregate('Account__c a, Type__c t, Direction__c d, SUM(Amount__c) s', f, 'Account__c, Type__c, Direction__c')) {
            Id cardId = (Id) ar.get('a');
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            String type = (String) ar.get('t');
            if (type == 'Card Payment') {
                paid.put(cardId, (paid.containsKey(cardId) ? paid.get(cardId) : 0) + amount);
            } else if (SPEND_TYPES.contains(type)) {
                spent.put(cardId, (spent.containsKey(cardId) ? spent.get(cardId) : 0) + (type == 'Refund' ? -amount : amount));
            }
        }
        Decimal totalSpent = 0;
        Decimal totalOwed = 0;
        r.detail = new Table().col('name', 'Card', 'text').col('spent', 'Spent', 'money').col('paid', 'Paid', 'money')
            .col('owed', 'Outstanding', 'money').col('pool', 'Limit group', 'text').col('limit', 'Limit', 'money').col('used', 'Used', 'percent');
        r.detail.title = 'By card';
        List<FinanceDtos.Account> cardViews = AccountService.toDtos(s.ctx, cards);
        for (FinanceDtos.Account c : cardViews) {
            Decimal cardSpent = spent.containsKey(c.id) ? spent.get(c.id) : 0;
            totalSpent += cardSpent;
            totalOwed += c.balance;
            r.detail.rows.add(new Map<String, Object>{
                'id' => c.id, 'name' => c.name, 'spent' => cardSpent, 'paid' => paid.containsKey(c.id) ? paid.get(c.id) : 0, 'owed' => c.balance,
                'pool' => c.sharedCredit != null ? c.sharedCredit.name : (c.sharedCreditRestricted ? 'Restricted shared limit' : 'Independent'),
                'limit' => c.creditLimit, 'used' => c.card?.utilisationPct
            });
        }
        r.kpis.add(new Kpi('Spent on cards', totalSpent, 'money', null));
        r.kpis.add(new Kpi('Outstanding now', totalOwed, 'money', null));
        r.kpis.add(new Kpi('Cards', cards.size(), 'number', null));
        CreditLimitGroupService.CreditTotals credit = CreditLimitGroupService.totals(cardViews);
        if (credit.complete) {
            r.kpis.add(new Kpi('Total credit limit', credit.creditLimit, 'money', 'Shared limits counted once'));
            r.kpis.add(new Kpi('Available credit', credit.available, 'money', 'Across visible credit facilities'));
        } else r.note = 'Shared credit totals are withheld because some linked cards are outside your visibility.';
        TransactionSelector.Filter byCategory = s.period(s.fromDate, s.toDate, SPEND_TYPES);
        byCategory.accountIds = cardIds;
        rankedCategories(s, r, rollUp(s, spendByCategory(s, byCategory), null), null);
    }

    private static void loans(Scope s, Report r) {
        List<CommitmentDtos.Loan> loans = LoanService.listLoans(s.ctx);
        Date today = Date.today();
        Date fyStart = Date.newInstance(today.month() >= 4 ? today.year() : today.year() - 1, 4, 1);
        r.title = 'Loans and EMIs';
        r.subtitle = 'Financial year from ' + String.valueOf(fyStart);
        r.fromDate = fyStart;
        r.toDate = today;
        Map<Id, CommitmentDtos.Loan> byAccount = new Map<Id, CommitmentDtos.Loan>();
        Set<Id> loanIds = new Set<Id>();
        for (CommitmentDtos.Loan l : loans) {
            byAccount.put(l.loanAccountId, l);
            loanIds.add(l.id);
        }
        Id fid = s.ctx.familyId;
        Map<Id, Decimal> interest = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT EMI_Installment__r.Loan__c l, SUM(Amount__c) s FROM Transaction__c
            WHERE Family__c = :fid AND Type__c = 'Expense' AND EMI_Installment__r.Loan__c IN :loanIds AND Status__c != 'Void' AND Txn_Date__c >= :fyStart
            WITH SYSTEM_MODE GROUP BY EMI_Installment__r.Loan__c
        ]) {
            interest.put((Id) ar.get('l'), LedgerUtil.zeroIfNull(ar.get('s')));
        }
        Map<Id, Decimal> principal = new Map<Id, Decimal>();
        TransactionSelector.Filter f = new TransactionSelector.Filter();
        f.wholeFamily = true;
        f.accountIds = byAccount.keySet();
        f.fromDate = fyStart;
        f.types = new Set<String>{ 'EMI Payment' };
        for (AggregateResult ar : s.selector.aggregate('Account__c a, SUM(Amount__c) s', f, 'Account__c')) {
            principal.put(byAccount.get((Id) ar.get('a')).id, LedgerUtil.zeroIfNull(ar.get('s')));
        }
        Decimal owed = 0;
        Decimal interestYear = 0;
        Decimal principalYear = 0;
        Decimal emis = 0;
        r.chart = new Chart('ranked').serie('amount', 'Outstanding');
        r.table = new Table().col('name', 'Loan', 'text').col('outstanding', 'Outstanding', 'money').col('repaid', 'Repaid', 'percent')
            .col('emi', 'EMI', 'money').col('left', 'EMIs left', 'number').col('payoff', 'Debt-free by', 'date')
            .col('interest', 'Interest this FY', 'money').col('principal', 'Principal this FY', 'money');
        for (CommitmentDtos.Loan l : loans) {
            Decimal paidInterest = interest.containsKey(l.id) ? interest.get(l.id) : 0;
            Decimal paidPrincipal = principal.containsKey(l.id) ? principal.get(l.id) : 0;
            if (l.status == 'Active') {
                owed += l.outstanding;
                emis += l.emi;
            }
            interestYear += paidInterest;
            principalYear += paidPrincipal;
            Point p = new Point();
            p.label = l.name;
            p.id = l.id;
            p.values.put('amount', l.outstanding);
            r.chart.points.add(p);
            r.table.rows.add(new Map<String, Object>{
                'id' => l.id, 'name' => l.name, 'outstanding' => l.outstanding, 'repaid' => l.repaidPct, 'emi' => l.emi, 'left' => l.installmentsLeft,
                'payoff' => l.payoffDate, 'interest' => paidInterest, 'principal' => paidPrincipal
            });
        }
        r.kpis.add(new Kpi('Outstanding', owed, 'money', null));
        r.kpis.add(new Kpi('EMIs each month', emis, 'money', null));
        r.kpis.add(new Kpi('Interest paid this FY', interestYear, 'money', 'useful for tax declarations'));
        r.kpis.add(new Kpi('Principal repaid this FY', principalYear, 'money', null));
    }

    private static void bills(Scope s, Report r) {
        CommitmentDtos.BillsView view = BillService.listBills(s.ctx);
        r.title = 'Bills';
        r.subtitle = 'Paid on time or late, and what each biller costs a year';
        Map<Id, Integer[]> punctuality = new Map<Id, Integer[]>();
        Map<Id, Decimal> paidInPeriod = new Map<Id, Decimal>();
        Set<Id> billIds = new Set<Id>();
        for (CommitmentDtos.Bill b : view.bills) {
            billIds.add(b.id);
        }
        Integer onTime = 0;
        Integer late = 0;
        for (Bill_Instance__c i : new CommitmentSelector(s.ctx).instances(billIds, new Set<String>{ 'Paid', 'Partially Paid' }, s.toDate.addDays(90))) {
            if (i.Paid_On__c == null || i.Paid_On__c < s.fromDate || i.Paid_On__c > s.toDate) {
                continue;
            }
            Integer[] counts = punctuality.containsKey(i.Bill__c) ? punctuality.get(i.Bill__c) : new List<Integer>{ 0, 0 };
            Boolean wasOnTime = i.Paid_On__c <= i.Due_Date__c;
            Integer slot = wasOnTime ? 0 : 1;
            counts[slot] = counts[slot] + 1;
            if (wasOnTime) {
                onTime++;
            } else {
                late++;
            }
            punctuality.put(i.Bill__c, counts);
            paidInPeriod.put(i.Bill__c, (paidInPeriod.containsKey(i.Bill__c) ? paidInPeriod.get(i.Bill__c) : 0) + LedgerUtil.zeroIfNull(i.Amount_Paid__c));
        }
        Decimal total = 0;
        r.chart = new Chart('ranked').serie('amount', 'Last 12 months');
        r.table = new Table().col('name', 'Biller', 'text').col('frequency', 'Comes', 'text').col('paid', 'Paid in period', 'money')
            .col('onTime', 'On time', 'number').col('late', 'Late', 'number').col('year', 'Last 12 months', 'money').col('next', 'Next due', 'date');
        for (CommitmentDtos.Bill b : view.bills) {
            Decimal paid = paidInPeriod.containsKey(b.id) ? paidInPeriod.get(b.id) : 0;
            total += paid;
            Integer[] counts = punctuality.containsKey(b.id) ? punctuality.get(b.id) : new List<Integer>{ 0, 0 };
            Point p = new Point();
            p.label = b.name;
            p.id = b.id;
            p.icon = b.icon;
            p.color = b.color;
            p.values.put('amount', b.paidLast12Months);
            r.chart.points.add(p);
            r.table.rows.add(new Map<String, Object>{
                'id' => b.id, 'name' => b.name, 'frequency' => b.frequency, 'paid' => paid, 'onTime' => counts[0], 'late' => counts[1],
                'year' => b.paidLast12Months, 'next' => b.active ? b.nextDueDate : null
            });
        }
        r.kpis.add(new Kpi('Paid in period', total, 'money', null));
        r.kpis.add(new Kpi('On time', onTime + late == 0 ? null : (Decimal.valueOf(onTime) / (onTime + late) * 100).setScale(0, RoundingMode.HALF_UP), 'percent', onTime + ' of ' + (onTime + late) + ' payments'));
        r.kpis.add(new Kpi('Overdue now', view.overdue, 'money', null));
        r.kpis.add(new Kpi('Due in 30 days', view.dueNext30, 'money', null));
    }

    private static void modes(Scope s, Report r) {
        r.title = 'Payment modes';
        r.subtitle = 'How the family pays: UPI, cash, cards and bank transfers';
        r.chart = new Chart('ranked').serie('amount', 'Spent');
        r.table = new Table().col('name', 'Mode', 'text').col('amount', 'Spent', 'money').col('share', 'Share', 'percent').col('count', 'Payments', 'number');
        List<Ranked> ranked = new List<Ranked>();
        Map<String, Integer> counts = new Map<String, Integer>();
        Decimal total = 0;
        for (AggregateResult ar : s.selector.aggregate(
            'Payment_Mode__c m, SUM(Amount__c) s, COUNT(Id) n', s.period(s.fromDate, s.toDate, new Set<String>{ 'Expense', 'Bill Payment' }), 'Payment_Mode__c'
        )) {
            String mode = ar.get('m') == null ? 'Not recorded' : (String) ar.get('m');
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            ranked.add(new Ranked(mode, amount));
            counts.put(mode, (Integer) ar.get('n'));
            total += amount;
        }
        ranked.sort();
        for (Ranked item : ranked) {
            Point p = new Point();
            p.label = item.id;
            p.values.put('amount', item.amount);
            r.chart.points.add(p);
            r.table.rows.add(new Map<String, Object>{
                'name' => item.id, 'amount' => item.amount, 'share' => total == 0 ? 0 : (item.amount / total * 100).setScale(1, RoundingMode.HALF_UP), 'count' => counts.get(item.id)
            });
        }
        r.kpis.add(new Kpi('Spent', total, 'money', null));
        r.kpis.add(new Kpi('Top mode', null, 'text', ranked.isEmpty() ? '—' : ranked[0].id));
    }

    private static void annual(Scope s, Report r) {
        Date today = Date.today();
        Date fyStart = String.isBlank(s.params.get('from')) ? Date.newInstance(today.month() >= 4 ? today.year() : today.year() - 1, 4, 1) : s.fromDate;
        Date fyEnd = String.isBlank(s.params.get('from')) ? fyStart.addYears(1).addDays(-1) : s.toDate;
        r.title = 'Annual summary';
        r.subtitle = 'Year totals and tax-relevant spending and income';
        r.fromDate = fyStart;
        r.toDate = fyEnd;
        kpiTotals(r, totals(s, fyStart, fyEnd));
        Map<Id, Decimal[]> spend = spendByCategory(s, s.period(fyStart, fyEnd, SPEND_TYPES));
        Map<Id, Decimal[]> income = spendByCategory(s, s.period(fyStart, fyEnd, new Set<String>{ 'Income' }));
        r.table = new Table().col('name', 'Category', 'text').col('kind', 'Kind', 'text').col('amount', 'Amount', 'money');
        r.table.title = 'Tax-relevant (medical insurance, education, home-loan interest, donations, interest income…)';
        Decimal taxTotal = 0;
        for (Integer pass = 0; pass < 2; pass++) {
            Map<Id, Decimal[]> source = pass == 0 ? spend : income;
            for (Id categoryId : source.keySet()) {
                Category__c c = s.cats.get(categoryId);
                Category__c top = s.categories.topLevel(categoryId);
                if (c == null || !(c.Tax_Relevant__c || (top != null && top.Tax_Relevant__c))) {
                    continue;
                }
                if (pass == 0) {
                    taxTotal += source.get(categoryId)[0];
                }
                r.table.rows.add(new Map<String, Object>{ 'id' => c.Id, 'name' => c.Name, 'kind' => c.Kind__c, 'amount' => source.get(categoryId)[0] });
            }
        }
        r.kpis.add(new Kpi('Tax-relevant spending', taxTotal, 'money', null));
        Report ranked = new Report();
        rankedCategories(s, ranked, rollUp(s, spend, null), null);
        r.chart = ranked.chart;
        r.detail = ranked.table;
        r.detail.title = 'Spending by category';
        r.note = 'Financial year April to March. Check with your tax adviser before filing.';
    }

    private static void security(Scope s, Report r) {
        r.title = 'Security and activity';
        r.subtitle = 'Sign-ins, sessions, locked accounts and recent admin actions';
        Id fid = s.ctx.familyId;
        Datetime since = Datetime.newInstance(s.fromDate, Time.newInstance(0, 0, 0, 0));
        Datetime until = Datetime.newInstance(s.toDate.addDays(1), Time.newInstance(0, 0, 0, 0));
        Map<Id, Integer> signIns = new Map<Id, Integer>();
        Integer total = 0;
        for (AggregateResult ar : [
            SELECT Portal_User__c u, COUNT(Id) n FROM Portal_Session__c
            WHERE Family__c = :fid AND CreatedDate >= :since AND CreatedDate < :until WITH SYSTEM_MODE GROUP BY Portal_User__c
        ]) {
            signIns.put((Id) ar.get('u'), (Integer) ar.get('n'));
            total += (Integer) ar.get('n');
        }
        Integer active = [SELECT COUNT() FROM Portal_Session__c WHERE Family__c = :fid AND Status__c = 'Active' WITH SYSTEM_MODE];
        Integer locked = 0;
        r.chart = new Chart('ranked').serie('amount', 'Sign-ins');
        r.table = new Table().col('name', 'Member', 'text').col('role', 'Role', 'text').col('status', 'Status', 'text').col('signIns', 'Sign-ins', 'number')
            .col('lastLogin', 'Last sign-in', 'datetime').col('failed', 'Failed attempts', 'number').col('locked', 'Locked', 'text');
        Map<Id, String> names = new Map<Id, String>();
        for (Portal_User__c m : [
            SELECT Id, First_Name__c, Last_Name__c, Role__c, Status__c, Last_Login__c, Failed_Login_Count__c, Locked_Until__c
            FROM Portal_User__c WHERE Family__c = :fid AND Status__c != 'Removed' WITH SYSTEM_MODE ORDER BY First_Name__c
        ]) {
            Boolean isLocked = m.Locked_Until__c != null && m.Locked_Until__c > Datetime.now();
            if (isLocked) {
                locked++;
            }
            String name = FinanceDtos.personName(m.First_Name__c, m.Last_Name__c);
            names.put(m.Id, name);
            Point p = new Point();
            p.label = name;
            p.values.put('amount', signIns.containsKey(m.Id) ? signIns.get(m.Id) : 0);
            r.chart.points.add(p);
            r.table.rows.add(new Map<String, Object>{
                'id' => m.Id, 'name' => name, 'role' => m.Role__c, 'status' => m.Status__c, 'signIns' => signIns.containsKey(m.Id) ? signIns.get(m.Id) : 0,
                'lastLogin' => m.Last_Login__c, 'failed' => m.Failed_Login_Count__c, 'locked' => isLocked ? 'Yes' : 'No'
            });
        }
        r.detail = new Table().col('time', 'When', 'datetime').col('member', 'Who', 'text').col('event', 'What', 'text').col('details', 'Details', 'text');
        r.detail.title = 'Recent activity (last 30 days)';
        Integer adminActions = 0;
        try {
            for (SObject e : Database.queryWithBinds(
                'SELECT Event_Time__c, Event_Type__c, Actor_Id__c, Details__c FROM Audit_Log__b WHERE Family_Id__c = :fid AND Event_Time__c >= :since LIMIT 200',
                new Map<String, Object>{ 'fid' => fid, 'since' => Datetime.now().addDays(-30) },
                AccessLevel.SYSTEM_MODE
            )) {
                String type = (String) e.get('Event_Type__c');
                if (type.startsWith('MEMBER') || type.startsWith('ACCOUNT') || type.startsWith('CATEGORY') || type.startsWith('BUDGET') || type.startsWith('LOAN') || type.startsWith('BILL')) {
                    adminActions++;
                }
                String actor = (String) e.get('Actor_Id__c');
                r.detail.rows.add(new Map<String, Object>{
                    'time' => e.get('Event_Time__c'), 'member' => actor != null && names.containsKey(actor) ? names.get(actor) : 'System',
                    'event' => type.replace('_', ' ').toLowerCase().capitalize(), 'details' => e.get('Details__c')
                });
            }
        } catch (Exception ex) {
            r.note = 'Recent activity is not available right now.';
        }
        r.kpis.add(new Kpi('Sign-ins', total, 'number', null));
        r.kpis.add(new Kpi('Active sessions', active, 'number', null));
        r.kpis.add(new Kpi('Locked accounts', locked, 'number', null));
        r.kpis.add(new Kpi('Changes in 30 days', adminActions, 'number', null));
    }

    private class Ranked implements Comparable {
        String id;
        Decimal amount;

        Ranked(String id, Decimal amount) {
            this.id = id;
            this.amount = amount;
        }

        public Integer compareTo(Object other) {
            Decimal theirs = ((Ranked) other).amount;
            return amount > theirs ? -1 : amount < theirs ? 1 : 0;
        }
    }
}