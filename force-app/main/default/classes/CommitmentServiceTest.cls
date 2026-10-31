/** Bills, loans and EMIs, card statements, recurring rules and notifications. */
@IsTest
private class CommitmentServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    static Map<String, Object> body(String text) {
        return (Map<String, Object>) JSON.deserializeUntyped(text);
    }

    @IsTest
    static void emiMatchesTheBlueprintExample() {
        Decimal emi = EmiCalculator.emi(1000000, 9, 60);
        Assert.areEqual(20758, emi.setScale(0, RoundingMode.DOWN));
        List<EmiCalculator.Row> rows = EmiCalculator.schedule(1000000, 9, emi, 1, Date.newInstance(2026, 1, 5), 600);
        Assert.areEqual(60, rows.size());
        Assert.areEqual(7500, rows[0].interest);
        Assert.areEqual(0, rows[59].closing);
        Assert.areEqual(Date.newInstance(2026, 2, 5), rows[1].dueDate);
        Assert.areEqual(100, EmiCalculator.emi(1200, 0, 12));
        try {
            EmiCalculator.schedule(100000, 12, 500, 1, Date.today(), 10);
            Assert.fail('an EMI below the interest never repays');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
    }

    @IsTest
    static void billsArePaidRolledForwardAndRevertedOnVoid() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 10000).id;
        Id electricity = LedgerTestData.categoryId(admin, 'Electricity');
        Date due = Date.today().addDays(5);
        CommitmentDtos.Bill bill = BillService.createBill(admin, new Map<String, Object>{
            'name' => 'BESCOM', 'categoryId' => electricity, 'frequency' => 'Monthly', 'nextDueDate' => String.valueOf(due),
            'expectedAmount' => 1500, 'payFromAccountId' => savings, 'reminderDays' => 3
        });
        Assert.areEqual('zap', bill.icon);
        CommitmentDtos.BillsView view = BillService.listBills(admin);
        Assert.areEqual(1, view.open.size());
        Assert.areEqual('Due', view.open[0].status);
        Assert.areEqual(1500, view.dueNext30);
        Id instanceId = view.open[0].id;

        Test.startTest();
        CommitmentDtos.BillInstance part = BillService.payInstance(admin, instanceId, new Map<String, Object>{ 'amount' => 1000 });
        Assert.areEqual('Partially Paid', part.status);
        Assert.areEqual(9000, LedgerTestData.balance(savings));
        CommitmentDtos.BillInstance rest = BillService.payInstance(admin, instanceId, new Map<String, Object>());
        Assert.areEqual('Paid', rest.status);
        Assert.areEqual(8500, LedgerTestData.balance(savings));
        Assert.areEqual(due.addMonths(1), [SELECT Next_Due_Date__c FROM Bill__c WHERE Id = :bill.id WITH SYSTEM_MODE].Next_Due_Date__c);
        Assert.areEqual(1, BillService.listBills(admin).open.size(), 'the next occurrence is ready');

        Transaction__c second = [SELECT Id, Type__c FROM Transaction__c WHERE Bill_Instance__c = :instanceId AND Amount__c = 500 WITH SYSTEM_MODE];
        Assert.areEqual('Bill Payment', second.Type__c);
        try {
            TransactionService.updateTransaction(admin, second.Id, new Map<String, Object>{ 'amount' => 1 });
            Assert.fail('bill payments are not edited directly');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        TransactionService.voidTransaction(admin, second.Id);
        Bill_Instance__c reverted = [SELECT Status__c, Amount_Paid__c FROM Bill_Instance__c WHERE Id = :instanceId WITH SYSTEM_MODE];
        Assert.areEqual('Partially Paid', reverted.Status__c);
        Assert.areEqual(1000, reverted.Amount_Paid__c);
        Assert.areEqual(9000, LedgerTestData.balance(savings));

        Id nextInstance = BillService.listBills(admin).open[1].id;
        BillService.skipInstance(admin, nextInstance);
        Assert.areEqual('Skipped', [SELECT Status__c FROM Bill_Instance__c WHERE Id = :nextInstance WITH SYSTEM_MODE].Status__c);
        Test.stopTest();
    }

    @IsTest
    static void membersSeeAndPayOnlyTheirBills() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id shared = AccountService.createAccount(admin, new Map<String, Object>{ 'name' => 'Household', 'type' => 'Current', 'isShared' => true, 'openingBalance' => 5000 }).id;
        Id internet = LedgerTestData.categoryId(admin, 'Internet');
        Id memberId = VkfTestData.userId('membera');
        BillService.createBill(admin, new Map<String, Object>{
            'name' => 'Airtel', 'categoryId' => internet, 'nextDueDate' => String.valueOf(Date.today().addDays(20)), 'expectedAmount' => 999,
            'payFromAccountId' => shared, 'responsibleId' => memberId
        });
        BillService.createBill(admin, new Map<String, Object>{
            'name' => 'Admin only', 'categoryId' => internet, 'nextDueDate' => String.valueOf(Date.today().addDays(20)), 'expectedAmount' => 10
        });
        UserContext member = VkfTestData.ctx('membera');
        Test.startTest();
        CommitmentDtos.BillsView mine = BillService.listBills(member);
        Assert.areEqual(1, mine.bills.size());
        Assert.isTrue(mine.open[0].canPay);
        Assert.isFalse(mine.canEdit);
        BillService.payInstance(member, mine.open[0].id, new Map<String, Object>());
        Assert.areEqual(4001, LedgerTestData.balance(shared));
        Id adminInstance = [SELECT Id FROM Bill_Instance__c WHERE Bill__r.Name = 'Admin only' WITH SYSTEM_MODE].Id;
        for (Integer attempt = 0; attempt < 2; attempt++) {
            try {
                if (attempt == 0) {
                    BillService.payInstance(member, adminInstance, new Map<String, Object>());
                } else {
                    BillService.createBill(member, new Map<String, Object>{ 'name' => 'x' });
                }
                Assert.fail('expected a refusal');
            } catch (PortalException e) {
                Assert.areEqual(attempt == 0 ? 'NOT_FOUND' : 'NOT_AUTHORIZED', e.code());
            }
        }
        try {
            BillService.listBills(VkfTestData.ctx('childa'));
            Assert.fail('children do not see bills');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        try {
            BillService.createBill(admin, new Map<String, Object>{ 'name' => 'Bad', 'categoryId' => internet, 'nextDueDate' => String.valueOf(Date.today()), 'autoPay' => true });
            Assert.fail('auto-pay needs an account and amount');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        Test.stopTest();
    }

    @IsTest
    static void loansPayEmisPrepayAndRevert() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 200000).id;
        CommitmentDtos.Loan loan = LoanService.createLoan(admin, new Map<String, Object>{
            'name' => 'Car loan', 'lender' => 'HDFC Bank', 'loanType' => 'Car', 'principal' => 100000, 'annualRate' => 12, 'tenureMonths' => 12,
            'firstEmiDate' => String.valueOf(Date.today().addDays(3)), 'debitAccountId' => savings
        });
        Assert.areEqual(100000, loan.outstanding);
        Assert.areEqual(12, loan.installmentsLeft);
        Assert.areEqual(8884.88, loan.emi);
        Assert.areEqual(12, [SELECT COUNT() FROM EMI_Installment__c WHERE Loan__c = :loan.id WITH SYSTEM_MODE]);
        Assert.areEqual(100000, LedgerTestData.balance(loan.loanAccountId));

        Test.startTest();
        CommitmentDtos.Loan afterEmi = LoanService.payEmi(admin, loan.id, new Map<String, Object>());
        Assert.areEqual(1, afterEmi.installmentsPaid);
        Assert.areEqual(200000 - 8884.88, LedgerTestData.balance(savings));
        Assert.areEqual(100000 - (8884.88 - 1000), afterEmi.outstanding, 'principal = EMI - 1% interest');
        Assert.areEqual(1000, [SELECT SUM(Amount__c) s FROM Transaction__c WHERE Type__c = 'Expense' AND Category__r.Name = 'Loan Interest' WITH SYSTEM_MODE][0].get('s'));

        CommitmentDtos.Loan prepaid = LoanService.prepay(admin, loan.id, new Map<String, Object>{ 'amount' => 20000 });
        Assert.isTrue(prepaid.installmentsLeft < 11, 'prepaying shortens the loan');
        CommitmentDtos.Schedule s = LoanService.schedule(admin, loan.id);
        Assert.areEqual('Paid', s.rows[0].status);
        Assert.areEqual(prepaid.installmentsLeft + 1, s.rows.size());

        Id emiLeg = [SELECT Id FROM Transaction__c WHERE EMI_Installment__c != NULL AND Type__c = 'EMI Payment' AND Direction__c = 'Debit' WITH SYSTEM_MODE LIMIT 1].Id;
        TransactionService.voidTransaction(admin, emiLeg);
        CommitmentDtos.Loan reverted = LoanService.listLoans(admin)[0];
        Assert.areEqual(0, reverted.installmentsPaid);
        Assert.areEqual(80000, reverted.outstanding, 'the prepayment stays, the EMI is undone');
        Assert.areEqual(200000 - 20000, LedgerTestData.balance(savings));
        Test.stopTest();
    }

    @IsTest
    static void existingLoansStartPartWayAndValidate() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Decimal emi = EmiCalculator.emi(500000, 8.5, 60);
        CommitmentDtos.Loan loan = LoanService.createLoan(admin, new Map<String, Object>{
            'name' => 'Home top-up', 'loanType' => 'Home', 'principal' => 500000, 'annualRate' => 8.5, 'tenureMonths' => 60,
            'firstEmiDate' => String.valueOf(Date.today().addMonths(-6)), 'installmentsPaid' => 6
        });
        Assert.areEqual(EmiCalculator.outstandingAfter(500000, 8.5, emi, 6), loan.outstanding);
        Assert.areEqual(54, loan.installmentsLeft);
        Assert.areEqual(7, loan.next.no);
        Assert.isTrue(new Set<String>{ 'Due', 'Overdue' }.contains(loan.next.status), 'the 7th EMI falls due about today');
        CommitmentDtos.Loan renamed = LoanService.updateLoan(admin, loan.id, new Map<String, Object>{ 'name' => 'Home loan top-up' });
        Assert.areEqual('Home loan top-up', renamed.name);
        for (String bad : new List<String>{
            '{"name":"x","loanType":"Home","principal":1000,"annualRate":10,"tenureMonths":12,"firstEmiDate":"2026-01-01","installmentsPaid":12}',
            '{"name":"x","loanType":"Boat","principal":1000,"annualRate":10,"tenureMonths":12,"firstEmiDate":"2026-01-01"}',
            '{"name":"x","loanType":"Home","principal":1000,"annualRate":80,"tenureMonths":12,"firstEmiDate":"2026-01-01"}',
            '{"name":"x","loanType":"Home","principal":1000,"annualRate":8,"tenureMonths":12,"firstEmiDate":"2026-01-01","autoDebit":true}'
        }) {
            try {
                LoanService.createLoan(admin, body(bad));
                Assert.fail('expected a validation error: ' + bad);
            } catch (PortalException e) {
                Assert.areEqual('VALIDATION', e.code());
            }
        }
        Assert.areEqual(0, LoanService.listLoans(VkfTestData.ctx('membera')).size(), 'members see only loans they borrowed');
    }

    @IsTest
    static void cardStatementsCloseCyclesAndTrackPayments() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 50000).id;
        Id card = LedgerTestData.account(admin, 'Visa', 'Credit Card', 0).id;
        LedgerTestData.entry(admin, 'Expense', 6000, card, LedgerTestData.categoryId(admin, 'Electronics'), Date.today().addDays(-45), 'Croma');
        Test.startTest();
        List<CommitmentDtos.Statement> statements = CardStatementService.listStatements(admin, card);
        Assert.areEqual(1, statements.size());
        Assert.areEqual(6000, statements[0].amount);
        Assert.areEqual(300, statements[0].minimumDue, '5% of 6,000');
        Assert.areNotEqual('Paid', statements[0].status);
        Assert.areEqual(0, CardStatementService.generate(admin.familyId, Date.today()), 'generating again adds nothing');
        FinanceDtos.Account cardView = AccountService.listAccounts(admin, false)[1];
        Assert.areEqual('Visa', cardView.name);
        Assert.areEqual(statements[0].id, cardView.card.statement.id, 'the card shows its latest statement as the bill');
        Assert.areEqual(6000, cardView.card.statement.amount);
        Assert.areEqual(300, cardView.card.statement.minimumDue);
        Assert.areEqual(0, cardView.card.statement.amountPaid);

        LedgerTestData.transfer(admin, savings, card, 6000);
        statements = CardStatementService.listStatements(admin, card);
        Assert.areEqual('Paid', statements[0].status);
        Assert.areEqual(6000, statements[0].amountPaid);
        cardView = AccountService.listAccounts(admin, false)[1];
        Assert.areEqual('Paid', cardView.card.statement.status, 'paying the card settles its bill');
        Assert.areEqual(6000, cardView.card.statement.amountPaid);
        try {
            CardStatementService.listStatements(admin, savings);
            Assert.fail('only cards have statements');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        Test.stopTest();
    }

    @IsTest
    static void recurringRulesPostSuggestAndSkip() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 100000).id;
        Id mf = LedgerTestData.account(admin, 'Mutual Funds', 'Investment', 0).id;
        Date yesterday = Date.today().addDays(-1);
        CommitmentDtos.Rule rent = RecurringService.createRule(admin, new Map<String, Object>{
            'name' => 'Rent', 'type' => 'Expense', 'amount' => 25000, 'accountId' => savings, 'categoryId' => LedgerTestData.categoryId(admin, 'Rent'),
            'payee' => 'Landlord', 'nextRunDate' => String.valueOf(yesterday), 'mode' => 'Auto-post'
        });
        CommitmentDtos.Rule salary = RecurringService.createRule(admin, new Map<String, Object>{
            'name' => 'Salary', 'type' => 'Income', 'amount' => 90000, 'accountId' => savings, 'categoryId' => LedgerTestData.categoryId(admin, 'Salary'),
            'nextRunDate' => String.valueOf(yesterday), 'mode' => 'Suggest'
        });
        CommitmentDtos.Rule sip = RecurringService.createRule(admin, new Map<String, Object>{
            'name' => 'SIP', 'type' => 'Transfer', 'amount' => 5000, 'accountId' => savings, 'toAccountId' => mf,
            'nextRunDate' => String.valueOf(Date.today().addDays(10)), 'frequency' => 'Monthly'
        });

        Test.startTest();
        Assert.areEqual(1, RecurringService.runDue(admin.familyId, Date.today()));
        Assert.areEqual(75000, LedgerTestData.balance(savings));
        Recurring_Rule__c after = [SELECT Next_Run_Date__c, Last_Run_Date__c FROM Recurring_Rule__c WHERE Id = :rent.id WITH SYSTEM_MODE];
        Assert.areEqual(yesterday.addMonths(1), after.Next_Run_Date__c);
        Assert.areEqual(yesterday, after.Last_Run_Date__c);
        Assert.areEqual('Recurring', [SELECT Source__c FROM Transaction__c WHERE Recurring_Rule__c = :rent.id WITH SYSTEM_MODE].Source__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Notification__c WHERE Type__c = 'RECURRING_CONFIRM' WITH SYSTEM_MODE], 'suggestions ask first');
        RecurringService.runDue(admin.familyId, Date.today());
        Assert.areEqual(1, [SELECT COUNT() FROM Notification__c WHERE Type__c = 'RECURRING_CONFIRM' WITH SYSTEM_MODE], 'and only once');

        RecurringService.postNow(admin, salary.id, false);
        Assert.areEqual(165000, LedgerTestData.balance(savings));
        CommitmentDtos.Rule skipped = RecurringService.postNow(admin, sip.id, true);
        Assert.areEqual(Date.today().addDays(10).addMonths(1), skipped.nextRunDate);
        RecurringService.postNow(admin, sip.id, false);
        Assert.areEqual(5000, LedgerTestData.balance(mf));
        CommitmentDtos.Rule paused = RecurringService.updateRule(admin, sip.id, new Map<String, Object>{ 'active' => false });
        Assert.isFalse(paused.active);
        Assert.areEqual(3, RecurringService.listRules(admin).size());

        UserContext member = VkfTestData.ctx('membera');
        Assert.areEqual(0, RecurringService.listRules(member).size());
        try {
            RecurringService.updateRule(member, rent.id, new Map<String, Object>{ 'amount' => 1 });
            Assert.fail('members cannot change other people\'s rules');
        } catch (PortalException e) {
            Assert.areEqual('NOT_FOUND', e.code());
        }
        Test.stopTest();
    }

    @IsTest
    static void notificationsDedupeReadAndPurge() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        NotificationService.Message m = new NotificationService.Message('TEST', 'info', 'Hello', 'World', '/', 'KEY1');
        Assert.areEqual(1, NotificationService.notify(admin.familyId, new Set<Id>{ admin.userId }, m));
        Assert.areEqual(0, NotificationService.notify(admin.familyId, new Set<Id>{ admin.userId }, m));
        NotificationService.notify(admin.familyId, new Set<Id>{ admin.userId }, new NotificationService.Message('TEST', 'warning', 'Two', null, null, null));
        CommitmentDtos.NotificationFeed feed = NotificationService.feed(admin);
        Assert.areEqual(2, feed.unread);
        Assert.areEqual(1, NotificationService.markRead(admin, new List<Id>{ feed.items[0].id }));
        Assert.areEqual(1, NotificationService.feed(admin).unread);
        Assert.areEqual(1, NotificationService.markRead(admin, new List<Id>()));
        Assert.areEqual(0, NotificationService.feed(VkfTestData.ctx('membera')).items.size(), 'everyone sees only their own');
        for (Notification__c n : [SELECT Id FROM Notification__c WITH SYSTEM_MODE]) {
            Test.setCreatedDate(n.Id, Datetime.now().addDays(-90));
        }
        Assert.areEqual(2, NotificationService.purge());
    }
}