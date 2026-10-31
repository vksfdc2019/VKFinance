/** Regressions for real card bills, transfer accounting, visibility and payment reversal. */
@IsTest
private class CreditCardBillTest {
    @TestSetup
    static void setup() { VkfTestData.twoFamilies(); }

    private class Fixture {
        UserContext admin;
        Id bankId;
        Id cardId;
        Id billId;
        Id instanceId;
        Fixture(Date due) {
            VkfTestData.fastPolicy();
            admin = VkfTestData.ctx('admina');
            bankId = LedgerTestData.account(admin, 'Bank', 'Savings', 100000).id;
            cardId = AccountService.createAccount(admin, new Map<String, Object>{
                'name' => 'AXIS BANK NEO', 'type' => 'Credit Card', 'openingBalance' => 29613.72,
                'creditLimit' => 314000, 'statementDay' => 16, 'paymentDueDays' => 20
            }).id;
            billId = BillService.createBill(admin, input(cardId, bankId, due)).id;
            instanceId = BillService.listBills(admin).open[0].id;
        }
        FinanceDtos.Account card() {
            for (FinanceDtos.Account a : AccountService.listAccounts(admin, false)) if (a.id == cardId) return a;
            Assert.fail('card missing'); return null;
        }
    }

    private static Map<String, Object> input(Id cardId, Id bankId, Date due) {
        return new Map<String, Object>{
            'name' => 'AXIS BANK NEO CC', 'categoryId' => LedgerTestData.categoryId(VkfTestData.ctx('admina'), 'Electricity'),
            'frequency' => 'Monthly', 'nextDueDate' => String.valueOf(due), 'expectedAmount' => 16985.59,
            'payFromAccountId' => bankId, 'creditCardAccountId' => cardId
        };
    }

    @IsTest static void linkedBillOverridesStatementWithoutChangingOutstanding() {
        Fixture f = new Fixture(Date.today().addDays(6));
        Test.startTest();
        CardStatementService.generate(f.admin.familyId, Date.today());
        FinanceDtos.Account card = f.card();
        Test.stopTest();
        Assert.areEqual(29613.72, card.balance);
        Assert.areEqual(284386.28, card.card.available);
        Assert.areEqual(314000, card.creditLimit);
        Assert.areEqual(16985.59, card.card.bill.amount);
        Assert.areEqual(Date.today().addDays(6), card.card.bill.dueDate);
        Assert.areEqual(0, card.card.bill.amountPaid);
        Assert.areEqual(f.billId, card.card.bill.billId);
        Assert.areEqual(100000, LedgerTestData.balance(f.bankId), 'adding a bill never moves money');
    }

    @IsTest static void billPaymentsAndCardTransfersShareOneAllocationAndVoidOnce() {
        Fixture f = new Fixture(Date.today());
        Test.startTest();
        BillService.payInstance(f.admin, f.instanceId, new Map<String, Object>{ 'amount' => 1000 });
        Assert.areEqual('Partially Paid', f.card().card.bill.status);
        FinanceDtos.Transfer payment = LedgerTestData.transfer(f.admin, f.bankId, f.cardId, 15985.59);
        Assert.areEqual('Paid', f.card().card.bill.status);
        Assert.areEqual(12628.13, LedgerTestData.balance(f.cardId));
        Assert.areEqual(83014.41, LedgerTestData.balance(f.bankId));
        Assert.areEqual(0, [SELECT COUNT() FROM Transaction__c WHERE Type__c = 'Bill Payment' WITH SYSTEM_MODE], 'card repayments are not expenses');
        for (Id legId : new List<Id>{ payment.outLeg.id, payment.inLeg.id }) {
            try {
                TransactionService.updateTransaction(f.admin, legId, new Map<String, Object>{ 'amount' => 1 });
                Assert.fail('allocated payments must be voided, not edited');
            } catch (PortalException e) { Assert.areEqual('VALIDATION', e.code()); }
        }
        TransactionService.voidTransaction(f.admin, payment.inLeg.id);
        Assert.areEqual(1000, f.card().card.bill.amountPaid, 'both legs are voided, but the allocation is reversed once');
        Assert.areEqual('Partially Paid', f.card().card.bill.status);
        Assert.areEqual(28613.72, LedgerTestData.balance(f.cardId));
        Test.stopTest();
    }

