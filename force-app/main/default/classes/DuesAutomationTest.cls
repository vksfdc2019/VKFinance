/** The daily dues job, the "coming up" feed, and cross-family isolation for commitments. */
@IsTest
private class DuesAutomationTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void dailyJobAutoPaysRemindsAndAlerts() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 100000).id;
        Id card = LedgerTestData.account(admin, 'Visa', 'Credit Card', 0).id;
        Id groceries = LedgerTestData.categoryId(admin, 'Groceries');
        BillService.createBill(admin, new Map<String, Object>{
            'name' => 'Netflix', 'categoryId' => LedgerTestData.categoryId(admin, 'OTT / Streaming'), 'nextDueDate' => String.valueOf(Date.today()),
            'expectedAmount' => 649, 'payFromAccountId' => savings, 'autoPay' => true
        });
        BillService.createBill(admin, new Map<String, Object>{
            'name' => 'BESCOM', 'categoryId' => LedgerTestData.categoryId(admin, 'Electricity'), 'nextDueDate' => String.valueOf(Date.today().addDays(2)),
            'expectedAmount' => 2000
        });
        BillService.createBill(admin, new Map<String, Object>{
            'name' => 'Water', 'categoryId' => LedgerTestData.categoryId(admin, 'Water'), 'nextDueDate' => String.valueOf(Date.today().addDays(-3)),
            'expectedAmount' => 400
        });
        LoanService.createLoan(admin, new Map<String, Object>{
            'name' => 'Bike loan', 'loanType' => 'Personal', 'principal' => 60000, 'annualRate' => 10, 'tenureMonths' => 12,
            'firstEmiDate' => String.valueOf(Date.today()), 'debitAccountId' => savings, 'autoDebit' => true
        });
        LedgerTestData.entry(admin, 'Expense', 9000, card, groceries, Date.today().addDays(-45), 'DMart');
        BudgetService.saveBudget(admin, LedgerUtil.monthKey(Date.today()), (Map<String, Object>) JSON.deserializeUntyped(
            '{"lines":[{"categoryId":"' + LedgerTestData.categoryId(admin, 'Food and Dining') + '","planned":5000}]}'
        ));
        LedgerTestData.entry(admin, 'Expense', 4500, savings, groceries);

        Test.startTest();
        Database.executeBatch(new DailyDuesBatch(), 200);
        Test.stopTest();

        Assert.areEqual('Paid', [SELECT Status__c FROM Bill_Instance__c WHERE Bill__r.Name = 'Netflix' AND Due_Date__c = TODAY WITH SYSTEM_MODE].Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Transaction__c WHERE Source__c = 'Auto-pay' AND Type__c = 'Bill Payment' WITH SYSTEM_MODE]);
        Assert.areEqual(1, [SELECT Installments_Paid__c FROM Loan__c WITH SYSTEM_MODE].Installments_Paid__c, 'the EMI was auto-debited');
        Assert.areEqual(1, [SELECT COUNT() FROM Card_Statement__c WITH SYSTEM_MODE]);
        Set<String> types = new Set<String>();
        for (Notification__c n : [SELECT Type__c FROM Notification__c WITH SYSTEM_MODE]) {
            types.add(n.Type__c);
        }
        for (String expected : new List<String>{ 'BILL_AUTOPAID', 'BILL_DUE', 'BILL_OVERDUE', 'EMI_AUTOPAID', 'BUDGET_80' }) {
            Assert.isTrue(types.contains(expected), expected + ' missing from ' + types);
        }
    }

    @IsTest
    static void runningTwiceDoesNotRepeatAlerts() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        BillService.createBill(admin, new Map<String, Object>{
            'name' => 'Rent', 'categoryId' => LedgerTestData.categoryId(admin, 'Rent'), 'nextDueDate' => String.valueOf(Date.today().addDays(1)),
            'expectedAmount' => 20000
        });
        DuesProcessor.Summary first = DuesProcessor.run(admin.familyId, Date.today());
        DuesProcessor.Summary second = DuesProcessor.run(admin.familyId, Date.today());
        Assert.isTrue(first.notifications > 0);
        Assert.areEqual(0, second.notifications);
    }

    @IsTest
    static void comingUpFeedOnTheDashboard() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 100000).id;
        BillService.createBill(admin, new Map<String, Object>{
            'name' => 'Airtel', 'categoryId' => LedgerTestData.categoryId(admin, 'Internet'), 'nextDueDate' => String.valueOf(Date.today().addDays(9)),
            'expectedAmount' => 999
        });
        LoanService.createLoan(admin, new Map<String, Object>{
            'name' => 'Car loan', 'loanType' => 'Car', 'principal' => 300000, 'annualRate' => 9, 'tenureMonths' => 36,
            'firstEmiDate' => String.valueOf(Date.today().addDays(4)), 'debitAccountId' => savings
        });
        Test.startTest();
        FinanceDtos.Dashboard d = DashboardService.build(admin, new Map<String, String>());
        Test.stopTest();
        Assert.areEqual(2, d.upcoming.size());
        Assert.areEqual('emi', d.upcoming[0].kind, 'sorted by due date');
        Assert.areEqual('bill', d.upcoming[1].kind);
        Assert.areEqual(9, d.upcoming[1].daysLeft);
    }

    @IsTest
    static void scheduleRunsTheBatch() {
        Test.startTest();
        String jobId = System.schedule('VKF Daily Dues Test', '0 0 6 * * ?', new DailyDuesBatch());
        Test.stopTest();
        Assert.isNotNull(jobId);
    }

    @IsTest
    static void otherFamiliesCommitmentsAreNotFound() {
        VkfTestData.fastPolicy();
        UserContext adminA = VkfTestData.ctx('admina');
        Id savingsA = LedgerTestData.account(adminA, 'A Savings', 'Savings', 100000).id;
        Id billA = BillService.createBill(adminA, new Map<String, Object>{
            'name' => 'A bill', 'categoryId' => LedgerTestData.categoryId(adminA, 'Internet'), 'nextDueDate' => String.valueOf(Date.today().addDays(3)),
            'expectedAmount' => 500, 'payFromAccountId' => savingsA
        }).id;
        Id instanceA = [SELECT Id FROM Bill_Instance__c WHERE Bill__c = :billA WITH SYSTEM_MODE].Id;
        Id loanA = LoanService.createLoan(adminA, new Map<String, Object>{
            'name' => 'A loan', 'loanType' => 'Car', 'principal' => 100000, 'annualRate' => 9, 'tenureMonths' => 12,
            'firstEmiDate' => String.valueOf(Date.today().addDays(3)), 'debitAccountId' => savingsA
        }).id;
        Id ruleA = RecurringService.createRule(adminA, new Map<String, Object>{
            'name' => 'A rule', 'type' => 'Expense', 'amount' => 100, 'accountId' => savingsA, 'categoryId' => LedgerTestData.categoryId(adminA, 'Rent'),
            'nextRunDate' => String.valueOf(Date.today().addDays(3))
        }).id;
        NotificationService.notify(adminA.familyId, new Set<Id>{ adminA.userId }, new NotificationService.Message('T', 'info', 'A only', null, null, null));
        Id noteA = [SELECT Id FROM Notification__c WITH SYSTEM_MODE].Id;

        UserContext adminB = VkfTestData.ctx('adminb');
        Test.startTest();
        List<String> attempts = new List<String>{ 'editBill', 'payBill', 'skipBill', 'schedule', 'payEmi', 'prepay', 'editLoan', 'editRule', 'postRule', 'statements' };
        for (String attempt : attempts) {
            try {
                if (attempt == 'editBill') {
                    BillService.updateBill(adminB, billA, new Map<String, Object>{ 'name' => 'mine' });
                } else if (attempt == 'payBill') {
                    BillService.payInstance(adminB, instanceA, new Map<String, Object>());
                } else if (attempt == 'skipBill') {
                    BillService.skipInstance(adminB, instanceA);
                } else if (attempt == 'schedule') {
                    LoanService.schedule(adminB, loanA);
                } else if (attempt == 'payEmi') {
                    LoanService.payEmi(adminB, loanA, new Map<String, Object>());
                } else if (attempt == 'prepay') {
                    LoanService.prepay(adminB, loanA, new Map<String, Object>{ 'amount' => 1 });
                } else if (attempt == 'editLoan') {
                    LoanService.updateLoan(adminB, loanA, new Map<String, Object>{ 'name' => 'mine' });
                } else if (attempt == 'editRule') {
                    RecurringService.updateRule(adminB, ruleA, new Map<String, Object>{ 'amount' => 1 });
                } else if (attempt == 'postRule') {
                    RecurringService.postNow(adminB, ruleA, false);
                } else if (attempt == 'statements') {
                    CardStatementService.listStatements(adminB, savingsA);
                }
                Assert.fail(attempt + ' reached Family A');
            } catch (PortalException e) {
                Assert.areEqual('NOT_FOUND', e.code(), attempt);
            }
        }
        Assert.areEqual(0, BillService.listBills(adminB).bills.size());
        Assert.areEqual(0, LoanService.listLoans(adminB).size());
        Assert.areEqual(0, RecurringService.listRules(adminB).size());
        Assert.areEqual(0, DuesService.upcoming(adminB, 30).size());
        Assert.areEqual(0, NotificationService.markRead(adminB, new List<Id>{ noteA }));
        Test.stopTest();
        Assert.isFalse([SELECT Is_Read__c FROM Notification__c WHERE Id = :noteA WITH SYSTEM_MODE].Is_Read__c);
        Assert.areEqual('A bill', [SELECT Name FROM Bill__c WHERE Id = :billA WITH SYSTEM_MODE].Name);
    }
}