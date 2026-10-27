/**
 * Moves money between two family accounts as two linked legs sharing a Transfer_Group_Id:
 * the source is debited and the destination credited, so family income and spending don't
 * change. Paying a credit card is the same shape with type Card Payment - the spend was
 * already counted when the card was swiped.
 */
public without sharing class TransferService {
    public static FinanceDtos.Transfer createTransfer(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'CREATE');
        Financial_Account__c source = TransactionService.usableAccount(ctx, VkfRest.toId(LedgerUtil.text(body, 'fromAccountId')));
        if (LedgerUtil.isLiability(source.Type__c)) {
            throw new PortalException('VALIDATION').withError('Transfers start from a bank, cash or wallet account.');
        }
        Id toId = VkfRest.toId(LedgerUtil.text(body, 'toAccountId'));
        if (toId == null) {
            throw new PortalException('VALIDATION').withError('Choose where the money goes.');
        }
        // Any active account in the family can receive money, e.g. pocket money to a child's wallet.
        Financial_Account__c target = new AccountSelector(ctx).byId(toId);
        if (target.Id == source.Id) {
            throw new PortalException('VALIDATION').withError('Choose two different accounts.');
        }
        if (target.Status__c != 'Active') {
            throw new PortalException('VALIDATION').withError('The receiving account is closed.');
        }
        if (target.Type__c == 'Loan') {
            throw new PortalException('VALIDATION').withError('Loan repayments arrive with EMI tracking in a later release.');
        }

        Decimal amount = LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount');
        Date txnDate = LedgerUtil.txnDate(LedgerUtil.dateValue(body, 'date', 'Date'));
        String notes = LedgerUtil.limited(LedgerUtil.text(body, 'notes'), 255, 'Notes');
        String reference = LedgerUtil.limited(LedgerUtil.text(body, 'referenceNo'), 60, 'Reference');
        String mode = TransactionService.mode(LedgerUtil.text(body, 'paymentMode'));
        Boolean cardPayment = target.Type__c == 'Credit Card';
        Category__c category = CategoryService.ensureSeeded(ctx).systemCategory(cardPayment ? 'CARD_PAYMENT' : 'TRANSFER');
        Id payer = new LedgerScope(ctx).memberFor(VkfRest.toId(LedgerUtil.text(body, 'memberId')), new PortalUserSelector(ctx));
        String groupId = TokenService.newToken().left(32);

        Transaction__c outLeg = leg(ctx, source, cardPayment ? 'Card Payment' : 'Transfer Out', 'Debit', amount, txnDate, category, payer);
        outLeg.Payee__c = target.Name.left(120);
        Transaction__c inLeg = leg(ctx, target, cardPayment ? 'Card Payment' : 'Transfer In', 'Credit', amount, txnDate, category,
            target.Owner_Member__c == null ? payer : target.Owner_Member__c);
        inLeg.Payee__c = source.Name.left(120);
        for (Transaction__c t : new List<Transaction__c>{ outLeg, inLeg }) {
            t.Transfer_Group_Id__c = groupId;
            t.Notes__c = notes;
            t.Reference_No__c = reference;
            t.Payment_Mode__c = mode;
        }
        insert as system new List<Transaction__c>{ outLeg, inLeg };
        update as system new List<Transaction__c>{
            new Transaction__c(Id = outLeg.Id, Counter_Transaction__c = inLeg.Id),
            new Transaction__c(Id = inLeg.Id, Counter_Transaction__c = outLeg.Id)
        };
        AuditService.log(ctx, cardPayment ? 'CARD_PAYMENT' : 'TRANSFER_CREATED', 'Transaction__c', outLeg.Id,
            source.Name + ' -> ' + target.Name + ' ' + amount);

        TransactionSelector selector = new TransactionSelector(ctx);
        List<FinanceDtos.Txn> legs = TransactionService.toDtos(ctx, new List<Transaction__c>{ selector.byId(outLeg.Id), selector.byId(inLeg.Id) });
        FinanceDtos.Transfer result = new FinanceDtos.Transfer();
        result.groupId = groupId;
        result.outLeg = legs[0];
        result.inLeg = legs[1];
        return result;
    }

    private static Transaction__c leg(
        UserContext ctx, Financial_Account__c account, String type, String direction, Decimal amount, Date txnDate,
        Category__c category, Id memberId
    ) {
        return new Transaction__c(
            Family__c = ctx.familyId,
            Account__c = account.Id,
            Type__c = type,
            Direction__c = direction,
            Amount__c = amount,
            Txn_Date__c = txnDate,
            Category__c = category?.Id,
            Member__c = memberId,
            Status__c = 'Cleared',
            Source__c = 'Manual'
        );
    }
}