    @IsTest static void excessCardPaymentOnlyReversesItsAllocatedAmount() {
        Fixture f = new Fixture(Date.today());
        Test.startTest();
        FinanceDtos.Transfer payment = LedgerTestData.transfer(f.admin, f.bankId, f.cardId, 20000);
        Assert.areEqual(16985.59, f.card().card.bill.amountPaid);
        TransactionService.voidTransaction(f.admin, payment.outLeg.id);
        Assert.areEqual(0, f.card().card.bill.amountPaid);
        Assert.areEqual(29613.72, LedgerTestData.balance(f.cardId));
        Assert.areEqual(100000, LedgerTestData.balance(f.bankId));
        Test.stopTest();
    }

    @IsTest static void paidCycleRemainsVisibleUntilNextDueMonthAndOverdueWins() {
        Fixture f = new Fixture(Date.today());
        Test.startTest();
        BillService.payInstance(f.admin, f.instanceId, new Map<String, Object>());
        Assert.areEqual('Paid', f.card().card.bill.status, 'next month\'s generated bill must not hide this month\'s paid bill');
        Map<Id, FinanceDtos.CardCycle> cycles = new Map<Id, FinanceDtos.CardCycle>{ f.cardId => new FinanceDtos.CardCycle() };
        BillService.attachCardBills(f.admin, cycles, Date.today().toStartOfMonth().addMonths(1));
        Assert.areEqual(Date.today().addMonths(1), cycles.get(f.cardId).bill.dueDate);
        Assert.areNotEqual('Paid', cycles.get(f.cardId).bill.status);
        update as system new Bill_Instance__c(Id = f.instanceId, Status__c = 'Due', Amount_Paid__c = 0, Due_Date__c = Date.today().addDays(-1));
        Assert.areEqual('Overdue', f.card().card.bill.status);
        Test.stopTest();
    }

    @IsTest static void linkingRequiresOwnFamilyCardAndOneActiveBill() {
        Fixture f = new Fixture(Date.today());
        Id other = LedgerTestData.account(VkfTestData.ctx('adminb'), 'Other card', 'Credit Card', 0).id;
        Test.startTest();
        for (Id invalid : new List<Id>{ other, f.bankId, f.cardId }) {
            try {
                BillService.createBill(f.admin, input(invalid, f.bankId, Date.today()));
                Assert.fail('invalid or duplicate card link');
            } catch (PortalException e) {
                Assert.isTrue(new Set<String>{ 'NOT_FOUND', 'VALIDATION' }.contains(e.code()), e.getMessage());
            }
        }
        BillService.payInstance(f.admin, f.instanceId, new Map<String, Object>{ 'amount' => 10 });
        try {
            BillService.updateBill(f.admin, f.billId, new Map<String, Object>{ 'creditCardAccountId' => null });
            Assert.fail('paid bill link is immutable');
        } catch (PortalException e) { Assert.areEqual('VALIDATION', e.code()); }
        for (FinanceDtos.Account a : AccountService.listAccounts(VkfTestData.ctx('adminb'), false)) {
            Assert.isNull(a.card.bill, 'another family never sees the linked bill');
        }
        Test.stopTest();
    }

    @IsTest static void oneTimeBillStaysPaidAndReopensWhenVoided() {
        Fixture f = new Fixture(Date.today());
        BillService.updateBill(f.admin, f.billId, new Map<String, Object>{ 'frequency' => 'One-time' });
        Test.startTest();
        BillService.payInstance(f.admin, f.instanceId, new Map<String, Object>());
        Assert.areEqual('Paid', f.card().card.bill.status);
        Transaction__c leg = [SELECT Id FROM Transaction__c WHERE Bill_Instance__c = :f.instanceId AND Direction__c = 'Debit' WITH SYSTEM_MODE LIMIT 1];
        TransactionService.voidTransaction(f.admin, leg.Id);
        Assert.areEqual(0, f.card().card.bill.amountPaid);
        Assert.areNotEqual('Paid', f.card().card.bill.status);
        Test.stopTest();
    }
}