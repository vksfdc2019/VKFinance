/** Editing loans (details, corrected terms, deleting a mistake) and the full credit card terms. */
@IsTest
private class LoanAndCardEditTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    static CommitmentDtos.Loan homeLoan(UserContext ctx, Id savings) {
        return LoanService.createLoan(ctx, new Map<String, Object>{
            'name' => 'Home loan', 'lender' => 'SBI', 'loanType' => 'Home', 'principal' => 2012000, 'annualRate' => 9.5, 'tenureMonths' => 85,
            'firstEmiDate' => String.valueOf(Date.today().addMonths(-31)), 'installmentsPaid' => 31, 'debitAccountId' => savings,
            'loanAccountNumber' => 'HL-0045 7781 2290'
        });
    }

    static void expectError(String code, String label, Map<String, Object> body, UserContext ctx, Id loanId) {
        try {
            LoanService.updateLoan(ctx, loanId, body);
            Assert.fail('expected ' + code + ': ' + label);
        } catch (PortalException e) {
            Assert.areEqual(code, e.code(), label);
        }
    }

    @IsTest
    static void detailsChangeWithoutTouchingTheMaths() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        CommitmentDtos.Loan loan = homeLoan(admin, savings);
        Assert.areEqual('HL-0045 7781 2290', loan.loanAccountNumber, 'admins see the full number');
        Assert.areEqual('•••• 2290', loan.loanAccountNumberMasked);
        Assert.isTrue(loan.canEdit);
        Assert.isTrue(loan.canDelete, 'nothing paid yet');

        CommitmentDtos.Loan edited = LoanService.updateLoan(admin, loan.id, new Map<String, Object>{
            'name' => 'SBI home loan', 'lender' => 'State Bank of India', 'loanType' => 'Personal', 'rateType' => 'Floating'
        });
        Assert.areEqual('SBI home loan', edited.name);
        Assert.areEqual('State Bank of India', edited.lender);
        Assert.areEqual('Personal', edited.loanType);
        Assert.areEqual('Floating', edited.rateType);
        Assert.areEqual(loan.outstanding, edited.outstanding, 'details leave the outstanding alone');
        Assert.areEqual(loan.emi, edited.emi);
        Financial_Account__c account = [SELECT Name, Institution__c FROM Financial_Account__c WHERE Id = :loan.loanAccountId];
        Assert.areEqual('SBI home loan', account.Name, 'the loan account follows');
        Assert.areEqual('State Bank of India', account.Institution__c);
        Assert.areEqual(0, LoanService.listLoans(VkfTestData.ctx('membera')).size(), 'members still see only their own loans');
    }

    @IsTest
    static void correctedTermsRepriceTheLoan() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        CommitmentDtos.Loan loan = homeLoan(admin, savings);

        CommitmentDtos.Loan bank = LoanService.updateLoan(admin, loan.id, new Map<String, Object>{ 'emiAmount' => 35539, 'outstandingAmount' => 1300000 });
        Assert.areEqual(35539, bank.emi, 'the bank\'s EMI');
        Assert.areEqual(1300000, bank.outstanding, 'the bank\'s outstanding');
        Assert.areEqual(1300000, LedgerTestData.balance(loan.loanAccountId), 'moved through the opening balance');
        Assert.areEqual(0, [SELECT COUNT() FROM Transaction__c WHERE Account__c = :loan.loanAccountId], 'no adjustment needed yet');
        Assert.areEqual(32, bank.next.no);

        CommitmentDtos.Loan recounted = LoanService.updateLoan(admin, loan.id, new Map<String, Object>{ 'installmentsPaid' => 30, 'tenureMonths' => 84, 'emiAmount' => null });
        Assert.areEqual(EmiCalculator.emi(2012000, 9.5, 84), recounted.emi, 'clearing the EMI works it out again');
        Assert.areEqual(EmiCalculator.outstandingAfter(2012000, 9.5, recounted.emi, 30), recounted.outstanding);
        Assert.areEqual(31, recounted.next.no);

        Test.startTest();
        LoanService.payEmi(admin, loan.id, new Map<String, Object>());
        CommitmentDtos.Loan afterPayment = LoanService.updateLoan(admin, loan.id, new Map<String, Object>{ 'outstandingAmount' => 1250000 });
        Test.stopTest();
        Assert.areEqual(1250000, afterPayment.outstanding);
        Assert.areEqual(1, [SELECT COUNT() FROM Transaction__c WHERE Account__c = :loan.loanAccountId AND Type__c = 'Adjustment'], 'with payments recorded, one adjustment entry');
        Assert.isFalse(afterPayment.canDelete, 'payments are recorded now');
        Assert.areEqual(1, afterPayment.installmentsPaidHere);

        expectError('VALIDATION', 'fewer EMIs than recorded here', new Map<String, Object>{ 'installmentsPaid' => 0 }, admin, loan.id);
        expectError('VALIDATION', 'paid beyond the tenure', new Map<String, Object>{ 'installmentsPaid' => 90 }, admin, loan.id);
        expectError('VALIDATION', 'bad rate', new Map<String, Object>{ 'annualRate' => 70 }, admin, loan.id);
        expectError('VALIDATION', 'bad account number', new Map<String, Object>{ 'loanAccountNumber' => '#!' }, admin, loan.id);
        expectError('NOT_AUTHORIZED', 'members cannot edit', new Map<String, Object>{ 'name' => 'x' }, VkfTestData.ctx('membera'), loan.id);
        try {
            LoanService.deleteLoan(admin, loan.id);
            Assert.fail('a loan with payments cannot be deleted');
        } catch (PortalException e) {
            Assert.areEqual('CONFLICT', e.code());
        }
    }

    @IsTest
    static void aMistakeCanBeDeleted() {
        UserContext admin = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 500000).id;
        CommitmentDtos.Loan loan = homeLoan(admin, savings);
        LoanService.changeRate(admin, loan.id, new Map<String, Object>{ 'annualRate' => 9 });
        String token = VkfTestData.login('admina');
        RestResponse res = VkfTestData.call('DELETE', '/vkf/v1/loans/' + loan.id, null, token);
        VkfLoansResource.remove();
        Assert.areEqual(204, res.statusCode, 'deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Loan__c]);
        Assert.areEqual(0, [SELECT COUNT() FROM EMI_Installment__c]);
        Assert.areEqual(0, [SELECT COUNT() FROM Financial_Account__c WHERE Id = :loan.loanAccountId], 'its loan account goes too');
    }

    @IsTest
    static void creditCardsCarryTheirFullTerms() {
        UserContext admin = VkfTestData.ctx('admina');
        FinanceDtos.Account card = AccountService.createAccount(admin, new Map<String, Object>{
            'name' => 'HDFC Regalia', 'type' => 'Credit Card', 'institution' => 'HDFC Bank', 'last4' => '4321', 'creditLimit' => 300000,
            'statementDay' => 12, 'paymentDueDays' => 20, 'minDuePct' => 5, 'cardNetwork' => 'Visa', 'cardExpiry' => '08/29',
            'cashLimit' => 90000, 'annualFee' => 2500, 'feeWaiverSpend' => 300000, 'cardInterestRate' => 3.75, 'cardAutopay' => 'Total due'
        });
        Assert.areEqual('Visa', card.cardNetwork);
        Assert.areEqual(Date.newInstance(2029, 8, 31), card.cardExpiry, 'expiry is the end of the month');
        Assert.areEqual(90000, card.cashLimit);
        Assert.areEqual(3.75, card.cardInterestRate);
        Assert.areEqual('Total due', card.cardAutopay);
        Assert.areEqual(card.card.dueDate.addDays(3), card.card.lateFeeAfter, 'RBI: no late fee for 3 days after the due date');
        Assert.isTrue(card.card.interestFreeDays >= 47 && card.card.interestFreeDays <= 50, 'a cycle plus the 20 days to pay');
        Assert.areEqual(90000, card.card.cashAvailable);

        LedgerTestData.entry(admin, 'Expense', 50000, card.id, LedgerTestData.categoryId(admin, 'Groceries'));
        FinanceDtos.Account spent = AccountService.listAccounts(admin, false)[0];
        Assert.areEqual(250000, spent.card.feeWaiverRemaining, 'spend counts towards the fee waiver');
        Assert.areEqual(50000, spent.card.spendLast12Months);

        FinanceDtos.Account edited = AccountService.updateAccount(admin, card.id, new Map<String, Object>{ 'cardNetwork' => 'RuPay', 'cashLimit' => 60000, 'cardAutopay' => 'Off' });
        Assert.areEqual('RuPay', edited.cardNetwork);
        Assert.areEqual(60000, edited.cashLimit);
        Assert.areEqual('Off', edited.cardAutopay);
        Assert.areEqual(2500, edited.annualFee, 'untouched terms stay');

        for (Map<String, Object> bad : new List<Map<String, Object>>{
            new Map<String, Object>{ 'cardExpiry' => '13/29' },
            new Map<String, Object>{ 'cardExpiry' => '2029-08' },
            new Map<String, Object>{ 'cashLimit' => 400000 },
            new Map<String, Object>{ 'cardInterestRate' => 8 },
            new Map<String, Object>{ 'cardNetwork' => 'Discover' },
            new Map<String, Object>{ 'cardAutopay' => 'Sometimes' },
            new Map<String, Object>{ 'annualFee' => -1 }
        }) {
            try {
                AccountService.updateAccount(admin, card.id, bad);
                Assert.fail('expected a validation error: ' + JSON.serialize(bad));
            } catch (PortalException e) {
                Assert.areEqual('VALIDATION', e.code(), JSON.serialize(bad));
            }
        }
    }
}
