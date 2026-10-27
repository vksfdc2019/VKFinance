/** Reports, saved reports, dashboard layout and monthly snapshots. */
@IsTest
private class ReportServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    static Map<String, String> period(Date f, Date t) {
        return new Map<String, String>{ 'from' => String.valueOf(f), 'to' => String.valueOf(t) };
    }

    static Map<String, Object> rowNamed(ReportService.Table t, String name) {
        for (Map<String, Object> row : t.rows) {
            if (row.get('name') == name) {
                return row;
            }
        }
        return null;
    }

    @IsTest
    static void ledgerReportsAddUp() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 100000).id;
        Id card = LedgerTestData.account(admin, 'Card', 'Credit Card', 0).id;
        Date d = Date.today().toStartOfMonth();
        LedgerTestData.entry(admin, 'Income', 50000, savings, LedgerTestData.categoryId(admin, 'Salary'), d, 'Employer');
        LedgerTestData.entry(admin, 'Expense', 12000, savings, LedgerTestData.categoryId(admin, 'Rent'), d, 'Landlord');
        LedgerTestData.entry(admin, 'Expense', 3000, card, LedgerTestData.categoryId(admin, 'Groceries'), d, 'DMart');
        LedgerTestData.entry(admin, 'Expense', 1000, card, LedgerTestData.categoryId(admin, 'Restaurants and Takeaway'), d, 'Cafe');
        Map<String, String> month = period(d, LedgerUtil.monthEnd(d));

        Test.startTest();
        ReportService.Report summary = ReportService.run(admin, 'summary', month);
        Assert.areEqual(50000, summary.kpis[0].value);
        Assert.areEqual(16000, summary.kpis[1].value);
        Assert.areEqual(68.0, summary.kpis[3].value);
        Assert.areEqual('Housing', summary.chart.points[0].label);
        Assert.areEqual('category', summary.drill);

        Id food = LedgerTestData.categoryId(admin, 'Food and Dining');
        Map<String, String> drill = month.clone();
        drill.put('categoryId', food);
        ReportService.Report category = ReportService.run(admin, 'category', drill);
        Assert.areEqual(4000, category.kpis[0].value);
        Assert.areEqual(2, category.table.rows.size());
        Assert.areEqual('transactions', category.drill);

        ReportService.Report modes = ReportService.run(admin, 'modes', month);
        Assert.areEqual(16000, modes.kpis[0].value);

        ReportService.Report trend = ReportService.run(admin, 'trend', month);
        Assert.areEqual(12, trend.chart.points.size());
        Assert.areEqual(50000, trend.chart.points[11].values.get('income'));

        Map<String, String> statement = month.clone();
        statement.put('accountId', savings);
        ReportService.Report account = ReportService.run(admin, 'account', statement);
        Assert.areEqual(100000, account.kpis[0].value);
        Assert.areEqual(138000, account.kpis[3].value);

        ReportService.Report cards = ReportService.run(admin, 'cards', month);
        Assert.areEqual(4000, cards.kpis[0].value);
        Assert.areEqual(1, cards.detail.rows.size());

        ReportService.Report annual = ReportService.run(admin, 'annual', new Map<String, String>());
        Assert.areEqual(50000, annual.kpis[0].value);
        Assert.isNotNull(annual.detail);
        Test.stopTest();
    }

    @IsTest
    static void commitmentReportsAndForecast() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 100000).id;
        BudgetService.saveBudget(admin, LedgerUtil.monthKey(Date.today()), (Map<String, Object>) JSON.deserializeUntyped(
            '{"lines":[{"categoryId":"' + LedgerTestData.categoryId(admin, 'Food and Dining') + '","planned":5000}]}'
        ));
        LedgerTestData.entry(admin, 'Expense', 6000, savings, LedgerTestData.categoryId(admin, 'Groceries'));
        CommitmentDtos.Bill bill = BillService.createBill(admin, new Map<String, Object>{
            'name' => 'Internet', 'categoryId' => LedgerTestData.categoryId(admin, 'Internet'), 'nextDueDate' => String.valueOf(Date.today().addDays(5)),
            'expectedAmount' => 1000, 'payFromAccountId' => savings
        });
        BillService.payInstance(admin, BillService.listBills(admin).open[0].id, new Map<String, Object>());
        LoanService.createLoan(admin, new Map<String, Object>{
            'name' => 'Car loan', 'loanType' => 'Car', 'principal' => 120000, 'annualRate' => 10, 'tenureMonths' => 12,
            'firstEmiDate' => String.valueOf(Date.today().addDays(10)), 'debitAccountId' => savings
        });
        RecurringService.createRule(admin, new Map<String, Object>{
            'name' => 'Salary', 'type' => 'Income', 'amount' => 80000, 'accountId' => savings, 'categoryId' => LedgerTestData.categoryId(admin, 'Salary'),
            'nextRunDate' => String.valueOf(Date.today().addDays(20))
        });

        Test.startTest();
        ReportService.Report budget = ReportService.run(admin, 'budget', new Map<String, String>());
        Assert.areEqual(5000, budget.kpis[0].value);
        Assert.areEqual(1, budget.kpis[3].value, 'one category over plan');
        Assert.areEqual(5000, budget.chart.points[0].target);

        ReportService.Report bills = ReportService.run(admin, 'bills', new Map<String, String>());
        Assert.areEqual(1000, bills.kpis[0].value);
        Assert.areEqual(100, bills.kpis[1].value, 'paid before the due date');

        ReportService.Report loans = ReportService.run(admin, 'loans', new Map<String, String>());
        Assert.areEqual(120000, loans.kpis[0].value);
        Assert.areEqual(1, loans.table.rows.size());

        ReportService.Report forecast = ReportService.run(admin, 'forecast', new Map<String, String>());
        Assert.areEqual(93000, forecast.kpis[0].value, 'bank today after spending and the bill');
        Assert.areEqual(14, forecast.chart.points.size());
        Boolean salarySeen = false;
        for (Map<String, Object> row : forecast.table.rows) {
            salarySeen = salarySeen || row.get('item') == 'Salary';
        }
        Assert.isTrue(salarySeen, 'recurring income is in the forecast');

        ReportService.Report members = ReportService.run(admin, 'members', new Map<String, String>());
        Assert.areEqual(4, members.table.rows.size());
        ReportService.Report security = ReportService.run(admin, 'security', new Map<String, String>());
        Assert.isTrue(security.kpis[0].value >= 1, 'this test signed in');
        Test.stopTest();
    }

    @IsTest
    static void scopeAndValidation() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id privateAcct = LedgerTestData.account(admin, 'Admin Private', 'Savings', 1000).id;
        LedgerTestData.entry(admin, 'Expense', 700, privateAcct, LedgerTestData.categoryId(admin, 'Groceries'));
        UserContext member = VkfTestData.ctx('membera');
        Test.startTest();
        Assert.areEqual(0, ReportService.run(member, 'summary', new Map<String, String>()).kpis[1].value, 'members see only their own money');
        for (String adminOnly : new List<String>{ 'members', 'forecast', 'bills', 'annual', 'security' }) {
            try {
                ReportService.run(member, adminOnly, new Map<String, String>());
                Assert.fail(adminOnly + ' is for admins');
            } catch (PortalException e) {
                Assert.areEqual('NOT_AUTHORIZED', e.code());
            }
        }
        List<Map<String, String>> bad = new List<Map<String, String>>{
            period(Date.today(), Date.today().addDays(-1)),
            period(Date.today().addYears(-5), Date.today()),
            new Map<String, String>{ 'accountId' => privateAcct }
        };
        List<String> expected = new List<String>{ 'VALIDATION', 'VALIDATION', 'NOT_FOUND' };
        for (Integer i = 0; i < bad.size(); i++) {
            try {
                ReportService.run(member, i == 2 ? 'account' : 'summary', bad[i]);
                Assert.fail('expected ' + expected[i]);
            } catch (PortalException e) {
                Assert.areEqual(expected[i], e.code());
            }
        }
        try {
            ReportService.run(admin, 'nope', new Map<String, String>());
            Assert.fail('unknown report');
        } catch (PortalException e) {
            Assert.areEqual('NOT_FOUND', e.code());
        }
        UserContext adminB = VkfTestData.ctx('adminb');
        try {
            ReportService.run(adminB, 'account', new Map<String, String>{ 'accountId' => privateAcct });
            Assert.fail('another family\'s account');
        } catch (PortalException e) {
            Assert.areEqual('NOT_FOUND', e.code());
        }
        Assert.areEqual(0, ReportService.run(adminB, 'summary', new Map<String, String>()).kpis[1].value);
        Test.stopTest();
    }

    @IsTest
    static void savedReportsAndLayout() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        InsightService.SavedReport mine = InsightService.saveReport(admin, (Map<String, Object>) JSON.deserializeUntyped(
            '{"name":"Food this year","reportType":"category","filters":{"from":"2026-04-01","to":"2027-03-31"},"shared":true}'
        ));
        Assert.isTrue(mine.mine);
        Assert.areEqual('2026-04-01', mine.filters.get('from'));
        InsightService.saveReport(admin, new Map<String, Object>{ 'name' => 'Private one', 'reportType' => 'summary' });
        UserContext member = VkfTestData.ctx('membera');
        List<InsightService.SavedReport> visible = InsightService.savedReports(member);
        Assert.areEqual(1, visible.size(), 'members see shared reports, not private ones');
        Assert.isFalse(visible[0].mine);
        try {
            InsightService.deleteReport(member, mine.id);
            Assert.fail('only the owner or Family Admin deletes');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        try {
            InsightService.saveReport(member, new Map<String, Object>{ 'name' => '', 'reportType' => 'x', 'filters' => new Map<String, Object>{ 'evil' => 1 } });
            Assert.fail('validation');
        } catch (PortalException e) {
            Assert.areEqual(3, e.errors.size());
        }
        try {
            InsightService.deleteReport(VkfTestData.ctx('adminb'), mine.id);
            Assert.fail('other family');
        } catch (PortalException e) {
            Assert.areEqual('NOT_FOUND', e.code());
        }
        InsightService.deleteReport(admin, mine.id);
        Assert.areEqual(1, InsightService.savedReports(admin).size());

        Assert.areEqual(0, InsightService.layout(admin).size());
        List<Object> saved = InsightService.saveLayout(admin, (Map<String, Object>) JSON.deserializeUntyped(
            '{"widgets":[{"key":"recent"},{"key":"upcoming","hidden":true}]}'
        ));
        Assert.areEqual(2, saved.size());
        Assert.areEqual('recent', ((Map<String, Object>) saved[0]).get('key'));
        for (String body : new List<String>{ '{"widgets":"x"}', '{"widgets":[{"key":"hack"}]}', '{"widgets":[{"key":"recent"},{"key":"recent"}]}' }) {
            try {
                InsightService.saveLayout(admin, (Map<String, Object>) JSON.deserializeUntyped(body));
                Assert.fail('bad layout ' + body);
            } catch (PortalException e) {
                Assert.areEqual('VALIDATION', e.code());
            }
        }
    }

    @IsTest
    static void monthlySnapshotsFeedTheTrend() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 0).id;
        Date old = Date.today().toStartOfMonth().addMonths(-6);
        LedgerTestData.entry(admin, 'Income', 40000, savings, LedgerTestData.categoryId(admin, 'Salary'), old, 'Employer');
        LedgerTestData.entry(admin, 'Expense', 9000, savings, LedgerTestData.categoryId(admin, 'Groceries'), old, 'DMart');
        Test.startTest();
        Assert.areEqual(2, InsightService.snapshot(admin.familyId, old), 'family and one member');
        Monthly_Summary__c family = [SELECT Income__c, Expense__c, Savings__c, By_Category__c FROM Monthly_Summary__c WHERE Member__c = NULL WITH SYSTEM_MODE];
        Assert.areEqual(31000, family.Savings__c);
        Assert.isTrue(family.By_Category__c.contains('Groceries'));
        // A snapshot wins over live data for old months, so edits to closed months don't slow reports.
        update as system new Monthly_Summary__c(Id = family.Id, Income__c = 41000);
        ReportService.Report trend = ReportService.run(admin, 'trend', new Map<String, String>());
        Assert.areEqual(41000, trend.chart.points[5].values.get('income'));
        Assert.isTrue(InsightService.ensurePreviousMonth(admin.familyId, Date.today()) >= 1);
        Assert.areEqual(0, InsightService.ensurePreviousMonth(admin.familyId, Date.today()));
        Test.stopTest();
    }

    @IsTest
    static void restEndpoints() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('admina');
        RestResponse res = VkfTestData.call('GET', '/vkf/v1/reports/summary', null, token);
        VkfReportsResource.get();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('POST', '/vkf/v1/reports/saved', '{"name":"Mine","reportType":"trend"}', token);
        VkfReportsResource.post();
        Assert.areEqual(201, res.statusCode, res.responseBody.toString());
        String savedId = (String) VkfTestData.json(res).get('id');
        res = VkfTestData.call('GET', '/vkf/v1/reports/saved', null, token);
        VkfReportsResource.get();
        Assert.areEqual(200, res.statusCode);
        res = VkfTestData.call('PUT', '/vkf/v1/reports/layout', '{"widgets":[{"key":"cashflow"}]}', token);
        VkfReportsResource.put();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('GET', '/vkf/v1/reports/layout', null, token);
        VkfReportsResource.get();
        Assert.areEqual(1, ((List<Object>) VkfTestData.json(res).get('widgets')).size());
        res = VkfTestData.call('DELETE', '/vkf/v1/reports/saved/' + savedId, null, token);
        VkfReportsResource.del();
        Assert.areEqual(204, res.statusCode);
        for (String m : new List<String>{ 'GET', 'POST', 'PUT', 'DELETE' }) {
            res = VkfTestData.call(m, '/vkf/v1/reports/a/b/c', m == 'GET' || m == 'DELETE' ? null : '{}', token);
            if (m == 'GET') {
                VkfReportsResource.get();
            } else if (m == 'POST') {
                VkfReportsResource.post();
            } else if (m == 'PUT') {
                VkfReportsResource.put();
            } else {
                VkfReportsResource.del();
            }
            Assert.areEqual(404, res.statusCode, m);
        }
    }
}
