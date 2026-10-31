/** The family's month: periods from a payday start, the Family Admin setting, and the views that follow it. */
@IsTest
private class BudgetMonthTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    static Id familyWithStart(Integer day) {
        UserContext admin = VkfTestData.ctx('admina');
        BudgetMonth.save(admin, new Map<String, Object>{ 'monthStartDay' => day });
        return admin.familyId;
    }

    @IsTest
    static void calendarMonthsByDefault() {
        Id fid = VkfTestData.ctx('admina').familyId;
        BudgetMonth.Period p = BudgetMonth.of(fid, Date.newInstance(2026, 11, 1));
        Assert.areEqual(Date.newInstance(2026, 11, 1), p.startDate);
        Assert.areEqual(Date.newInstance(2026, 11, 30), p.endDate);
        Assert.areEqual('2026-11', BudgetMonth.containing(fid, Date.newInstance(2026, 11, 30)).key);
    }

    @IsTest
    static void paydayMonthsAreNamedForTheMonthTheyFund() {
        Id fid = familyWithStart(30);
        BudgetMonth.Period nov = BudgetMonth.of(fid, Date.newInstance(2026, 11, 1));
        Assert.areEqual(Date.newInstance(2026, 10, 30), nov.startDate, 'November starts on the 30 October payday');
        Assert.areEqual(Date.newInstance(2026, 11, 29), nov.endDate);
        Assert.areEqual(31, nov.days());
        BudgetMonth.Period feb = BudgetMonth.of(fid, Date.newInstance(2027, 2, 1));
        Assert.areEqual(Date.newInstance(2027, 1, 30), feb.startDate);
        Assert.areEqual(Date.newInstance(2027, 2, 27), feb.endDate, 'March starts on 28 February, the last day');
        Assert.areEqual('2026-11', BudgetMonth.containing(fid, Date.newInstance(2026, 10, 30)).key, 'salary on 30 October counts for November');
        Assert.areEqual('2026-10', BudgetMonth.containing(fid, Date.newInstance(2026, 10, 29)).key);
        Assert.areEqual('2026-11', BudgetMonth.containing(fid, Date.newInstance(2026, 11, 1)).key);
        Assert.areEqual('2026-12', BudgetMonth.containing(fid, Date.newInstance(2026, 11, 30)).key);
    }

    @IsTest
    static void earlyStartDaysNameTheMonthTheyStartIn() {
        Id fid = familyWithStart(10);
        BudgetMonth.Period nov = BudgetMonth.of(fid, Date.newInstance(2026, 11, 1));
        Assert.areEqual(Date.newInstance(2026, 11, 10), nov.startDate);
        Assert.areEqual(Date.newInstance(2026, 12, 9), nov.endDate);
        Assert.areEqual('2026-10', BudgetMonth.containing(fid, Date.newInstance(2026, 11, 9)).key);
    }

    @IsTest
    static void onlyTheFamilyAdminSetsIt() {
        UserContext admin = VkfTestData.ctx('admina');
        BudgetMonth.Settings s = BudgetMonth.save(admin, new Map<String, Object>{ 'monthStartDay' => 30 });
        Assert.areEqual(30, s.monthStartDay);
        Assert.isTrue(s.canEdit);
        Assert.areEqual(30, BudgetMonth.settings(VkfTestData.ctx('membera')).monthStartDay, 'everyone in the family shares it');
        Assert.areEqual(1, BudgetMonth.startDay(VkfTestData.ctx('adminb').familyId), 'other families are untouched');
        try {
            BudgetMonth.save(VkfTestData.ctx('coadmina'), new Map<String, Object>{ 'monthStartDay' => 1 });
            Assert.fail('co-admins cannot change it');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        for (Object bad : new List<Object>{ 0, 32, 1.5, null }) {
            try {
                BudgetMonth.save(admin, new Map<String, Object>{ 'monthStartDay' => bad });
                Assert.fail('expected a validation error: ' + bad);
            } catch (PortalException e) {
                Assert.areEqual('VALIDATION', e.code());
            }
        }
        String token = VkfTestData.login('admina');
        RestResponse res = VkfTestData.call('PUT', '/vkf/v1/family/settings', '{"monthStartDay":25}', token);
        VkfFamilyResource.put();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('GET', '/vkf/v1/family/settings', null, token);
        VkfFamilyResource.get();
        Assert.areEqual(25, VkfTestData.json(res).get('monthStartDay'));
    }

    @IsTest
    static void salaryOnPaydayShowsInTheMonthItFunds() {
        UserContext admin = VkfTestData.ctx('admina');
        Id fid = familyWithStart(30);
        BudgetMonth.Period now = BudgetMonth.containing(fid, Date.today());
        Id savings = LedgerTestData.account(admin, 'Salary account', 'Savings', 0).id;
        LedgerTestData.entry(admin, 'Income', 100000, savings, LedgerTestData.categoryId(admin, 'Salary'), now.startDate, 'Employer');
        LedgerTestData.entry(admin, 'Expense', 2500, savings, LedgerTestData.categoryId(admin, 'Groceries'), now.startDate.addDays(-1), 'Store');

        Test.startTest();
        FinanceDtos.Dashboard d = DashboardService.build(admin, new Map<String, String>());
        Test.stopTest();
        Assert.areEqual(now.key, d.month);
        Assert.areEqual(now.startDate, d.periodStart);
        Assert.areEqual(now.endDate, d.periodEnd);
        Assert.areEqual(100000, d.kpis.income, 'payday salary is this month\'s income');
        Assert.areEqual(0, d.kpis.expenses, 'the day before payday belongs to last month');
        Assert.areEqual(2500, d.kpis.prevExpenses);

        FinanceDtos.TxnPage page = TransactionService.listTransactions(admin, new Map<String, String>{ 'month' => now.key });
        Assert.areEqual(1, page.items.size(), 'the month filter follows the family month');
        FinanceDtos.BudgetView budget = BudgetService.getBudget(admin, now.key);
        Assert.areEqual(now.days(), budget.daysInMonth);
        Assert.areEqual(now.startDate, budget.periodStart);
        Assert.areEqual(30, PortalDtos.profile(admin).monthStartDay, 'the portal learns the start day at sign-in');
    }
}
