/** Routing, status codes and JSON shapes of the ledger REST resources. */
@IsTest
private class VkfLedgerResourcesTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void accountsAndTransactionsEndpoints() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('admina');
        UserContext admin = VkfTestData.ctx('admina');
        Id groceries = LedgerTestData.categoryId(admin, 'Groceries');

        RestResponse res = VkfTestData.call('POST', '/vkf/v1/accounts', '{"name":"Savings","type":"Savings","openingBalance":1000}', token);
        VkfAccountsResource.post();
        Assert.areEqual(201, res.statusCode);
        String savings = (String) VkfTestData.json(res).get('id');
        res = VkfTestData.call('POST', '/vkf/v1/accounts', '{"name":"Card","type":"Credit Card","creditLimit":10000,"statementDay":5}', token);
        VkfAccountsResource.post();
        String card = (String) VkfTestData.json(res).get('id');

        res = VkfTestData.call('GET', '/vkf/v1/accounts', null, token);
        VkfAccountsResource.get();
        Assert.areEqual(200, res.statusCode);
        Assert.areEqual(2, ((List<Object>) JSON.deserializeUntyped(res.responseBody.toString())).size());
        res = VkfTestData.call('GET', '/vkf/v1/accounts/targets', null, token);
        VkfAccountsResource.get();
        Assert.areEqual(200, res.statusCode);
        res = VkfTestData.call('PATCH', '/vkf/v1/accounts/' + savings, '{"color":"rose"}', token);
        VkfAccountsResource.patch();
        Assert.areEqual('rose', VkfTestData.json(res).get('color'));
        res = VkfTestData.call('POST', '/vkf/v1/accounts/' + savings + '/reconcile', '{"actualBalance":1200}', token);
        VkfAccountsResource.post();
        Assert.areEqual(1200, VkfTestData.json(res).get('balance'));

        Test.startTest();
        res = VkfTestData.call(
            'POST',
            '/vkf/v1/transactions',
            '{"type":"Expense","amount":200,"date":"' + Date.today() + '","accountId":"' + savings + '","categoryId":"' + groceries + '"}',
            token
        );
        VkfTransactionsResource.post();
        Assert.areEqual(201, res.statusCode, res.responseBody.toString());
        String txnId = (String) VkfTestData.json(res).get('id');
        res = VkfTestData.call('GET', '/vkf/v1/transactions/' + txnId, null, token);
        VkfTransactionsResource.get();
        Assert.areEqual('Groceries', VkfTestData.json(res).get('categoryName'));
        res = VkfTestData.call('PATCH', '/vkf/v1/transactions/' + txnId, '{"notes":"weekly shop"}', token);
        VkfTransactionsResource.patch();
        Assert.areEqual('weekly shop', VkfTestData.json(res).get('notes'));

        res = VkfTestData.call('POST', '/vkf/v1/transfers', '{"fromAccountId":"' + savings + '","toAccountId":"' + card + '","amount":50,"date":"' + Date.today() + '"}', token);
        VkfTransfersResource.post();
        Assert.areEqual(201, res.statusCode, res.responseBody.toString());

        res = VkfTestData.call('GET', '/vkf/v1/transactions', null, token);
        RestContext.request.addParameter('month', LedgerUtil.monthKey(Date.today()));
        RestContext.request.addParameter('limit', '2');
        VkfTransactionsResource.get();
        Map<String, Object> page = VkfTestData.json(res);
        Assert.areEqual(2, ((List<Object>) page.get('items')).size());
        Assert.isNotNull(page.get('nextCursor'));

        res = VkfTestData.call('DELETE', '/vkf/v1/transactions/' + txnId, null, token);
        VkfTransactionsResource.del();
        Assert.areEqual(204, res.statusCode);
        res = VkfTestData.call('DELETE', '/vkf/v1/transactions/' + txnId, null, token);
        VkfTransactionsResource.del();
        Assert.areEqual(409, res.statusCode);
        Test.stopTest();
    }

    @IsTest
    static void planningEndpoints() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('admina');
        UserContext admin = VkfTestData.ctx('admina');
        Id food = LedgerTestData.categoryId(admin, 'Food and Dining');
        String month = LedgerUtil.monthKey(Date.today());

        RestResponse res = VkfTestData.call('GET', '/vkf/v1/categories', null, token);
        VkfCategoriesResource.get();
        Assert.areEqual(200, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/categories', '{"name":"Chaat","parentId":"' + food + '"}', token);
        VkfCategoriesResource.post();
        Assert.areEqual(201, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('PATCH', '/vkf/v1/categories/' + VkfTestData.json(res).get('id'), '{"name":"Street Food"}', token);
        VkfCategoriesResource.patch();
        Assert.areEqual('Street Food', VkfTestData.json(res).get('name'));

        Test.startTest();
        res = VkfTestData.call('PUT', '/vkf/v1/budgets/' + month, '{"lines":[{"categoryId":"' + food + '","planned":9000}]}', token);
        VkfBudgetsResource.put();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('GET', '/vkf/v1/budgets/' + month, null, token);
        VkfBudgetsResource.get();
        Assert.areEqual(9000, VkfTestData.json(res).get('totalPlanned'));
        res = VkfTestData.call('POST', '/vkf/v1/budgets/' + LedgerUtil.monthKey(Date.today().addMonths(1)) + '/copy-previous', '{}', token);
        VkfBudgetsResource.post();
        Assert.areEqual(200, res.statusCode);
        res = VkfTestData.call('GET', '/vkf/v1/budgets/not-a-month', null, token);
        VkfBudgetsResource.get();
        Assert.areEqual(422, res.statusCode);

        res = VkfTestData.call('GET', '/vkf/v1/dashboard', null, token);
        RestContext.request.addParameter('month', month);
        VkfDashboardResource.get();
        Assert.areEqual(200, res.statusCode);
        Assert.areEqual(month, VkfTestData.json(res).get('month'));
        Test.stopTest();
    }

    @IsTest
    static void unknownPathsAndMissingSessions() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('admina');
        Test.startTest();
        RestResponse res = VkfTestData.call('GET', '/vkf/v1/accounts/x/y', null, token);
        VkfAccountsResource.get();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/accounts/x/y', '{}', token);
        VkfAccountsResource.post();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('PATCH', '/vkf/v1/accounts', '{}', token);
        VkfAccountsResource.patch();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('GET', '/vkf/v1/transactions/a/b', null, token);
        VkfTransactionsResource.get();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/transactions/x', '{}', token);
        VkfTransactionsResource.post();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('PATCH', '/vkf/v1/transactions', '{}', token);
        VkfTransactionsResource.patch();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('DELETE', '/vkf/v1/transactions', null, token);
        VkfTransactionsResource.del();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/transfers/x', '{}', token);
        VkfTransfersResource.post();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('GET', '/vkf/v1/categories/x', null, token);
        VkfCategoriesResource.get();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/categories/x', '{}', token);
        VkfCategoriesResource.post();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('PATCH', '/vkf/v1/categories', '{}', token);
        VkfCategoriesResource.patch();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('GET', '/vkf/v1/budgets/a/b', null, token);
        VkfBudgetsResource.get();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('PUT', '/vkf/v1/budgets', '{}', token);
        VkfBudgetsResource.put();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/budgets/2026-10', '{}', token);
        VkfBudgetsResource.post();
        Assert.areEqual(404, res.statusCode);

        res = VkfTestData.call('GET', '/vkf/v1/dashboard', null, null);
        VkfDashboardResource.get();
        Assert.areEqual(401, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/transfers', '{}', null);
        VkfTransfersResource.post();
        Assert.areEqual(401, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/transactions', 'not json', token);
        VkfTransactionsResource.post();
        Assert.areEqual(400, res.statusCode);
        Test.stopTest();
    }
}
