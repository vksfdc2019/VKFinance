/** Categories, budgets and the dashboard. */
@IsTest
private class PlanningServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void categoriesAreSeededAndManagedByTheFamilyAdmin() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        List<FinanceDtos.Category> all = CategoryService.listCategories(admin);
        Assert.areEqual([SELECT COUNT() FROM Default_Category__mdt WITH SYSTEM_MODE], all.size());
        Assert.areEqual(0, CategoryService.seedDefaults(admin.familyId), 'seeding twice adds nothing');

        Id food = LedgerTestData.categoryId(admin, 'Food and Dining');
        FinanceDtos.Category created = CategoryService.createCategory(admin, new Map<String, Object>{ 'name' => 'Sweets', 'parentId' => food });
        Assert.areEqual('Expense', created.kind);
        Assert.areEqual('utensils-crossed', created.icon);
        FinanceDtos.Category top = CategoryService.createCategory(
            admin,
            new Map<String, Object>{ 'name' => 'Side Hustle', 'kind' => 'Income', 'color' => '#22c55e', 'icon' => 'rocket' }
        );
        Assert.areEqual('#22c55e', top.color);

        FinanceDtos.Category renamed = CategoryService.updateCategory(
            admin,
            created.id,
            new Map<String, Object>{ 'name' => 'Mithai', 'essential' => true, 'active' => false, 'taxRelevant' => true, 'sortOrder' => 3 }
        );
        Assert.areEqual('Mithai', renamed.name);
        Assert.isFalse(renamed.active);

        for (Map<String, Object> bad : new List<Map<String, Object>>{
            new Map<String, Object>{ 'name' => 'Groceries', 'parentId' => food },
            new Map<String, Object>{ 'name' => 'No kind' },
            new Map<String, Object>{ 'name' => 'Bad colour', 'kind' => 'Expense', 'color' => 'red' },
            new Map<String, Object>{ 'name' => 'Too deep', 'parentId' => LedgerTestData.categoryId(admin, 'Groceries') }
        }) {
            try {
                CategoryService.createCategory(admin, bad);
                Assert.fail('expected an error for ' + bad);
            } catch (PortalException e) {
                Assert.isTrue(e.code() == 'VALIDATION' || e.code() == 'CONFLICT', e.code());
            }
        }
        try {
            CategoryService.updateCategory(admin, LedgerTestData.categoryId(admin, 'Transfer'), new Map<String, Object>{ 'name' => 'Moves' });
            Assert.fail('system categories are fixed');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        try {
            CategoryService.createCategory(VkfTestData.ctx('coadmina'), new Map<String, Object>{ 'name' => 'X', 'kind' => 'Expense' });
            Assert.fail('co-admins read categories but cannot add them');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
    }

    @IsTest
    static void budgetsTrackSpendingAndCopyForward() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 50000).id;
        Id food = LedgerTestData.categoryId(admin, 'Food and Dining');
        Id transport = LedgerTestData.categoryId(admin, 'Transport');
        LedgerTestData.entry(admin, 'Expense', 3000, savings, LedgerTestData.categoryId(admin, 'Groceries'));
        LedgerTestData.entry(admin, 'Expense', 1500, savings, LedgerTestData.categoryId(admin, 'Restaurants and Takeaway'));
        LedgerTestData.entry(admin, 'Refund', 500, savings, LedgerTestData.categoryId(admin, 'Groceries'));
        LedgerTestData.entry(admin, 'Expense', 700, savings, LedgerTestData.categoryId(admin, 'Movies and Shows'));
        String month = LedgerUtil.monthKey(Date.today());

        Test.startTest();
        FinanceDtos.BudgetView empty = BudgetService.getBudget(admin, month);
        Assert.isFalse(empty.exists);
        Assert.areEqual(2, empty.unbudgeted.size());

        FinanceDtos.BudgetView saved = BudgetService.saveBudget(
            admin,
            month,
            (Map<String, Object>) JSON.deserializeUntyped(
                '{"lines":[{"categoryId":"' + food + '","planned":5000},{"categoryId":"' + transport + '","planned":2000}]}'
            )
        );
        Assert.isTrue(saved.exists);
        Assert.areEqual(7000, saved.totalPlanned);
        Assert.areEqual(4700, saved.totalSpent);
        Assert.areEqual(4000, saved.lines[0].spent, 'groceries + restaurants - refund roll up to Food and Dining');
        Assert.areEqual(1, saved.unbudgeted.size());
        Assert.areEqual('Outing and Entertainment', saved.unbudgeted[0].name);

        saved = BudgetService.saveBudget(
            admin,
            month,
            (Map<String, Object>) JSON.deserializeUntyped('{"lines":[{"categoryId":"' + transport + '","planned":0}]}')
        );
        Assert.areEqual(1, saved.lines.size(), 'a zero amount removes the line');

        String nextMonth = LedgerUtil.monthKey(Date.today().addMonths(1));
        FinanceDtos.BudgetView copied = BudgetService.copyPrevious(admin, nextMonth);
        Assert.areEqual(5000, copied.totalPlanned);
        Assert.areEqual(0, copied.totalSpent);

        UserContext member = VkfTestData.ctx('membera');
        Assert.isFalse(BudgetService.getBudget(member, month).canEdit);
        try {
            BudgetService.copyPrevious(member, nextMonth);
            Assert.fail('members read budgets only');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        for (String body : new List<String>{ '{"lines":"nope"}', '{"lines":[{"categoryId":"' + LedgerTestData.categoryId(admin, 'Groceries') + '","planned":10}]}' }) {
            try {
                BudgetService.saveBudget(admin, month, (Map<String, Object>) JSON.deserializeUntyped(body));
                Assert.fail('expected a validation error');
            } catch (PortalException e) {
                Assert.areEqual('VALIDATION', e.code());
            }
        }
        try {
            BudgetService.copyPrevious(admin, LedgerUtil.monthKey(Date.today().addMonths(-6)));
            Assert.fail('nothing to copy');
        } catch (PortalException e) {
            Assert.areEqual('NOT_FOUND', e.code());
        }
        Test.stopTest();
    }

    @IsTest
    static void dashboardSummarisesTheMonthForEachRole() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 100000).id;
        Id card = LedgerTestData.account(admin, 'Card', 'Credit Card', 0).id;
        Id salary = LedgerTestData.categoryId(admin, 'Salary');
        Date thisMonth = Date.today().toStartOfMonth();
        LedgerTestData.entry(admin, 'Income', 80000, savings, salary, thisMonth, 'Employer');
        LedgerTestData.entry(admin, 'Income', 75000, savings, salary, thisMonth.addMonths(-1), 'Employer');
        LedgerTestData.entry(admin, 'Expense', 20000, savings, LedgerTestData.categoryId(admin, 'Rent'), thisMonth, 'Landlord');
        LedgerTestData.entry(admin, 'Expense', 4000, card, LedgerTestData.categoryId(admin, 'Restaurants and Takeaway'), thisMonth, 'Cafe');
        BudgetService.saveBudget(
            admin,
            LedgerUtil.monthKey(thisMonth),
            (Map<String, Object>) JSON.deserializeUntyped('{"lines":[{"categoryId":"' + LedgerTestData.categoryId(admin, 'Food and Dining') + '","planned":3000}]}')
        );

        Test.startTest();
        FinanceDtos.Dashboard d = DashboardService.build(admin, new Map<String, String>{ 'month' => LedgerUtil.monthKey(thisMonth) });
        Assert.isTrue(d.wholeFamily);
        Assert.areEqual('INR', d.currencyCode);
        Assert.areEqual(80000, d.kpis.income);
        Assert.areEqual(24000, d.kpis.expenses);
        Assert.areEqual(56000, d.kpis.net);
        Assert.areEqual(70.0, d.kpis.savingsRate);
        Assert.areEqual(75000, d.kpis.prevIncome);
        Assert.areEqual(20000, d.kpis.essential, 'rent is a need');
        Assert.areEqual(4000, d.kpis.discretionary);
        Assert.areEqual('Housing', d.byCategory[0].name, 'largest category first');
        Assert.areEqual(6, d.trend.size());
        Assert.areEqual(80000, d.trend[5].income);
        Assert.areEqual(100000 + 80000 + 75000 - 20000, d.netWorth.assets);
        Assert.areEqual(4000, d.netWorth.liabilities);
        Assert.areEqual(1, d.budget.overCount);
        Assert.areEqual(4, d.recent.size());
        Assert.areEqual(4, d.members.size());

        FinanceDtos.Dashboard forMember = DashboardService.build(
            admin,
            new Map<String, String>{ 'memberId' => VkfTestData.userId('membera') }
        );
        Assert.areEqual(0, forMember.kpis.income);
        Assert.isNull(forMember.budget, 'the family budget is not shown for one member');

        FinanceDtos.Dashboard memberView = DashboardService.build(VkfTestData.ctx('membera'), new Map<String, String>());
        Assert.isFalse(memberView.wholeFamily);
        Assert.areEqual(0, memberView.kpis.expenses, 'the admin\'s private spending is not in a member\'s view');
        Assert.areEqual(0, memberView.accounts.size());
        Assert.areEqual(0, memberView.members.size());
        Test.stopTest();
    }

    @IsTest
    static void onboardingSeedsCategories() {
        VkfTestData.fastPolicy();
        MemberService.MemberInput admin = new MemberService.MemberInput();
        admin.firstName = 'New';
        admin.lastName = 'Family';
        admin.username = 'new.family.admin';
        admin.email = 'new.family@example.test';
        FamilyOnboardingService.Result result = FamilyOnboardingService.onboard('New Family', 'INR', 'Asia/Kolkata', 6, admin);
        Assert.areEqual(
            [SELECT COUNT() FROM Default_Category__mdt WITH SYSTEM_MODE],
            [SELECT COUNT() FROM Category__c WHERE Family__c = :result.familyId WITH SYSTEM_MODE]
        );
    }
}