/** Routing and status codes of the bills, loans, recurring and notifications endpoints. */
@IsTest
private class VkfCommitmentResourcesTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void billsAndRecurringEndpoints() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('admina');
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 10000).id;
        Id internet = LedgerTestData.categoryId(admin, 'Internet');

        RestResponse res = VkfTestData.call('POST', '/vkf/v1/bills', '{"name":"Airtel","categoryId":"' + internet + '","nextDueDate":"' + String.valueOf(Date.today().addDays(5)) + '","expectedAmount":999,"payFromAccountId":"' + savings + '"}', token);
        VkfBillsResource.post();
        Assert.areEqual(201, res.statusCode, res.responseBody.toString());
        String billId = (String) VkfTestData.json(res).get('id');
        res = VkfTestData.call('PATCH', '/vkf/v1/bills/' + billId, '{"expectedAmount":1099}', token);
        VkfBillsResource.patch();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('GET', '/vkf/v1/bills', null, token);
        VkfBillsResource.get();
        List<Object> open = (List<Object>) VkfTestData.json(res).get('open');
        String instanceId = (String) ((Map<String, Object>) open[0]).get('id');
        Assert.areEqual(1099, ((Map<String, Object>) open[0]).get('amountDue'));

        Test.startTest();
        res = VkfTestData.call('POST', '/vkf/v1/bills/instances/' + instanceId + '/pay', '{}', token);
        VkfBillsResource.post();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        Assert.areEqual('Paid', VkfTestData.json(res).get('status'));
        res = VkfTestData.call('POST', '/vkf/v1/bills/instances/' + instanceId + '/pay', '{}', token);
        VkfBillsResource.post();
        Assert.areEqual(409, res.statusCode);
        String nextInstance = [SELECT Id FROM Bill_Instance__c WHERE Status__c != 'Paid' WITH SYSTEM_MODE LIMIT 1].Id;
        res = VkfTestData.call('POST', '/vkf/v1/bills/instances/' + nextInstance + '/skip', '{}', token);
        VkfBillsResource.post();
        Assert.areEqual(204, res.statusCode);

        res = VkfTestData.call('POST', '/vkf/v1/recurring', '{"name":"Rent","type":"Expense","amount":100,"accountId":"' + savings + '","categoryId":"' + LedgerTestData.categoryId(admin, 'Rent') + '","nextRunDate":"' + String.valueOf(Date.today()) + '"}', token);
        VkfRecurringResource.post();
        Assert.areEqual(201, res.statusCode, res.responseBody.toString());
        String ruleId = (String) VkfTestData.json(res).get('id');
        res = VkfTestData.call('PATCH', '/vkf/v1/recurring/' + ruleId, '{"amount":150}', token);
        VkfRecurringResource.patch();
        Assert.areEqual(200, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/recurring/' + ruleId + '/post', '{}', token);
        VkfRecurringResource.post();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('GET', '/vkf/v1/recurring', null, token);
        VkfRecurringResource.get();
        Assert.areEqual(200, res.statusCode);
        Test.stopTest();
    }

    @IsTest
    static void loansStatementsAndNotificationsEndpoints() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('admina');
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        Id card = LedgerTestData.account(admin, 'Visa', 'Credit Card', 0).id;

        RestResponse res = VkfTestData.call('POST', '/vkf/v1/loans', '{"name":"Car","loanType":"Car","principal":200000,"annualRate":9,"tenureMonths":24,"firstEmiDate":"' + String.valueOf(Date.today().addDays(5)) + '","debitAccountId":"' + savings + '"}', token);
        VkfLoansResource.post();
        Assert.areEqual(201, res.statusCode, res.responseBody.toString());
        String loanId = (String) VkfTestData.json(res).get('id');

        Test.startTest();
        res = VkfTestData.call('GET', '/vkf/v1/loans/' + loanId + '/schedule', null, token);
        VkfLoansResource.get();
        Assert.areEqual(24, ((List<Object>) VkfTestData.json(res).get('rows')).size());
        res = VkfTestData.call('POST', '/vkf/v1/loans/' + loanId + '/pay', '{}', token);
        VkfLoansResource.post();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('POST', '/vkf/v1/loans/' + loanId + '/prepay', '{"amount":10000}', token);
        VkfLoansResource.post();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('PATCH', '/vkf/v1/loans/' + loanId, '{"autoDebit":true}', token);
        VkfLoansResource.patch();
        Assert.areEqual(true, VkfTestData.json(res).get('autoDebit'));
        res = VkfTestData.call('GET', '/vkf/v1/loans', null, token);
        VkfLoansResource.get();
        Assert.areEqual(200, res.statusCode);

        res = VkfTestData.call('GET', '/vkf/v1/accounts/' + card + '/statements', null, token);
        VkfAccountsResource.get();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());

        NotificationService.notify(admin.familyId, new Set<Id>{ admin.userId }, new NotificationService.Message('T', 'info', 'Hi', null, null, null));
        res = VkfTestData.call('GET', '/vkf/v1/notifications', null, token);
        VkfNotificationsResource.get();
        Assert.areEqual(1, VkfTestData.json(res).get('unread'));
        res = VkfTestData.call('POST', '/vkf/v1/notifications/read', '{"ids":[]}', token);
        VkfNotificationsResource.post();
        Assert.areEqual(1, VkfTestData.json(res).get('marked'));

        for (String path : new List<String>{ '/vkf/v1/bills/x', '/vkf/v1/loans/x/y/z', '/vkf/v1/recurring/x', '/vkf/v1/notifications/x' }) {
            res = VkfTestData.call('GET', path, null, token);
            if (path.contains('bills')) {
                VkfBillsResource.get();
            } else if (path.contains('loans')) {
                VkfLoansResource.get();
            } else if (path.contains('recurring')) {
                VkfRecurringResource.get();
            } else {
                VkfNotificationsResource.get();
            }
            Assert.areEqual(404, res.statusCode, path);
        }
        for (String path : new List<String>{ '/vkf/v1/bills/x/y', '/vkf/v1/loans/x/y', '/vkf/v1/recurring/x/y', '/vkf/v1/notifications/x' }) {
            res = VkfTestData.call('POST', path, '{}', token);
            if (path.contains('bills')) {
                VkfBillsResource.post();
            } else if (path.contains('loans')) {
                VkfLoansResource.post();
            } else if (path.contains('recurring')) {
                VkfRecurringResource.post();
            } else {
                VkfNotificationsResource.post();
            }
            Assert.areEqual(404, res.statusCode, path);
        }
        for (String path : new List<String>{ '/vkf/v1/bills', '/vkf/v1/loans', '/vkf/v1/recurring' }) {
            res = VkfTestData.call('PATCH', path, '{}', token);
            if (path.contains('bills')) {
                VkfBillsResource.patch();
            } else if (path.contains('loans')) {
                VkfLoansResource.patch();
            } else {
                VkfRecurringResource.patch();
            }
            Assert.areEqual(404, res.statusCode, path);
        }
        res = VkfTestData.call('GET', '/vkf/v1/loans', null, null);
        VkfLoansResource.get();
        Assert.areEqual(401, res.statusCode);
        Test.stopTest();
    }
}