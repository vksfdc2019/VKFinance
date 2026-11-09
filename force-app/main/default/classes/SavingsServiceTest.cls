/** Savings schemes, insurance policies and the per-person tax-saving picture, against Indian rules. */
@IsTest
private class SavingsServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    static SavingsDtos.Scheme open(UserContext ctx, Map<String, Object> body) {
        return SavingsService.create(ctx, body);
    }

    static SavingsDtos.TaxSummary mine(UserContext ctx) {
        SavingsDtos.Portfolio p = SavingsService.portfolio(ctx);
        Assert.isFalse(p.taxes.isEmpty(), 'a tax summary for the caller');
        Assert.areEqual(ctx.userId, p.taxes[0].ownerId, 'the caller comes first');
        return p.taxes[0];
    }

    @IsTest
    static void ppfFollowsTheFinancialYearRules() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        SavingsDtos.Scheme ppf = open(admin, new Map<String, Object>{
            'scheme' => 'PPF', 'name' => 'PPF - SBI', 'institution' => 'SBI', 'startDate' => '2020-06-15', 'balance' => 300000,
            'plannedContribution' => 100000, 'accountNumber' => '32991147788'
        });
        Assert.areEqual(Date.newInstance(2036, 4, 1), ppf.maturityDate, '15 full financial years after FY 2020-21');
        Assert.areEqual(7.1, ppf.rate, 'the notified rate by default');
        Assert.areEqual(300000, ppf.balance);
        Assert.areEqual('•••• 7788', ppf.accountNumberMasked);
        Assert.isTrue(ppf.depositsOpen);
        Assert.areEqual(150000, ppf.roomThisYear);
        Assert.isTrue(ppf.maturityValue > 300000, 'grows with interest and deposits');
        Assert.isTrue(ppf.canDelete, 'nothing recorded yet');

        Test.startTest();
        SavingsDtos.Scheme after = SavingsService.contribute(admin, ppf.id, new Map<String, Object>{ 'fromAccountId' => savings, 'amount' => 100000 });
        Test.stopTest();
        Assert.areEqual(400000, after.balance);
        Assert.areEqual(100000, after.contributedThisYear);
        Assert.areEqual(50000, after.roomThisYear);
        Assert.areEqual(400000, LedgerTestData.balance(after.accountId), 'a ledger transfer');
        Assert.areEqual(400000, LedgerTestData.balance(savings));
        try {
            SavingsService.contribute(admin, ppf.id, new Map<String, Object>{ 'fromAccountId' => savings, 'amount' => 60000 });
            Assert.fail('Rs 1.5 lakh a year at most');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        SavingsDtos.TaxSummary tax = mine(admin);
        Assert.areEqual(100000, tax.section80C, 'this year\'s PPF deposit counts for 80C');
        try {
            SavingsService.deleteScheme(admin, ppf.id);
            Assert.fail('deposits are recorded');
        } catch (PortalException e) {
            Assert.areEqual('CONFLICT', e.code());
        }
    }

    @IsTest
    static void lumpSumAndIncomeSchemes() {
        UserContext admin = VkfTestData.ctx('admina');
        Date today = Date.today();
        SavingsDtos.Scheme nsc = open(admin, new Map<String, Object>{ 'scheme' => 'NSC', 'startDate' => String.valueOf(today), 'principal' => 50000 });
        Assert.areEqual(today.addMonths(60), nsc.maturityDate);
        Assert.areEqual(Decimal.valueOf(50000 * Math.pow((Double) 1.077, (Double) 5)).setScale(2, RoundingMode.HALF_UP), nsc.maturityValue, 'compounds yearly');
        Assert.isFalse(nsc.depositsOpen, 'one deposit only');
        Assert.areEqual('80C', nsc.taxSection);

        SavingsDtos.Scheme kvp = open(admin, new Map<String, Object>{ 'scheme' => 'KVP', 'startDate' => String.valueOf(today), 'principal' => 100000 });
        Assert.areEqual(today.addMonths(115), kvp.maturityDate);
        Assert.isTrue(Math.abs(kvp.maturityValue - 200000) < 500, 'KVP doubles in 115 months: ' + kvp.maturityValue);
        Assert.isNull(kvp.taxSection);

        SavingsDtos.Scheme scss = open(admin, new Map<String, Object>{ 'scheme' => 'SCSS', 'startDate' => String.valueOf(today), 'principal' => 1000000 });
        Assert.areEqual(20500, scss.payoutAmount, '8.2% paid every quarter');
        Assert.areEqual(1000000, scss.maturityValue, 'the deposit comes back');
        SavingsDtos.Scheme pomis = open(admin, new Map<String, Object>{ 'scheme' => 'POMIS', 'startDate' => String.valueOf(today), 'principal' => 900000 });
        Assert.areEqual(5550, pomis.payoutAmount, '7.4% paid monthly');

        Map<String, Object> tooMuch = new Map<String, Object>{ 'scheme' => 'POMIS', 'startDate' => String.valueOf(today), 'principal' => 1000000 };
        Map<String, Object> badTd = new Map<String, Object>{ 'scheme' => 'PO_TD', 'startDate' => String.valueOf(today), 'principal' => 10000, 'tenureMonths' => 18 };
        Map<String, Object> noRd = new Map<String, Object>{ 'scheme' => 'PO_RD', 'startDate' => String.valueOf(today) };
        Map<String, Object> unknown = new Map<String, Object>{ 'scheme' => 'CHIT', 'startDate' => String.valueOf(today) };
        for (Map<String, Object> bad : new List<Map<String, Object>>{ tooMuch, badTd, noRd, unknown }) {
            try {
                open(admin, bad);
                Assert.fail('expected a validation error: ' + JSON.serialize(bad));
            } catch (PortalException e) {
                Assert.areEqual('VALIDATION', e.code(), JSON.serialize(bad));
            }
        }
        SavingsDtos.Scheme rd = open(admin, new Map<String, Object>{ 'scheme' => 'PO_RD', 'startDate' => String.valueOf(today), 'plannedContribution' => 1000, 'balance' => 0 });
        Assert.areEqual(DepositCalculator.rdMaturity(1000, 6.7, 60, today), rd.maturityValue);

        SavingsDtos.TaxSummary tax = mine(admin);
        Assert.areEqual(50000 + 1000000, tax.section80C, 'NSC and SCSS bought this year (KVP and POMIS give no deduction)');
        Assert.isTrue(tax.section80C > tax.limit80C, 'the page shows the Rs 1.5 lakh cap');
    }

    @IsTest
    static void npsGetsItsOwnFiftyThousandAndValuations() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 200000).id;
        SavingsDtos.Scheme nps = open(admin, new Map<String, Object>{
            'scheme' => 'NPS', 'startDate' => '2018-04-10', 'balance' => 400000, 'maturityDate' => '2045-07-01'
        });
        Assert.areEqual(Date.newInstance(2045, 7, 1), nps.maturityDate, 'NPS runs to 60: the holder sets the date');
        Assert.isNotNull(nps.valueAsOf);
        Test.startTest();
        SavingsService.contribute(admin, nps.id, new Map<String, Object>{ 'fromAccountId' => savings, 'amount' => 60000 });
        SavingsDtos.Scheme valued = SavingsService.updateValue(admin, nps.id, new Map<String, Object>{ 'value' => 512345 });
        Test.stopTest();
        Assert.areEqual(512345, valued.balance, 'market value');
        SavingsDtos.TaxSummary tax = mine(admin);
        Assert.areEqual(50000, tax.section80CCD1B);
        Assert.areEqual(10000, tax.section80C, 'the rest counts under 80C');
    }

    @IsTest
    static void lifeAndHealthPoliciesKeepTheirPremiumsAsBills() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 200000).id;
        SavingsDtos.Policy lic = InsuranceService.save(admin, null, new Map<String, Object>{
            'insurer' => 'LIC of India', 'planName' => 'Jeevan Anand', 'policyType' => 'Endowment', 'policyNumber' => '781234567',
            'sumAssured' => 200000, 'premium' => 25000, 'frequency' => 'Yearly', 'startDate' => '2019-03-28',
            'nextDueDate' => String.valueOf(Date.today()), 'policyTermYears' => 21, 'premiumTermYears' => 21, 'payFromAccountId' => savings,
            'nominee' => 'Spouse'
        });
        Assert.areEqual('80C', lic.taxSection, 'life cover defaults to 80C');
        Assert.areEqual(Date.newInstance(2040, 3, 28), lic.maturityDate);
        Assert.areEqual(30, lic.graceDays, 'IRDAI: 30 days for yearly premiums');
        Assert.areEqual(1, lic.taxWarnings.size(), 'premium is over 10% of the sum assured');
        Assert.isNotNull(lic.billId, 'the premium is a bill');
        Assert.areEqual('Due', lic.premiumState);
        Bill__c bill = [SELECT Name, Frequency__c, Expected_Amount__c, Pay_From_Account__c FROM Bill__c WHERE Id = :lic.billId];
        Assert.areEqual('Yearly', bill.Frequency__c);
        Assert.areEqual(25000, bill.Expected_Amount__c);

        SavingsDtos.Policy health = InsuranceService.save(admin, null, new Map<String, Object>{
            'insurer' => 'Star Health', 'policyType' => 'Health', 'sumAssured' => 1000000, 'premium' => 1500, 'frequency' => 'Monthly',
            'nextDueDate' => String.valueOf(Date.today()), 'payFromAccountId' => savings
        });
        Assert.areEqual('80D', health.taxSection);
        Assert.areEqual(15, health.graceDays, 'IRDAI: 15 days for monthly premiums');
        Assert.areEqual(18000, health.yearlyPremium);

        Test.startTest();
        BillService.payInstance(admin, lic.openInstanceId, new Map<String, Object>());
        BillService.payInstance(admin, health.openInstanceId, new Map<String, Object>());
        Test.stopTest();
        SavingsDtos.Portfolio p = SavingsService.portfolio(admin);
        Assert.areEqual(200000, p.lifeCover);
        Assert.areEqual(1000000, p.healthCover);
        SavingsDtos.TaxSummary tax = p.taxes[0];
        Assert.areEqual(20000, tax.section80C, 'only 10% of the sum assured counts');
        Assert.areEqual(1500, tax.section80D);

        SavingsDtos.Policy paidUp = InsuranceService.save(admin, lic.id, new Map<String, Object>{ 'status' => 'Paid-up' });
        Assert.areEqual('None', paidUp.premiumState);
        Assert.isFalse([SELECT Active__c FROM Bill__c WHERE Id = :lic.billId].Active__c, 'premiums stop');

        Assert.areEqual(0, InsuranceService.policies(VkfTestData.ctx('membera')).size(), 'members see their own policies');
        try {
            InsuranceService.save(admin, null, new Map<String, Object>{ 'insurer' => 'X', 'policyType' => 'Chit', 'frequency' => 'Yearly', 'premium' => 1 });
            Assert.fail('unknown type');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        InsuranceService.deletePolicy(admin, health.id);
        Assert.areEqual(0, [SELECT COUNT() FROM Bill__c WHERE Id = :health.billId], 'its bill goes too');
    }

    @IsTest
    static void closingAndDeleting() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 0).id;
        SavingsDtos.Scheme mistake = open(admin, new Map<String, Object>{ 'scheme' => 'NSC', 'startDate' => String.valueOf(Date.today()), 'principal' => 5000 });
        SavingsService.deleteScheme(admin, mistake.id);
        Assert.areEqual(0, [SELECT COUNT() FROM Financial_Account__c WHERE Id = :mistake.accountId], 'its account goes too');

        SavingsDtos.Scheme kvp = open(admin, new Map<String, Object>{ 'scheme' => 'KVP', 'startDate' => '2016-01-01', 'principal' => 50000, 'balance' => 100000 });
        Test.startTest();
        SavingsDtos.Scheme closed = SavingsService.close(admin, kvp.id, new Map<String, Object>{ 'toAccountId' => savings });
        Test.stopTest();
        Assert.areEqual('Matured', closed.status);
        Assert.areEqual(100000, LedgerTestData.balance(savings), 'the proceeds land in the bank');
        Assert.areEqual('Closed', [SELECT Status__c FROM Financial_Account__c WHERE Id = :kvp.accountId].Status__c);
        Assert.areEqual(0, SavingsService.portfolio(VkfTestData.ctx('adminb')).schemes.size(), 'nothing crosses families');
    }

    @IsTest
    static void servedOverRest() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 10000).id;
        String token = VkfTestData.login('admina');
        RestResponse res = VkfTestData.call('GET', '/vkf/v1/savings', null, token);
        VkfSavingsResource.get();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('POST', '/vkf/v1/savings/schemes', '{"scheme":"SSY","startDate":"2024-05-01","balance":50000,"beneficiary":"Ananya"}', token);
        VkfSavingsResource.post();
        Assert.areEqual(201, res.statusCode, res.responseBody.toString());
        Map<String, Object> ssy = VkfTestData.json(res);
        Assert.areEqual('2045-05-01', ssy.get('maturityDate'), 'SSY matures 21 years after opening');
        res = VkfTestData.call('PATCH', '/vkf/v1/savings/schemes/' + ssy.get('id'), '{"plannedContribution":150000,"name":"Ananya SSY"}', token);
        VkfSavingsResource.patch();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        Assert.areEqual('Ananya SSY', VkfTestData.json(res).get('name'));
        Test.startTest();
        for (String action : new List<String>{
            'contribute:{"fromAccountId":"' + savings + '","amount":1000}', 'interest:{"amount":350}', 'value:{"value":52000}', 'close:{"toAccountId":"' + savings + '"}'
        }) {
            res = VkfTestData.call('POST', '/vkf/v1/savings/schemes/' + ssy.get('id') + '/' + action.substringBefore(':'), action.substringAfter(':'), token);
            VkfSavingsResource.post();
            Assert.areEqual(200, res.statusCode, action + ' ' + res.responseBody.toString());
        }
        Test.stopTest();
        res = VkfTestData.call('POST', '/vkf/v1/savings/policies', '{"insurer":"HDFC Life","policyType":"Term","sumAssured":10000000,"premium":14000,"frequency":"Yearly"}', token);
        VkfSavingsResource.post();
        Assert.areEqual(201, res.statusCode, res.responseBody.toString());
        String policyId = (String) VkfTestData.json(res).get('id');
        res = VkfTestData.call('PATCH', '/vkf/v1/savings/policies/' + policyId, '{"nominee":"Spouse"}', token);
        VkfSavingsResource.patch();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        res = VkfTestData.call('DELETE', '/vkf/v1/savings/policies/' + policyId, null, token);
        VkfSavingsResource.remove();
        Assert.areEqual(204, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/savings/schemes/' + ssy.get('id') + '/nope', '{}', token);
        VkfSavingsResource.post();
        Assert.areEqual(404, res.statusCode);
    }
}
