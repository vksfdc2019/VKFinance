/**
 * Release gate for the ledger: a Family B user aiming at Family A's accounts, transactions,
 * categories, budgets or members always gets NOT_FOUND, and nothing in Family A changes.
 */
@IsTest
private class FinanceIsolationTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void serviceLayerHidesOtherFamilyRecords() {
        VkfTestData.fastPolicy();
        UserContext adminA = VkfTestData.ctx('admina');
        Id accountA = LedgerTestData.account(adminA, 'A Savings', 'Savings', 1000).id;
        Id groceriesA = LedgerTestData.categoryId(adminA, 'Groceries');
        Id foodA = LedgerTestData.categoryId(adminA, 'Food and Dining');
        Id txnA = LedgerTestData.entry(adminA, 'Expense', 100, accountA, groceriesA).id;

        UserContext adminB = VkfTestData.ctx('adminb');
        Id accountB = LedgerTestData.account(adminB, 'B Savings', 'Savings', 1000).id;
        Id groceriesB = LedgerTestData.categoryId(adminB, 'Groceries');

        Test.startTest();
        Integer failures = 0;
        List<String> attempts = new List<String>{
            'readTxn', 'editTxn', 'voidTxn', 'editAccount', 'reconcile', 'transferFrom', 'transferTo', 'postToAccount',
            'useCategory', 'editCategory', 'budgetCategory', 'filterAccount', 'filterCategory', 'dashboardMember'
        };
        for (String attempt : attempts) {
            try {
                if (attempt == 'readTxn') {
                    TransactionService.getTransaction(adminB, txnA);
                } else if (attempt == 'editTxn') {
                    TransactionService.updateTransaction(adminB, txnA, new Map<String, Object>{ 'amount' => 1 });
                } else if (attempt == 'voidTxn') {
                    TransactionService.voidTransaction(adminB, txnA);
                } else if (attempt == 'editAccount') {
                    AccountService.updateAccount(adminB, accountA, new Map<String, Object>{ 'name' => 'Mine' });
                } else if (attempt == 'reconcile') {
                    AccountService.reconcile(adminB, accountA, new Map<String, Object>{ 'actualBalance' => 0 });
                } else if (attempt == 'transferFrom') {
                    LedgerTestData.transfer(adminB, accountA, accountB, 10);
                } else if (attempt == 'transferTo') {
                    LedgerTestData.transfer(adminB, accountB, accountA, 10);
                } else if (attempt == 'postToAccount') {
                    LedgerTestData.entry(adminB, 'Expense', 10, accountA, groceriesB);
                } else if (attempt == 'useCategory') {
                    LedgerTestData.entry(adminB, 'Expense', 10, accountB, groceriesA);
                } else if (attempt == 'editCategory') {
                    CategoryService.updateCategory(adminB, groceriesA, new Map<String, Object>{ 'name' => 'Mine' });
                } else if (attempt == 'budgetCategory') {
                    BudgetService.saveBudget(
                        adminB,
                        null,
                        (Map<String, Object>) JSON.deserializeUntyped('{"lines":[{"categoryId":"' + foodA + '","planned":10}]}')
                    );
                } else if (attempt == 'filterAccount') {
                    TransactionService.listTransactions(adminB, new Map<String, String>{ 'accountId' => accountA });
                } else if (attempt == 'filterCategory') {
                    TransactionService.listTransactions(adminB, new Map<String, String>{ 'categoryId' => groceriesA });
                } else if (attempt == 'dashboardMember') {
                    DashboardService.build(adminB, new Map<String, String>{ 'memberId' => VkfTestData.userId('membera') });
                }
                Assert.fail(attempt + ' should not reach Family A');
            } catch (PortalException e) {
                Assert.areEqual('NOT_FOUND', e.code(), attempt);
                failures++;
            }
        }
        Test.stopTest();
        Assert.areEqual(attempts.size(), failures);

        Financial_Account__c after = [SELECT Name, Current_Balance__c FROM Financial_Account__c WHERE Id = :accountA WITH SYSTEM_MODE];
        Assert.areEqual('A Savings', after.Name);
        Assert.areEqual(900, after.Current_Balance__c);
        Assert.areEqual('Cleared', [SELECT Status__c FROM Transaction__c WHERE Id = :txnA WITH SYSTEM_MODE].Status__c);
        Assert.areEqual('Groceries', [SELECT Name FROM Category__c WHERE Id = :groceriesA WITH SYSTEM_MODE].Name);
    }

    @IsTest
    static void listsAndTargetsNeverIncludeOtherFamilies() {
        VkfTestData.fastPolicy();
        UserContext adminA = VkfTestData.ctx('admina');
        Id accountA = LedgerTestData.account(adminA, 'A Savings', 'Savings', 1000).id;
        LedgerTestData.entry(adminA, 'Expense', 100, accountA, LedgerTestData.categoryId(adminA, 'Groceries'));
        UserContext adminB = VkfTestData.ctx('adminb');

        Test.startTest();
        Assert.areEqual(0, AccountService.listAccounts(adminB, true).size());
        Assert.areEqual(0, AccountService.transferTargets(adminB).size());
        Assert.areEqual(0, TransactionService.listTransactions(adminB, new Map<String, String>()).items.size());
        FinanceDtos.Dashboard d = DashboardService.build(adminB, new Map<String, String>());
        Assert.areEqual(0, d.kpis.expenses);
        Assert.areEqual(0, d.netWorth.assets);
        Assert.areEqual(2, d.members.size());
        Set<Id> categoryIds = new Set<Id>();
        for (FinanceDtos.Category c : CategoryService.listCategories(adminB)) {
            categoryIds.add(c.id);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Category__c WHERE Id IN :categoryIds AND Family__c != :adminB.familyId WITH SYSTEM_MODE]);
        Assert.areEqual(0, BudgetService.getBudget(adminB, null).totalSpent);
        Test.stopTest();
    }

    @IsTest
    static void restLayerHidesOtherFamilyRecords() {
        VkfTestData.fastPolicy();
        UserContext adminA = VkfTestData.ctx('admina');
        Id accountA = LedgerTestData.account(adminA, 'A Savings', 'Savings', 1000).id;
        Id txnA = LedgerTestData.entry(adminA, 'Expense', 100, accountA, LedgerTestData.categoryId(adminA, 'Groceries')).id;
        String tokenB = VkfTestData.login('adminb');

        Test.startTest();
        RestResponse res = VkfTestData.call('GET', '/vkf/v1/transactions/' + txnA, null, tokenB);
        VkfTransactionsResource.get();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('PATCH', '/vkf/v1/transactions/' + txnA, '{"amount":1}', tokenB);
        VkfTransactionsResource.patch();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('DELETE', '/vkf/v1/transactions/' + txnA, null, tokenB);
        VkfTransactionsResource.del();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('PATCH', '/vkf/v1/accounts/' + accountA, '{"name":"Mine"}', tokenB);
        VkfAccountsResource.patch();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/accounts/' + accountA + '/reconcile', '{"actualBalance":0}', tokenB);
        VkfAccountsResource.post();
        Assert.areEqual(404, res.statusCode);
        Test.stopTest();
        Assert.areEqual(900, LedgerTestData.balance(accountA));
    }
}
