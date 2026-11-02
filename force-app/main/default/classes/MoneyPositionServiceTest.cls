/** Money position: available against spent for accounts, cards, bills and loans, scoped like their pages. */
@IsTest
private class MoneyPositionServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void accountsShowWhatIsSpendableAndWhatMoved() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 100000).id;
        Id cash = LedgerTestData.account(admin, 'Cash', 'Cash', 5000).id;
        LedgerTestData.account(admin, 'Mutual funds', 'Investment', 20000);
        LedgerTestData.entry(admin, 'Income', 50000, savings, LedgerTestData.categoryId(admin, 'Salary'));
        LedgerTestData.entry(admin, 'Expense', 2000, savings, LedgerTestData.categoryId(admin, 'Groceries'));
        LedgerTestData.transfer(admin, savings, cash, 10000);

        Test.startTest();
        PositionDtos.Position p = MoneyPositionService.build(admin, new Map<String, String>());
        Test.stopTest();
        Assert.isTrue(p.isCurrent);
        Assert.areEqual(153000, p.bank.available, 'savings 1,38,000 and cash 15,000');
        Assert.areEqual(20000, p.bank.locked, 'investments are not spendable');
        Assert.areEqual(50000, p.bank.moneyIn, 'moving money to cash is not income');
        Assert.areEqual(2000, p.bank.moneyOut);
        Assert.areEqual(3, p.bank.accounts.size());
        for (PositionDtos.AccountLine line : p.bank.accounts) {
            if (line.id == savings) {
                Assert.areEqual(50000, line.moneyIn);
                Assert.areEqual(12000, line.moneyOut, 'the account itself shows the transfer');
            }
        }
        Assert.areEqual(153000, p.summary.liquid);
        Assert.areEqual(153000, p.summary.leftAfterDues, 'nothing due yet');
    }

    @IsTest
    static void cardsShowLimitUsedAndSpent() {
        UserContext admin = VkfTestData.ctx('admina');
        Id card = AccountService.createAccount(admin, new Map<String, Object>{
            'name' => 'HDFC Regalia', 'type' => 'Credit Card', 'institution' => 'HDFC Bank', 'last4' => '4321', 'creditLimit' => 300000,
            'statementDay' => 12, 'paymentDueDays' => 20, 'cardNetwork' => 'Visa'
        }).id;
        LedgerTestData.entry(admin, 'Expense', 50000, card, LedgerTestData.categoryId(admin, 'Groceries'));

        PositionDtos.Position p = MoneyPositionService.build(admin, new Map<String, String>());
        Assert.areEqual(300000, p.cards.totalLimit);
        Assert.areEqual(50000, p.cards.used);
        Assert.areEqual(250000, p.cards.available);
        Assert.areEqual(16.7, p.cards.utilisationPct);
        Assert.areEqual(50000, p.cards.spent);
        PositionDtos.CardLine line = p.cards.cards[0];
        Assert.areEqual('Visa', line.network);
        Assert.areEqual(line.dueDate.addDays(3), line.lateFeeAfter, 'RBI: 3 days before a late fee');
        Assert.isTrue(p.bank.accounts.isEmpty(), 'cards are not bank accounts');
        Assert.areEqual(50000, p.summary.owed);
    }

    @IsTest
    static void billsAndEmisDueThisMonthCountAgainstTheMoney() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        BillService.createBill(admin, new Map<String, Object>{
            'name' => 'Electricity', 'categoryId' => LedgerTestData.categoryId(admin, 'Electricity'), 'frequency' => 'Monthly',
            'nextDueDate' => String.valueOf(Date.today()), 'expectedAmount' => 1500, 'payFromAccountId' => savings
        });
        CommitmentDtos.Loan loan = LoanService.createLoan(admin, new Map<String, Object>{
            'name' => 'Home loan', 'lender' => 'SBI', 'loanType' => 'Home', 'principal' => 2012000, 'annualRate' => 9.5, 'tenureMonths' => 85,
            'firstEmiDate' => String.valueOf(Date.today().addMonths(-31)), 'installmentsPaid' => 31, 'debitAccountId' => savings
        });

        Test.startTest();
        PositionDtos.Position p = MoneyPositionService.build(admin, new Map<String, String>());
        Test.stopTest();
        Assert.areEqual(1, p.bills.count);
        Assert.areEqual(1500, p.bills.due);
        Assert.areEqual(1500, p.bills.remaining);
        Assert.areEqual(0, p.bills.paidCount);

        Assert.areEqual(1, p.loans.activeCount);
        Assert.areEqual(2012000, p.loans.borrowed);
        Assert.areEqual(loan.outstanding, p.loans.outstanding);
        Assert.areEqual(loan.emi, p.loans.monthlyEmi);
        Assert.areEqual(loan.emi, p.loans.emiDue, 'EMI 32 falls in this month');
        Assert.areEqual(loan.emi, p.loans.emiRemaining);
        Assert.areEqual('Due', p.loans.loans[0].monthStatus);

        Assert.areEqual(1500 + loan.emi, p.summary.duesRemaining);
        Assert.areEqual(500000 - 1500 - loan.emi, p.summary.leftAfterDues);
        Assert.areEqual(loan.outstanding, p.summary.owed);
    }

    @IsTest
    static void paidBillsMoveFromRemainingToPaid() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 10000).id;
        BillService.createBill(admin, new Map<String, Object>{
            'name' => 'Broadband', 'categoryId' => LedgerTestData.categoryId(admin, 'Electricity'), 'frequency' => 'Monthly',
            'nextDueDate' => String.valueOf(Date.today()), 'expectedAmount' => 999, 'payFromAccountId' => savings
        });
        BillService.payInstance(admin, BillService.listBills(admin).open[0].id, new Map<String, Object>());

        PositionDtos.Position p = MoneyPositionService.build(admin, new Map<String, String>());
        Assert.areEqual(999, p.bills.paid);
        Assert.areEqual(0, p.bills.remaining);
        Assert.areEqual(1, p.bills.paidCount);
        Assert.areEqual(999, p.bank.moneyOut, 'the bill payment left the bank');
    }

    @IsTest
    static void scopedLikeThePagesAndServedOverRest() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        LoanService.createLoan(admin, new Map<String, Object>{
            'name' => 'Car loan', 'lender' => 'HDFC', 'loanType' => 'Car', 'principal' => 600000, 'annualRate' => 9, 'tenureMonths' => 60,
            'firstEmiDate' => String.valueOf(Date.today().addMonths(1)), 'debitAccountId' => savings
        });
        Assert.areEqual(0, MoneyPositionService.build(VkfTestData.ctx('membera'), new Map<String, String>()).loans.loans.size(), 'members see their own loans');
        PositionDtos.Position other = MoneyPositionService.build(VkfTestData.ctx('adminb'), new Map<String, String>());
        Assert.areEqual(0, other.bank.accounts.size(), 'nothing crosses families');
        Assert.areEqual(0, other.loans.loans.size());

        PositionDtos.Position past = MoneyPositionService.build(admin, new Map<String, String>{ 'month' => LedgerUtil.monthKey(Date.today().addMonths(-2)) });
        Assert.isFalse(past.isCurrent);
        Assert.isNull(past.summary.leftAfterDues, 'only this month has dues still to pay');

        String token = VkfTestData.login('admina');
        RestResponse res = VkfTestData.call('GET', '/vkf/v1/dashboard/position', null, token);
        VkfDashboardResource.get();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        Assert.areEqual(500000, (Decimal) ((Map<String, Object>) VkfTestData.json(res).get('bank')).get('available'));
        res = VkfTestData.call('GET', '/vkf/v1/dashboard/nope', null, token);
        VkfDashboardResource.get();
        Assert.areEqual(404, res.statusCode);
    }
}
