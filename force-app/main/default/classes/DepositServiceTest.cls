/** Fixed and recurring deposits: the maths, the ledger on maturity, renewal and early closure, and the TDS and DICGC checks. */
@IsTest
private class DepositServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    static Id depositAccount(UserContext ctx, String name, String type, String bank) {
        return AccountService.createAccount(ctx, new Map<String, Object>{ 'name' => name, 'type' => type, 'institution' => bank, 'isShared' => true }).id;
    }

    static DepositDtos.Deposit fd(UserContext ctx, Id accountId, Decimal principal, Decimal rate, Date start, Integer months, Map<String, Object> extra) {
        Map<String, Object> body = new Map<String, Object>{
            'principal' => principal, 'rate' => rate, 'startDate' => String.valueOf(start), 'tenureMonths' => months
        };
        if (extra != null) {
            body.putAll(extra);
        }
        return DepositService.save(ctx, accountId, body);
    }

    static void expectError(String code, String label, Callable action) {
        try {
            action.call(null, null);
            Assert.fail('expected ' + code + ': ' + label);
        } catch (PortalException e) {
            Assert.areEqual(code, e.code(), label);
        }
    }

    @IsTest
    static void calculatorMatchesBankFigures() {
        Date d = Date.newInstance(2026, 1, 1);
        Assert.areEqual(107185.90, DepositCalculator.fdValue(100000, 7, 'Quarterly', d, d.addYears(1), d.addYears(1)), '1 year, quarterly');
        Assert.areEqual(141477.82, DepositCalculator.fdValue(100000, 7, 'Quarterly', d, d.addYears(5), d.addYears(5)), '5 years, quarterly');
        Assert.areEqual(101479.45, DepositCalculator.fdValue(100000, 6, 'Quarterly', d, d.addDays(90), d.addDays(90)), 'under 6 months is simple interest');
        Assert.areEqual(124621.32, DepositCalculator.rdMaturity(10000, 7, 12, d), 'RD of 10,000 a month for a year');
        Assert.areEqual(579.94, DepositCalculator.payoutPerPeriod(100000, 7, 'Monthly'), 'monthly payout is discounted');
        Assert.areEqual(1750.00, DepositCalculator.payoutPerPeriod(100000, 7, 'Quarterly'));
        Assert.areEqual(Date.newInstance(2025, 4, 1), DepositCalculator.financialYearStart(Date.newInstance(2026, 3, 31)));
        Assert.areEqual('FY 2026-27', DepositCalculator.financialYearLabel(Date.newInstance(2026, 10, 31)));
        Assert.areEqual(3, DepositCalculator.rdInstalmentsDue(d, 12, d.addMonths(2)));
        Assert.areEqual(7.19, DepositCalculator.effectiveYield(100000, 107185.90, d, d.addYears(1)), 'quarterly compounding beats the headline rate');
    }

    @IsTest
    static void fixedDepositMaturesIntoTheLedger() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        Id account = depositAccount(admin, 'SBI FD', 'Fixed Deposit', 'SBI');
        Date start = Date.today().addMonths(-12);
        DepositDtos.Deposit d = fd(admin, account, 100000, 7, start, 12, new Map<String, Object>{
            'depositNumber' => '40123456789', 'payoutAccountId' => savings, 'nominee' => 'Asha'
        });
        Assert.areEqual(DepositCalculator.fdValue(100000, 7, 'Quarterly', start, start.addMonths(12), start.addMonths(12)), d.maturityAmount);
        Assert.areEqual(Date.today(), d.maturityDate);
        Assert.areEqual(100000, LedgerTestData.balance(account), 'the account opens with the amount invested');
        Assert.areEqual('40123456789', d.depositNumber, 'admins see the full number');
        Assert.areEqual('•••• 6789', DepositService.get(VkfTestData.ctx('membera'), account).depositNumber, 'others see it masked');
        Assert.areEqual('Asha', d.nominee);
        for (FinanceDtos.Account a : AccountService.listAccounts(admin, false)) {
            Assert.areEqual(a.id == account, a.deposit != null, 'only the FD account carries deposit terms');
        }

        Test.startTest();
        DepositDtos.Deposit closed = DepositService.close(admin, account, new Map<String, Object>());
        Test.stopTest();
        Assert.areEqual('Matured', closed.status);
        Assert.areEqual(d.maturityAmount, closed.amountReceived);
        Assert.areEqual(500000 + d.maturityAmount, LedgerTestData.balance(savings));
        Assert.areEqual(0, LedgerTestData.balance(account));
        Assert.areEqual('Closed', [SELECT Status__c FROM Financial_Account__c WHERE Id = :account].Status__c);
        Transaction__c interest = [SELECT Amount__c, Category__r.Name FROM Transaction__c WHERE Account__c = :account AND Type__c = 'Income'];
        Assert.areEqual(d.maturityAmount - 100000, interest.Amount__c, 'interest is booked as income');
        Assert.areEqual('Interest and Dividends', interest.Category__r.Name);
        expectError('CONFLICT', 'closing twice', new Action(admin, account, 'close', null));
    }

    @IsTest
    static void earlyClosureAppliesThePenaltyAndTaxSaversAreLocked() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        Id account = depositAccount(admin, 'HDFC FD', 'Fixed Deposit', 'HDFC');
        Date start = Date.today().addMonths(-6);
        DepositDtos.Deposit d = fd(admin, account, 100000, 8, start, 24, new Map<String, Object>{ 'payoutAccountId' => savings, 'penaltyRate' => 1 });
        Decimal expected = DepositCalculator.fdValue(100000, 7, 'Quarterly', start, Date.today(), Date.today());
        Assert.areEqual(expected, d.prematureValue, 'one percent off the rate for the time it ran');

        Test.startTest();
        DepositDtos.Deposit closed = DepositService.close(admin, account, new Map<String, Object>());
        Test.stopTest();
        Assert.areEqual('Closed Early', closed.status);
        Assert.areEqual(500000 + expected, LedgerTestData.balance(savings));

        Id saver = depositAccount(admin, 'Tax saver', 'Fixed Deposit', 'SBI');
        fd(admin, saver, 150000, 6.5, Date.today(), 60, new Map<String, Object>{ 'taxSaver' => true, 'payoutAccountId' => savings });
        expectError('VALIDATION', 'tax savers are locked in for 5 years', new Action(admin, saver, 'close', null));
        Id saver2 = depositAccount(admin, 'Tax saver 2', 'Fixed Deposit', 'SBI');
        expectError('VALIDATION', 'tax savers hold up to 1.5 lakh', new Action(admin, saver2, 'save', new Map<String, Object>{
            'principal' => 200000, 'rate' => 6.5, 'startDate' => String.valueOf(Date.today()), 'tenureMonths' => 60, 'taxSaver' => true
        }));
        expectError('VALIDATION', 'tax savers run 5 years', new Action(admin, saver2, 'save', new Map<String, Object>{
            'principal' => 100000, 'rate' => 6.5, 'startDate' => String.valueOf(Date.today()), 'tenureMonths' => 36, 'taxSaver' => true
        }));
    }

    @IsTest
    static void recurringDepositsScheduleTheirInstalments() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        Id account = depositAccount(admin, 'Post office RD', 'Recurring Deposit', 'India Post');
        Date start = Date.today().addMonths(-2);
        DepositDtos.Deposit d = DepositService.save(admin, account, new Map<String, Object>{
            'instalment' => 5000, 'rate' => 6.5, 'startDate' => String.valueOf(start), 'tenureMonths' => 24, 'fundingAccountId' => savings
        });
        Assert.areEqual('RD', d.kind);
        Assert.areEqual(3, d.instalmentsDue);
        Assert.areEqual(15000, LedgerTestData.balance(account), 'the three instalments already paid');
        Assert.areEqual(DepositCalculator.rdMaturity(5000, 6.5, 24, start), d.maturityAmount);
        Assert.areEqual(120000, d.invested);
        Assert.areEqual('Quarterly', d.compounding, 'RDs always compound quarterly');
        Recurring_Rule__c rule = [SELECT Type__c, Amount__c, Account__c, To_Account__c, Next_Run_Date__c, End_Date__c, Mode__c, Active__c FROM Recurring_Rule__c WHERE Id = :d.scheduleRuleId];
        Assert.areEqual('Transfer', rule.Type__c);
        Assert.areEqual(5000, rule.Amount__c);
        Assert.areEqual(savings, rule.Account__c);
        Assert.areEqual(account, rule.To_Account__c);
        Assert.areEqual(start.addMonths(3), rule.Next_Run_Date__c);
        Assert.areEqual(start.addMonths(23), rule.End_Date__c);
        Assert.areEqual('Auto-post', rule.Mode__c);

        DepositService.save(admin, account, new Map<String, Object>{ 'instalment' => 6000 });
        Assert.areEqual(6000, [SELECT Amount__c FROM Recurring_Rule__c WHERE Id = :d.scheduleRuleId].Amount__c, 'the schedule follows the terms');
        Assert.areEqual(1, [SELECT COUNT() FROM Recurring_Rule__c], 'one schedule per deposit');

        expectError('VALIDATION', 'RDs run at least 6 months', new Action(admin, account, 'save', new Map<String, Object>{ 'tenureMonths' => 3 }));
        expectError('VALIDATION', 'RDs run whole months', new Action(admin, account, 'save', new Map<String, Object>{ 'tenureDays' => 10 }));
        expectError('VALIDATION', 'RDs are not renewed', new Action(admin, account, 'renew', new Map<String, Object>()));

        Test.startTest();
        DepositService.close(admin, account, new Map<String, Object>{ 'toAccountId' => savings });
        Test.stopTest();
        Assert.isFalse([SELECT Active__c FROM Recurring_Rule__c WHERE Id = :d.scheduleRuleId].Active__c, 'closing stops the instalments');
    }

    @IsTest
    static void payoutDepositsCreditInterestAndRenew() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 0).id;
        Id monthly = depositAccount(admin, 'Income FD', 'Fixed Deposit', 'SBI');
        DepositDtos.Deposit p = fd(admin, monthly, 100000, 7, Date.today().addMonths(-1), 12, new Map<String, Object>{
            'payout' => 'Quarterly', 'payoutAccountId' => savings
        });
        Assert.areEqual(1750, p.payoutPerPeriod);
        Assert.areEqual(100000, p.maturityAmount, 'payout deposits return the principal');
        Assert.areEqual(7000, p.interestAtMaturity);
        Recurring_Rule__c rule = [SELECT Type__c, Amount__c, Frequency__c, Account__c FROM Recurring_Rule__c WHERE Id = :p.scheduleRuleId];
        Assert.areEqual('Income', rule.Type__c);
        Assert.areEqual('Quarterly', rule.Frequency__c);
        Assert.areEqual(savings, rule.Account__c);

        Id renewing = depositAccount(admin, 'Rollover FD', 'Fixed Deposit', 'SBI');
        DepositDtos.Deposit r = fd(admin, renewing, 100000, 7, Date.today().addMonths(-12), 12, new Map<String, Object>{ 'payoutAccountId' => savings });
        Test.startTest();
        DepositDtos.Deposit renewed = DepositService.renew(admin, renewing, new Map<String, Object>{ 'rate' => 7.25, 'tenureMonths' => 12 });
        Test.stopTest();
        Assert.areEqual('Active', renewed.status);
        Assert.areEqual(r.maturityAmount, renewed.principal, 'principal and interest roll over');
        Assert.areEqual(Date.today(), renewed.startDate);
        Assert.areEqual(7.25, renewed.rate);
        Assert.areEqual(Date.today().addMonths(12), renewed.maturityDate);
        Assert.areEqual(r.maturityAmount, LedgerTestData.balance(renewing));

        Id principalOnly = depositAccount(admin, 'Principal-only FD', 'Fixed Deposit', 'SBI');
        DepositDtos.Deposit q = fd(admin, principalOnly, 50000, 7, Date.today().addMonths(-12), 12, new Map<String, Object>{ 'payoutAccountId' => savings });
        DepositDtos.Deposit again = DepositService.renew(admin, principalOnly, new Map<String, Object>{ 'includeInterest' => false });
        Assert.areEqual(50000, again.principal, 'without the interest only the principal rolls over');
        Assert.areEqual(50000, LedgerTestData.balance(principalOnly));
        Assert.areEqual(q.maturityAmount - 50000, LedgerTestData.balance(savings), 'the interest went to savings');
    }

    @IsTest
    static void portfolioFlagsTdsAndDepositInsurance() {
        UserContext admin = VkfTestData.ctx('admina');
        Date fyStart = DepositCalculator.financialYearStart(Date.today());
        Id big = depositAccount(admin, 'HDFC FD', 'Fixed Deposit', 'HDFC');
        fd(admin, big, 700000, 9, fyStart, 12, null);
        Id small = depositAccount(admin, 'ICICI FD', 'Fixed Deposit', 'ICICI');
        fd(admin, small, 100000, 7, fyStart, 12, new Map<String, Object>{ 'form15Submitted' => true });

        DepositDtos.Portfolio p = DepositService.portfolio(admin);
        Assert.areEqual(2, p.deposits.size());
        Assert.areEqual(800000, p.invested);
        Assert.areEqual(DepositCalculator.financialYearLabel(Date.today()), p.financialYear);
        DepositDtos.TdsLine hdfc;
        DepositDtos.CoverLine hdfcCover;
        for (DepositDtos.TdsLine t : p.tds) {
            if (t.institution == 'HDFC') {
                hdfc = t;
            }
        }
        for (DepositDtos.CoverLine c : p.cover) {
            if (c.institution == 'HDFC') {
                hdfcCover = c;
            }
        }
        Assert.isTrue(hdfc.interest > 50000, 'a year at 9% on 7 lakh passes the TDS threshold');
        Assert.areEqual(50000, hdfc.threshold);
        Assert.areEqual((hdfc.interest * 0.10).setScale(2, RoundingMode.HALF_UP), hdfc.estimatedTds);
        Assert.isTrue(hdfcCover.uncovered >= 200000, 'DICGC covers 5 lakh per bank');

        DepositService.save(admin, big, new Map<String, Object>{ 'seniorCitizen' => true });
        for (DepositDtos.TdsLine t : DepositService.portfolio(admin).tds) {
            if (t.institution == 'HDFC') {
                Assert.areEqual(100000, t.threshold, 'senior citizens have a higher threshold');
                Assert.areEqual(0, t.estimatedTds);
            }
            if (t.institution == 'ICICI') {
                Assert.areEqual(0, t.estimatedTds, 'Form 15G/15H stops TDS');
            }
        }
    }

    @IsTest
    static void maturityRemindersAreSentOnce() {
        UserContext admin = VkfTestData.ctx('admina');
        Id account = depositAccount(admin, 'Short FD', 'Fixed Deposit', 'SBI');
        fd(admin, account, 50000, 6.5, Date.today().addMonths(-12).addDays(3), 12, null);
        Set<Id> admins = SystemContext.adminIds(admin.familyId);
        Integer sent = DepositService.notifyMaturities(admin.familyId, Date.today(), admins);
        Assert.isTrue(sent > 0);
        Assert.areEqual(0, DepositService.notifyMaturities(admin.familyId, Date.today(), admins), 'not repeated');
        Assert.isTrue(DepositService.notifyMaturities(admin.familyId, Date.today().addDays(3), admins) > 0, 'again once it has matured');
        Assert.areEqual(1, [SELECT COUNT() FROM Notification__c WHERE Type__c = 'DEPOSIT_MATURED' AND Recipient__c = :admin.userId]);
    }

    @IsTest
    static void termsAreValidated() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 1000).id;
        Id account = depositAccount(admin, 'FD', 'Fixed Deposit', 'SBI');
        Map<String, Object> ok = new Map<String, Object>{ 'principal' => 10000, 'rate' => 7, 'startDate' => String.valueOf(Date.today()), 'tenureMonths' => 12 };
        expectError('VALIDATION', 'only deposit accounts', new Action(admin, savings, 'save', ok));
        for (Map<String, Object> bad : new List<Map<String, Object>>{
            new Map<String, Object>{ 'rate' => 0 },
            new Map<String, Object>{ 'rate' => 25 },
            new Map<String, Object>{ 'tenureMonths' => 0, 'tenureDays' => 3 },
            new Map<String, Object>{ 'tenureMonths' => 121 },
            new Map<String, Object>{ 'principal' => 0 },
            new Map<String, Object>{ 'depositNumber' => '12' },
            new Map<String, Object>{ 'compounding' => 'Daily' },
            new Map<String, Object>{ 'maturityAmount' => 5000 },
            new Map<String, Object>{ 'startDate' => String.valueOf(Date.today().addDays(60)) }
        }) {
            Map<String, Object> body = ok.clone();
            body.putAll(bad);
            expectError('VALIDATION', JSON.serialize(bad), new Action(admin, account, 'save', body));
        }
        expectError('VALIDATION', 'payout into another deposit', new Action(admin, account, 'save', new Map<String, Object>{ 'payoutAccountId' => account }));
        expectError('NOT_AUTHORIZED', 'members cannot change an admin\'s deposit', new Action(VkfTestData.ctx('membera'), account, 'save', ok));
        expectError('VALIDATION', 'close before any terms', new Action(admin, account, 'close', null));

        Map<String, Object> byDate = new Map<String, Object>{
            'principal' => 10000, 'rate' => 7, 'startDate' => String.valueOf(Date.today()), 'maturityDate' => String.valueOf(Date.today().addMonths(13).addDays(5))
        };
        DepositDtos.Deposit d = DepositService.save(admin, account, byDate);
        Assert.areEqual(13, d.tenureMonths, 'the bank\'s maturity date becomes months');
        Assert.areEqual(5, d.tenureDays, 'and days');
        DepositDtos.Deposit quoted = DepositService.save(admin, account, new Map<String, Object>{ 'maturityAmount' => 10800 });
        Assert.isTrue(quoted.maturityQuoted);
        Assert.areEqual(10800, quoted.maturityAmount, 'the bank\'s figure wins');
        Assert.areNotEqual(quoted.maturityAmount, quoted.calculatedMaturity);
        expectError('VALIDATION', 'type is fixed once terms exist', new Action(admin, account, 'retype', null));
    }

    @IsTest
    static void endpointsRoute() {
        String token = VkfTestData.login('admina');
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 0).id;
        Id account = depositAccount(admin, 'FD', 'Fixed Deposit', 'SBI');
        RestResponse res = VkfTestData.call('PATCH', '/vkf/v1/deposits/' + account,
            '{"principal":25000,"rate":7.1,"startDate":"' + String.valueOf(Date.today().addMonths(-12)) + '","tenureMonths":12,"payoutAccountId":"' + savings + '"}', token);
        VkfDepositsResource.patch();
        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        Test.startTest();
        res = VkfTestData.call('GET', '/vkf/v1/deposits', null, token);
        VkfDepositsResource.get();
        Assert.areEqual(1, ((List<Object>) VkfTestData.json(res).get('deposits')).size());
        res = VkfTestData.call('GET', '/vkf/v1/deposits/' + account, null, token);
        VkfDepositsResource.get();
        Assert.areEqual('FD', VkfTestData.json(res).get('kind'));
        res = VkfTestData.call('POST', '/vkf/v1/deposits/' + account + '/close', '{}', token);
        VkfDepositsResource.post();
        Assert.areEqual('Matured', VkfTestData.json(res).get('status'), res.responseBody.toString());
        res = VkfTestData.call('POST', '/vkf/v1/deposits/' + account + '/explode', '{}', token);
        VkfDepositsResource.post();
        Assert.areEqual(404, res.statusCode);
        Test.stopTest();
    }

    /** Runs one service call so expectError can check what it throws. */
    private class Action implements Callable {
        UserContext ctx;
        Id accountId;
        String what;
        Map<String, Object> body;

        Action(UserContext ctx, Id accountId, String what, Map<String, Object> body) {
            this.ctx = ctx;
            this.accountId = accountId;
            this.what = what;
            this.body = body == null ? new Map<String, Object>() : body;
        }

        public Object call(String action, Map<String, Object> args) {
            switch on what {
                when 'save' {
                    return DepositService.save(ctx, accountId, body);
                }
                when 'close' {
                    return DepositService.close(ctx, accountId, body);
                }
                when 'renew' {
                    return DepositService.renew(ctx, accountId, body);
                }
                when else {
                    return AccountService.updateAccount(ctx, accountId, new Map<String, Object>{ 'type' => 'Savings' });
                }
            }
        }
    }
}
