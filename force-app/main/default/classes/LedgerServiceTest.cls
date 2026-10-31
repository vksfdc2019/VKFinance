@IsTest
private class LedgerServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void entriesMoveBalancesAndVoidRestoresThem() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'HDFC Savings', 'Savings', 10000).id;
        Id groceries = LedgerTestData.categoryId(admin, 'Groceries');
        Id salary = LedgerTestData.categoryId(admin, 'Salary');

        FinanceDtos.Txn spend = LedgerTestData.entry(admin, 'Expense', 2500, savings, groceries);
        Assert.areEqual(7500, LedgerTestData.balance(savings));
        Assert.areEqual('Debit', spend.direction);
        Assert.areEqual('Food and Dining', spend.parentCategoryName);
        Assert.areEqual('utensils-crossed', spend.icon, 'sub-categories inherit the parent icon');
        FinanceDtos.Txn pay = LedgerTestData.entry(admin, 'Income', 1000, savings, salary);
        LedgerTestData.entry(admin, 'Refund', 500, savings, groceries);
        Assert.areEqual(9000, LedgerTestData.balance(savings));

        TransactionService.updateTransaction(admin, spend.id, new Map<String, Object>{ 'amount' => 2000, 'payee' => 'Big Bazaar' });
        Assert.areEqual(9500, LedgerTestData.balance(savings));
        TransactionService.voidTransaction(admin, pay.id);
        Assert.areEqual(8500, LedgerTestData.balance(savings));
        try {
            TransactionService.voidTransaction(admin, pay.id);
            Assert.fail('voiding twice should fail');
        } catch (PortalException e) {
            Assert.areEqual('CONFLICT', e.code());
        }

        // The incremental balance always matches a full rebuild from the ledger.
        LedgerBalances.recalculate(new Set<Id>{ savings });
        Assert.areEqual(8500, LedgerTestData.balance(savings));
    }

    @IsTest
    static void cardSpendAndPaymentAreCountedOnce() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 20000).id;
        Id card = LedgerTestData.account(admin, 'Visa', 'Credit Card', 0).id;
        LedgerTestData.entry(admin, 'Expense', 3000, card, LedgerTestData.categoryId(admin, 'Restaurants and Takeaway'));
        Assert.areEqual(3000, LedgerTestData.balance(card), 'spending on a card raises what is owed');

        FinanceDtos.Transfer payment = LedgerTestData.transfer(admin, savings, card, 2000);
        Assert.areEqual('Card Payment', payment.outLeg.type);
        Assert.areEqual('Credit Card Payment', payment.inLeg.categoryName);
        Assert.areEqual(18000, LedgerTestData.balance(savings));
        Assert.areEqual(1000, LedgerTestData.balance(card));
        Transaction__c outLeg = [SELECT Counter_Transaction__c FROM Transaction__c WHERE Id = :payment.outLeg.id WITH SYSTEM_MODE];
        Assert.areEqual(payment.inLeg.id, outLeg.Counter_Transaction__c);

        FinanceDtos.Account cardView = AccountService.listAccounts(admin, false)[1];
        Assert.areEqual('Visa', cardView.name);
        Assert.areEqual(2.0, cardView.card.utilisationPct);
        Assert.areEqual(49000, cardView.card.available);
        Assert.isNull(cardView.card.statement, 'no bill until the statement is written');

        Map<String, String> params = LedgerTestData.params('month=' + LedgerUtil.monthKey(Date.today()));
        FinanceDtos.TxnPage page = TransactionService.listTransactions(admin, params);
        Assert.areEqual(3000, page.totals.expenses, 'the card payment is not spending');
        Assert.areEqual(2000, page.totals.transfers, 'both legs count once');

        TransactionService.updateTransaction(admin, payment.inLeg.id, new Map<String, Object>{ 'amount' => 3000, 'notes' => 'Full bill' });
        Assert.areEqual(0, LedgerTestData.balance(card));
        Assert.areEqual(17000, LedgerTestData.balance(savings));
        TransactionService.voidTransaction(admin, payment.outLeg.id);
        Assert.areEqual(3000, LedgerTestData.balance(card));
        Assert.areEqual(20000, LedgerTestData.balance(savings));
        Assert.areEqual(2, [SELECT COUNT() FROM Transaction__c WHERE Transfer_Group_Id__c = :payment.groupId AND Status__c = 'Void' WITH SYSTEM_MODE]);
    }

    @IsTest
    static void pocketMoneyReachesTheChildsAccount() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id childId = VkfTestData.userId('childa');
        FinanceDtos.Account wallet = AccountService.createAccount(
            admin,
            new Map<String, Object>{ 'name' => 'Riya Wallet', 'type' => 'Cash', 'ownerId' => childId }
        );
        UserContext member = VkfTestData.ctx('membera');
        Id memberSavings = LedgerTestData.account(member, 'My Savings', 'Savings', 5000).id;
        Assert.areEqual(VkfTestData.userId('membera'), [SELECT Owner_Member__c FROM Financial_Account__c WHERE Id = :memberSavings WITH SYSTEM_MODE].Owner_Member__c);

        Test.startTest();
        Boolean targetListed = false;
        for (FinanceDtos.AccountRef target : AccountService.transferTargets(member)) {
            targetListed = targetListed || target.id == wallet.id;
        }
        Assert.isTrue(targetListed, 'other members\' accounts are offered as transfer targets');
        FinanceDtos.Transfer pocketMoney = LedgerTestData.transfer(member, memberSavings, wallet.id, 500);
        Assert.areEqual(childId, pocketMoney.inLeg.memberId, 'the receiving leg belongs to the account owner');
        Assert.areEqual(500, LedgerTestData.balance(wallet.id));

        UserContext child = VkfTestData.ctx('childa');
        FinanceDtos.TxnPage childView = TransactionService.listTransactions(child, new Map<String, String>());
        Assert.areEqual(1, childView.items.size());
        Assert.areEqual('Transfer In', childView.items[0].type);
        Assert.areEqual('My Savings', childView.items[0].counterAccountName);
        try {
            TransactionService.getTransaction(child, pocketMoney.outLeg.id);
            Assert.fail('the child cannot see the sender\'s leg');
        } catch (PortalException e) {
            Assert.areEqual('NOT_FOUND', e.code());
        }
        Test.stopTest();
    }

    @IsTest
    static void validationMessages() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 100).id;
        Id card = LedgerTestData.account(admin, 'Card', 'Credit Card', 0).id;
        Id groceries = LedgerTestData.categoryId(admin, 'Groceries');
        Id salary = LedgerTestData.categoryId(admin, 'Salary');

        expectError('VALIDATION', admin, 'Expense', 0, savings, groceries);
        expectError('VALIDATION', admin, 'Expense', 10, savings, null);
        expectError('VALIDATION', admin, 'Income', 10, card, salary);
        expectError('VALIDATION', admin, 'Expense', 10, savings, salary);
        expectError('VALIDATION', admin, 'Transfer Out', 10, savings, groceries);
        expectError('VALIDATION', admin, 'Expense', 10, null, groceries);

        for (Map<String, Object> body : new List<Map<String, Object>>{
            new Map<String, Object>{ 'fromAccountId' => savings, 'toAccountId' => savings, 'amount' => 5, 'date' => String.valueOf(Date.today()) },
            new Map<String, Object>{ 'fromAccountId' => card, 'toAccountId' => savings, 'amount' => 5, 'date' => String.valueOf(Date.today()) },
            new Map<String, Object>{ 'fromAccountId' => savings, 'amount' => 5, 'date' => String.valueOf(Date.today()) },
            new Map<String, Object>{ 'fromAccountId' => savings, 'toAccountId' => card, 'amount' => 5, 'date' => '1999-12-31' }
        }) {
            try {
                TransferService.createTransfer(admin, body);
                Assert.fail('expected a validation error for ' + body);
            } catch (PortalException e) {
                Assert.areEqual('VALIDATION', e.code());
            }
        }

        AccountService.updateAccount(admin, savings, new Map<String, Object>{ 'openingBalance' => 0, 'status' => 'Closed' });
        expectError('VALIDATION', admin, 'Expense', 10, savings, groceries);
        try {
            AccountService.createAccount(admin, new Map<String, Object>{ 'name' => 'Bad', 'type' => 'Credit Card', 'last4' => '12345' });
            Assert.fail('card without limit and with a bad last-4 should fail');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
            Assert.isTrue(e.errors.size() >= 2, String.valueOf(e.errors));
        }
    }

    @IsTest
    static void membersSeeOwnAndSharedAccountsOnly() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id privateAcct = LedgerTestData.account(admin, 'Admin Private', 'Savings', 1000).id;
        Id shared = AccountService.createAccount(
            admin,
            new Map<String, Object>{ 'name' => 'Household', 'type' => 'Current', 'isShared' => true, 'openingBalance' => 5000 }
        ).id;
        Id groceries = LedgerTestData.categoryId(admin, 'Groceries');
        FinanceDtos.Txn adminPrivate = LedgerTestData.entry(admin, 'Expense', 100, privateAcct, groceries);
        FinanceDtos.Txn adminShared = LedgerTestData.entry(admin, 'Expense', 200, shared, groceries);

        UserContext member = VkfTestData.ctx('membera');
        Test.startTest();
        List<FinanceDtos.Account> visible = AccountService.listAccounts(member, false);
        Assert.areEqual(1, visible.size());
        Assert.areEqual('Household', visible[0].name);
        Assert.isFalse(visible[0].canManage);
        Assert.isTrue(visible[0].canUse);

        expectError('NOT_FOUND', member, 'Expense', 10, privateAcct, groceries);
        FinanceDtos.Txn own = LedgerTestData.entry(member, 'Expense', 300, shared, groceries);
        Assert.isTrue(own.canEdit);
        FinanceDtos.TxnPage page = TransactionService.listTransactions(member, new Map<String, String>());
        Set<Id> seen = new Set<Id>();
        for (FinanceDtos.Txn t : page.items) {
            seen.add(t.id);
        }
        Assert.isTrue(seen.contains(adminShared.id), 'shared-account activity is visible');
        Assert.isFalse(seen.contains(adminPrivate.id), 'private-account activity is not');
        try {
            TransactionService.updateTransaction(member, adminShared.id, new Map<String, Object>{ 'amount' => 1 });
            Assert.fail('members cannot edit other people\'s entries');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        try {
            AccountService.updateAccount(member, shared, new Map<String, Object>{ 'name' => 'Mine now' });
            Assert.fail('members cannot change accounts they do not own');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        try {
            TransactionService.listTransactions(member, LedgerTestData.params('memberId=' + VkfTestData.userId('admina')));
            Assert.fail('members cannot filter by member');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        Test.stopTest();
    }

    @IsTest
    static void childrenEditForADayAndViewersOnlyRead() {
        VkfTestData.fastPolicy();
        Id familyA = [SELECT Family__c FROM Portal_User__c WHERE Username__c = 'admina' WITH SYSTEM_MODE].Family__c;
        Portal_User__c viewer = VkfTestData.member(familyA, 'viewera', 'Viewer');
        update as system new Portal_User__c(Id = viewer.Id, Viewer_Scope__c = 'Family');
        UserContext admin = VkfTestData.ctx('admina');
        Id wallet = AccountService.createAccount(
            admin,
            new Map<String, Object>{ 'name' => 'Kid Wallet', 'type' => 'Cash', 'ownerId' => VkfTestData.userId('childa'), 'openingBalance' => 500 }
        ).id;

        UserContext child = VkfTestData.ctx('childa');
        Id snacks = LedgerTestData.categoryId(child, 'Snacks and Beverages');
        FinanceDtos.Txn t = LedgerTestData.entry(child, 'Expense', 40, wallet, snacks);
        Assert.isTrue(t.canEdit);
        TransactionService.updateTransaction(child, t.id, new Map<String, Object>{ 'amount' => 45 });
        Assert.areEqual(455, LedgerTestData.balance(wallet));
        try {
            TransactionService.voidTransaction(child, t.id);
            Assert.fail('children cannot void');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        try {
            LedgerTestData.account(child, 'Secret', 'Cash', 0);
            Assert.fail('children cannot add accounts');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        // setCreatedDate must run before startTest, which then gives the rest of the test fresh limits.
        Test.setCreatedDate(t.id, Datetime.now().addDays(-2));
        Test.startTest();
        try {
            TransactionService.updateTransaction(child, t.id, new Map<String, Object>{ 'amount' => 50 });
            Assert.fail('the 24-hour window has passed');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
            Assert.isTrue(e.errors[0].contains('24 hours'));
        }

        UserContext viewerCtx = VkfTestData.ctx('viewera');
        Assert.areEqual(1, TransactionService.listTransactions(viewerCtx, new Map<String, String>()).items.size());
        Assert.isFalse(TransactionService.getTransaction(viewerCtx, t.id).canEdit);
        expectError('NOT_AUTHORIZED', viewerCtx, 'Expense', 10, wallet, snacks);
        Test.stopTest();
    }

    @IsTest
    static void accountSettingsReconcileAndClose() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 1000).id;
        Id card = LedgerTestData.account(admin, 'Card', 'Credit Card', 0).id;
        LedgerTestData.entry(admin, 'Expense', 400, card, LedgerTestData.categoryId(admin, 'Fuel'));

        FinanceDtos.Account updated = AccountService.updateAccount(
            admin,
            savings,
            new Map<String, Object>{ 'name' => 'SBI Savings', 'institution' => 'SBI', 'last4' => '4321', 'color' => 'indigo', 'openingBalance' => 1500 }
        );
        Assert.areEqual('SBI Savings', updated.name);
        Assert.areEqual(1500, updated.balance, 'changing the opening balance moves the balance');

        FinanceDtos.Account reconciled = AccountService.reconcile(admin, savings, new Map<String, Object>{ 'actualBalance' => 1450.75 });
        Assert.areEqual(1450.75, reconciled.balance);
        Transaction__c adj = [SELECT Type__c, Direction__c, Amount__c FROM Transaction__c WHERE Account__c = :savings WITH SYSTEM_MODE];
        Assert.areEqual('Adjustment', adj.Type__c);
        Assert.areEqual('Debit', adj.Direction__c);
        Assert.areEqual(49.25, adj.Amount__c);
        Assert.areEqual(500, AccountService.reconcile(admin, card, new Map<String, Object>{ 'actualBalance' => 500 }).balance);

        try {
            AccountService.updateAccount(admin, card, new Map<String, Object>{ 'type' => 'Savings' });
            Assert.fail('a card with history cannot become a savings account');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        try {
            AccountService.updateAccount(admin, savings, new Map<String, Object>{ 'status' => 'Closed' });
            Assert.fail('cannot close with money in it');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        AccountService.reconcile(admin, savings, new Map<String, Object>{ 'actualBalance' => 0 });
        Assert.areEqual('Closed', AccountService.updateAccount(admin, savings, new Map<String, Object>{ 'status' => 'Closed' }).status);
        Assert.areEqual(1, AccountService.listAccounts(admin, false).size());
        Assert.areEqual(2, AccountService.listAccounts(admin, true).size());
    }

    @IsTest
    static void cardCycleClampsToMonthEnd() {
        Financial_Account__c card = new Financial_Account__c(Type__c = 'Credit Card', Statement_Day__c = 31, Payment_Due_Days__c = 20);
        FinanceDtos.CardCycle c = AccountService.cardCycle(card, Date.newInstance(2026, 2, 10));
        Assert.areEqual(Date.newInstance(2026, 1, 31), c.lastStatementDate);
        Assert.areEqual(Date.newInstance(2026, 2, 28), c.nextStatementDate);
        Assert.areEqual(Date.newInstance(2026, 2, 20), c.dueDate);
        c = AccountService.cardCycle(card, Date.newInstance(2026, 2, 25));
        Assert.areEqual(Date.newInstance(2026, 3, 20), c.dueDate, 'after the due date, show the next one');
    }

    @IsTest
    static void listingFiltersAndPagesWithACursor() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 0).id;
        Id groceries = LedgerTestData.categoryId(admin, 'Groceries');
        Id fuel = LedgerTestData.categoryId(admin, 'Fuel');
        Id salary = LedgerTestData.categoryId(admin, 'Salary');
        Date d = Date.today();
        LedgerTestData.entry(admin, 'Income', 5000, savings, salary, d.addDays(-3), 'Employer');
        LedgerTestData.entry(admin, 'Expense', 100, savings, groceries, d.addDays(-2), 'Corner Store');
        LedgerTestData.entry(admin, 'Expense', 200, savings, fuel, d.addDays(-1), 'Shell 50%_off');
        FinanceDtos.Txn last = LedgerTestData.entry(admin, 'Expense', 300, savings, groceries, d, 'Corner Store');
        TransactionService.voidTransaction(admin, last.id);

        Test.startTest();
        FinanceDtos.TxnPage first = TransactionService.listTransactions(admin, LedgerTestData.params('limit=2'));
        Assert.areEqual(2, first.items.size());
        Assert.areEqual(3, first.totals.count);
        Assert.areEqual(5000, first.totals.income);
        Assert.areEqual(300, first.totals.expenses);
        Assert.isNotNull(first.nextCursor);
        FinanceDtos.TxnPage second = TransactionService.listTransactions(admin, LedgerTestData.params('limit=2&cursor=' + first.nextCursor));
        Assert.areEqual(1, second.items.size());
        Assert.isNull(second.nextCursor);
        Assert.areEqual('Income', second.items[0].type);

        Id foodParent = LedgerTestData.categoryId(admin, 'Food and Dining');
        Assert.areEqual(1, TransactionService.listTransactions(admin, LedgerTestData.params('categoryId=' + foodParent)).items.size());
        Assert.areEqual(2, TransactionService.listTransactions(admin, LedgerTestData.params('categoryId=' + foodParent + '&includeVoid=true')).items.size());
        // Search treats % and _ literally, not as wildcards.
        Assert.areEqual(1, TransactionService.listTransactions(admin, new Map<String, String>{ 'q' => '50%_off' }).items.size());
        Assert.areEqual(0, TransactionService.listTransactions(admin, new Map<String, String>{ 'q' => 'Corner%' }).items.size());
        Assert.areEqual(1, TransactionService.listTransactions(admin, LedgerTestData.params('type=Income&accountId=' + savings)).items.size());
        Assert.areEqual(
            3,
            TransactionService.listTransactions(admin, LedgerTestData.params('memberId=' + VkfTestData.userId('admina') + '&from=' + d.addDays(-7) + '&to=' + d)).items.size()
        );
        try {
            TransactionService.listTransactions(admin, LedgerTestData.params('cursor=nonsense'));
            Assert.fail('bad cursor');
        } catch (PortalException e) {
            Assert.areEqual('BAD_REQUEST', e.code());
        }
        Test.stopTest();
    }

    private static void expectError(String code, UserContext ctx, String type, Decimal amount, Id accountId, Id categoryId) {
        try {
            LedgerTestData.entry(ctx, type, amount, accountId, categoryId);
            Assert.fail('expected ' + code + ' for ' + type + ' ' + amount);
        } catch (PortalException e) {
            Assert.areEqual(code, e.code(), String.valueOf(e.errors));
        }
    }
}