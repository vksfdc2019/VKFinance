/**
 * Income, expense and refund entries, plus listing, editing and voiding any ledger row.
 * Transfers and card payments are created by TransferService; once created, both legs
 * are edited and voided together here.
 */
public without sharing class TransactionService {
    public static final Set<String> ENTRY_TYPES = new Set<String>{ 'Income', 'Expense', 'Refund' };
    public static final Integer DEFAULT_PAGE = 50;

    public static FinanceDtos.TxnPage listTransactions(UserContext ctx, Map<String, String> params) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'READ');
        TransactionSelector selector = new TransactionSelector(ctx);
        LedgerScope scope = new LedgerScope(ctx);
        TransactionSelector.Filter f = selector.scoped();

        if (String.isNotBlank(params.get('month'))) {
            f.fromDate = LedgerUtil.monthStart(params.get('month'));
            f.toDate = LedgerUtil.monthEnd(f.fromDate);
        }
        if (String.isNotBlank(params.get('from'))) {
            f.fromDate = LedgerUtil.dateValue(params.get('from'), 'From');
        }
        if (String.isNotBlank(params.get('to'))) {
            f.toDate = LedgerUtil.dateValue(params.get('to'), 'To');
        }
        if (String.isNotBlank(params.get('type'))) {
            f.types = new Set<String>();
            for (String t : params.get('type').split(',')) {
                f.types.add(t.trim());
            }
        }
        if (String.isNotBlank(params.get('accountId'))) {
            Financial_Account__c a = new AccountSelector(ctx).byId(VkfRest.toId(params.get('accountId')));
            if (!scope.canSeeAccount(a)) {
                throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
            }
            f.accountIds = new Set<Id>{ a.Id };
        }
        if (String.isNotBlank(params.get('categoryId'))) {
            CategorySelector categories = new CategorySelector(ctx);
            f.categoryIds = categories.withChildren(categories.byId(VkfRest.toId(params.get('categoryId'))).Id);
        }
        if (String.isNotBlank(params.get('memberId'))) {
            if (!scope.wholeFamily()) {
                throw new PortalException('NOT_AUTHORIZED').withError('You can only filter by member as an admin.');
            }
            f.memberId = new PortalUserSelector(ctx).memberInFamily(VkfRest.toId(params.get('memberId'))).Id;
        }
        f.search = LedgerUtil.limited(params.get('q'), 80, 'Search');
        f.includeVoid = params.get('includeVoid') == 'true';

        Integer pageSize = DEFAULT_PAGE;
        String digits = params.get('limit') == null ? '' : params.get('limit').replaceAll('[^0-9]', '').left(3);
        if (String.isNotBlank(digits)) {
            pageSize = Math.max(1, Math.min(200, Integer.valueOf(digits)));
        }
        String cursor = params.get('cursor');
        FinanceDtos.TxnPage page = new FinanceDtos.TxnPage();
        if (String.isNotBlank(cursor)) {
            List<String> parts = cursor.split('\\|');
            if (parts.size() != 2) {
                throw new PortalException('BAD_REQUEST').withError('Invalid cursor.');
            }
            f.cursorDate = LedgerUtil.dateValue(parts[0], 'Cursor');
            f.cursorName = parts[1];
        } else {
            page.totals = totals(selector, f);
        }

        List<Transaction__c> rows = selector.page(f, pageSize + 1);
        if (rows.size() > pageSize) {
            rows.remove(rows.size() - 1);
            Transaction__c last = rows[rows.size() - 1];
            page.nextCursor = String.valueOf(last.Txn_Date__c) + '|' + last.Name;
        }
        page.items = toDtos(ctx, rows);
        return page;
    }

    private static FinanceDtos.Totals totals(TransactionSelector selector, TransactionSelector.Filter f) {
        FinanceDtos.Totals t = new FinanceDtos.Totals();
        for (AggregateResult ar : selector.aggregate('Type__c t, Direction__c d, SUM(Amount__c) s, COUNT(Id) n', f, 'Type__c, Direction__c')) {
            String type = (String) ar.get('t');
            Decimal sum = LedgerUtil.zeroIfNull(ar.get('s'));
            t.count += (Integer) ar.get('n');
            if (type == 'Income') {
                t.income += sum;
            } else if (type == 'Expense' || type == 'Bill Payment') {
                t.expenses += sum;
            } else if (type == 'Refund') {
                t.expenses -= sum;
            } else if ((type == 'Transfer Out' || type == 'Card Payment') && (String) ar.get('d') == 'Debit') {
                // Both legs of a transfer share the amount; count the money once, on the way out.
                t.transfers += sum;
            }
        }
        return t;
    }

    public static List<FinanceDtos.Txn> toDtos(UserContext ctx, List<Transaction__c> rows) {
        Map<Id, Category__c> categories = new CategorySelector(ctx).byIdMap();
        LedgerScope scope = new LedgerScope(ctx);
        List<FinanceDtos.Txn> result = new List<FinanceDtos.Txn>();
        for (Transaction__c t : rows) {
            result.add(FinanceDtos.txn(t, categories, scope));
        }
        return result;
    }

    public static FinanceDtos.Txn getTransaction(UserContext ctx, Id txnId) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'READ');
        return toDtos(ctx, new List<Transaction__c>{ visible(ctx, new TransactionSelector(ctx), txnId) })[0];
    }

    public static FinanceDtos.Txn createTransaction(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'CREATE');
        String type = LedgerUtil.text(body, 'type');
        if (!ENTRY_TYPES.contains(type)) {
            throw new PortalException('VALIDATION').withError('Type must be Income, Expense or Refund. Use a transfer to move money between accounts.');
        }
        LedgerScope scope = new LedgerScope(ctx);
        Financial_Account__c account = usableAccount(ctx, VkfRest.toId(LedgerUtil.text(body, 'accountId')));
        assertAccountFits(type, account);
        Category__c category = entryCategory(ctx, type, VkfRest.toId(LedgerUtil.text(body, 'categoryId')));

        Transaction__c t = new Transaction__c(
            Family__c = ctx.familyId,
            Type__c = type,
            Direction__c = type == 'Expense' ? 'Debit' : 'Credit',
            Amount__c = LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount'),
            Txn_Date__c = LedgerUtil.txnDate(LedgerUtil.dateValue(body, 'date', 'Date')),
            Account__c = account.Id,
            Category__c = category.Id,
            Member__c = scope.memberFor(VkfRest.toId(LedgerUtil.text(body, 'memberId')), new PortalUserSelector(ctx)),
            Status__c = 'Cleared',
            Source__c = 'Manual'
        );
        applyDetails(t, body);
        insert as system t;
        AuditService.log(ctx, 'TXN_CREATED', 'Transaction__c', t.Id, type + ' ' + t.Amount__c);
        return getTransaction(ctx, t.Id);
    }

    public static FinanceDtos.Txn updateTransaction(UserContext ctx, Id txnId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'EDIT');
        TransactionSelector selector = new TransactionSelector(ctx);
        Transaction__c existing = editable(ctx, selector, txnId);

        if (existing.Transfer_Group_Id__c != null) {
            if (LedgerUtil.has(body, 'accountId') || LedgerUtil.has(body, 'categoryId') || LedgerUtil.has(body, 'type')) {
                throw new PortalException('VALIDATION').withError('To change a transfer\'s accounts, void it and create a new one.');
            }
            List<Transaction__c> legs = new List<Transaction__c>();
            for (Transaction__c leg : selector.byGroup(existing.Transfer_Group_Id__c)) {
                Transaction__c changes = new Transaction__c(Id = leg.Id);
                if (LedgerUtil.has(body, 'amount')) {
                    changes.Amount__c = LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount');
                }
                if (LedgerUtil.has(body, 'date')) {
                    changes.Txn_Date__c = LedgerUtil.txnDate(LedgerUtil.dateValue(body, 'date', 'Date'));
                }
                if (LedgerUtil.has(body, 'notes')) {
                    changes.Notes__c = LedgerUtil.limited(LedgerUtil.text(body, 'notes'), 255, 'Notes');
                }
                if (LedgerUtil.has(body, 'referenceNo')) {
                    changes.Reference_No__c = LedgerUtil.limited(LedgerUtil.text(body, 'referenceNo'), 60, 'Reference');
                }
                if (LedgerUtil.has(body, 'paymentMode')) {
                    changes.Payment_Mode__c = mode(LedgerUtil.text(body, 'paymentMode'));
                }
                legs.add(changes);
            }
            update as system legs;
        } else {
            Transaction__c t = new Transaction__c(Id = existing.Id);
            String type = existing.Type__c;
            if (LedgerUtil.has(body, 'type') && LedgerUtil.text(body, 'type') != type) {
                type = LedgerUtil.text(body, 'type');
                if (!ENTRY_TYPES.contains(type) || !ENTRY_TYPES.contains(existing.Type__c)) {
                    throw new PortalException('VALIDATION').withError('This entry can only switch between Income, Expense and Refund.');
                }
                t.Type__c = type;
                t.Direction__c = type == 'Expense' ? 'Debit' : 'Credit';
            }
            Id accountId = existing.Account__c;
            if (LedgerUtil.has(body, 'accountId')) {
                accountId = usableAccount(ctx, VkfRest.toId(LedgerUtil.text(body, 'accountId'))).Id;
                t.Account__c = accountId;
            }
            if (ENTRY_TYPES.contains(type)) {
                assertAccountFits(type, new AccountSelector(ctx).byId(accountId));
                Id categoryId = LedgerUtil.has(body, 'categoryId') ? VkfRest.toId(LedgerUtil.text(body, 'categoryId')) : existing.Category__c;
                t.Category__c = entryCategory(ctx, type, categoryId).Id;
            }
            if (LedgerUtil.has(body, 'amount')) {
                t.Amount__c = LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount');
            }
            if (LedgerUtil.has(body, 'date')) {
                t.Txn_Date__c = LedgerUtil.txnDate(LedgerUtil.dateValue(body, 'date', 'Date'));
            }
            if (LedgerUtil.has(body, 'memberId')) {
                t.Member__c = new LedgerScope(ctx).memberFor(VkfRest.toId(LedgerUtil.text(body, 'memberId')), new PortalUserSelector(ctx));
            }
            applyDetails(t, body);
            update as system t;
        }
        AuditService.log(ctx, 'TXN_UPDATED', 'Transaction__c', existing.Id, String.join(new List<String>(body.keySet()), ','));
        return getTransaction(ctx, existing.Id);
    }

    /** Voids the entry, and both legs when it's a transfer. Void rows stay for the audit trail. */
    public static void voidTransaction(UserContext ctx, Id txnId) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'DELETE');
        TransactionSelector selector = new TransactionSelector(ctx);
        Transaction__c existing = visible(ctx, selector, txnId);
        if (existing.Status__c == 'Void') {
            throw new PortalException('CONFLICT').withError('That transaction is already void.');
        }
        editable(ctx, selector, txnId);
        List<Transaction__c> rows = existing.Transfer_Group_Id__c == null
            ? new List<Transaction__c>{ existing }
            : selector.byGroup(existing.Transfer_Group_Id__c);
        List<Transaction__c> changes = new List<Transaction__c>();
        for (Transaction__c r : rows) {
            changes.add(new Transaction__c(Id = r.Id, Status__c = 'Void'));
        }
        update as system changes;
        AuditService.log(ctx, 'TXN_VOIDED', 'Transaction__c', existing.Id, existing.Type__c + ' ' + existing.Amount__c);
    }

    // ------------------------------------------------------------------ shared checks

    public static Transaction__c visible(UserContext ctx, TransactionSelector selector, Id txnId) {
        Transaction__c t = selector.byId(txnId);
        LedgerScope scope = new LedgerScope(ctx);
        if (!scope.wholeFamily() && !scope.canSeeTransaction(t, new AccountSelector(ctx).visibleIds())) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        return t;
    }

    private static Transaction__c editable(UserContext ctx, TransactionSelector selector, Id txnId) {
        Transaction__c t = visible(ctx, selector, txnId);
        if (!new LedgerScope(ctx).canEditTransaction(t)) {
            String reason = t.Status__c == 'Void'
                ? 'That transaction is void.'
                : ctx.role == 'Child' ? 'You can change your own entries for 24 hours after adding them.' : 'You can\'t change this transaction.';
            throw new PortalException('NOT_AUTHORIZED').withError(reason);
        }
        return t;
    }

    /** An active account in the family that the caller may post to. */
    public static Financial_Account__c usableAccount(UserContext ctx, Id accountId) {
        if (accountId == null) {
            throw new PortalException('VALIDATION').withError('Choose an account.');
        }
        Financial_Account__c a = new AccountSelector(ctx).byId(accountId);
        LedgerScope scope = new LedgerScope(ctx);
        if (!scope.canSeeAccount(a)) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        if (!scope.canUseAccount(a)) {
            throw new PortalException('NOT_AUTHORIZED').withError('You can\'t record transactions on that account.');
        }
        if (a.Status__c != 'Active') {
            throw new PortalException('VALIDATION').withError('That account is closed.');
        }
        return a;
    }

    private static void assertAccountFits(String type, Financial_Account__c a) {
        if (type == 'Income' && LedgerUtil.isLiability(a.Type__c)) {
            throw new PortalException('VALIDATION').withError('Income goes into a bank, cash or wallet account, not a card or loan.');
        }
        if (a.Type__c == 'Loan') {
            throw new PortalException('VALIDATION').withError('Loan balances change through transfers and EMI payments, not entries.');
        }
    }

    private static Category__c entryCategory(UserContext ctx, String type, Id categoryId) {
        if (categoryId == null) {
            throw new PortalException('VALIDATION').withError('Choose a category.');
        }
        Category__c c = CategoryService.ensureSeeded(ctx).byId(categoryId);
        String expected = type == 'Income' ? 'Income' : 'Expense';
        if (c.Kind__c != expected) {
            throw new PortalException('VALIDATION').withError('Choose an ' + expected.toLowerCase() + ' category for this entry.');
        }
        if (c.Active__c != true) {
            throw new PortalException('VALIDATION').withError('That category is hidden. Choose another one.');
        }
        return c;
    }

    private static void applyDetails(Transaction__c t, Map<String, Object> body) {
        if (LedgerUtil.has(body, 'payee')) {
            t.Payee__c = LedgerUtil.limited(LedgerUtil.text(body, 'payee'), 120, 'Payee');
        }
        if (LedgerUtil.has(body, 'notes')) {
            t.Notes__c = LedgerUtil.limited(LedgerUtil.text(body, 'notes'), 255, 'Notes');
        }
        if (LedgerUtil.has(body, 'referenceNo')) {
            t.Reference_No__c = LedgerUtil.limited(LedgerUtil.text(body, 'referenceNo'), 60, 'Reference');
        }
        if (LedgerUtil.has(body, 'paymentMode')) {
            t.Payment_Mode__c = mode(LedgerUtil.text(body, 'paymentMode'));
        }
    }

    public static String mode(String value) {
        if (value != null && !LedgerUtil.PAYMENT_MODES.contains(value)) {
            throw new PortalException('VALIDATION').withError('Choose a payment mode from the list.');
        }
        return value;
    }
}
