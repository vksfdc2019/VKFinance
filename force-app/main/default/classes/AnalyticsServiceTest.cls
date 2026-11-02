/** Analytics: income split into EMIs, bills, spending and savings by family month, daily spend and top payees. */
@IsTest
private class AnalyticsServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void splitsTheMonthWithoutCountingMovesOrInterestTwice() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        Id cash = LedgerTestData.account(admin, 'Cash', 'Cash', 0).id;
        LedgerTestData.entry(admin, 'Income', 100000, savings, LedgerTestData.categoryId(admin, 'Salary'), Date.today(), 'Employer');
        LedgerTestData.entry(admin, 'Expense', 4000, savings, LedgerTestData.categoryId(admin, 'Groceries'), Date.today(), 'BigBasket');
        LedgerTestData.entry(admin, 'Expense', 1000, savings, LedgerTestData.categoryId(admin, 'Groceries'), Date.today(), 'BigBasket');
        LedgerTestData.entry(admin, 'Expense', 600, savings, LedgerTestData.categoryId(admin, 'Groceries'), Date.today(), 'Swiggy');
        LedgerTestData.transfer(admin, savings, cash, 2000);
        CommitmentDtos.Loan loan = LoanService.createLoan(admin, new Map<String, Object>{
            'name' => 'Home loan', 'lender' => 'SBI', 'loanType' => 'Home', 'principal' => 1000000, 'annualRate' => 9, 'tenureMonths' => 120,
            'firstEmiDate' => String.valueOf(Date.today()), 'debitAccountId' => savings
        });

        Test.startTest();
        LoanService.payEmi(admin, loan.id, new Map<String, Object>{ 'paidOn' => String.valueOf(Date.today()) });
        AnalyticsDtos.Analytics a = AnalyticsService.build(admin, new Map<String, String>{ 'months' => '6' });
        Test.stopTest();

        Assert.areEqual(6, a.series.size());
        Assert.areEqual(a.month, a.series[5].month, 'ends with the selected month');
        AnalyticsDtos.MonthFlow m = a.current;
        Assert.areEqual(100000, m.income);
        Assert.areEqual(5600, m.spending, 'loan interest and the transfer to cash are not spending');
        Assert.areEqual(loan.emi, m.emis, 'principal plus interest');
        Assert.areEqual(100000 - 5600 - loan.emi, m.saved);
        Decimal byDay = 0;
        for (AnalyticsDtos.DayAmount d : a.days) {
            byDay += d.amount;
        }
        Assert.areEqual(5600, byDay, 'the heatmap shows everyday spending');
        Assert.areEqual('BigBasket', a.payees[0].name);
        Assert.areEqual(5000, a.payees[0].amount);
        Assert.areEqual(2, a.payees[0].count);
    }

    @IsTest
    static void scopedAndServedOverRest() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 0).id;
        LedgerTestData.entry(admin, 'Income', 50000, savings, LedgerTestData.categoryId(admin, 'Salary'));
        Assert.areEqual(0, AnalyticsService.build(VkfTestData.ctx('adminb'), new Map<String, String>()).current.income, 'nothing crosses families');
        Assert.areEqual(24, AnalyticsService.build(admin, new Map<String, String>{ 'months' => '99' }).series.size(), 'capped at two years');
        Assert.areEqual(12, AnalyticsService.build(admin, new Map<String, String>{ 'months' => 'x' }).series.size());

        String token = VkfTestData.login('admina');
        RestResponse res = VkfTestData.call('GET', '/vkf/v1/dashboard/analytics', null, token);
        VkfDashboardResource.get();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        Assert.areEqual(12, ((List<Object>) VkfTestData.json(res).get('series')).size());
    }
}
