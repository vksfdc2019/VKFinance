/** Reviewed statement rows are staged once, then posted in small asynchronous batches. */
public without sharing class StatementImportService {
    public static final Integer MAX_ROWS = 500;
    public static final String FIELDS = 'Member__c, Account__c, File_Name__c, Status__c, Total__c, Imported__c, Duplicates__c, Failed__c, Job_Id__c, Error__c, CreatedDate';

    public static Statement_Import__c find(UserContext ctx, Id importId, Boolean lockRow) {
        Statement_Import__c item = (Statement_Import__c) EnhancementService.record(ctx, 'Statement_Import__c', FIELDS, importId, lockRow);
        // Imports are personal staging records even for administrators.
        if (item.Member__c != ctx.userId) throw new PortalException('NOT_FOUND');
        Financial_Account__c a = new AccountSelector(ctx).byId(item.Account__c);
        if (!new LedgerScope(ctx).canSeeAccount(a)) throw new PortalException('NOT_FOUND');
        return item;
    }

    public static List<Map<String, Object>> listImports(UserContext ctx) {
        EnhancementService.requireFeature(ctx, 'IMPORTS', 'READ');
        Set<Id> accounts = new AccountSelector(ctx).visibleIds();
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Statement_Import__c item : (List<Statement_Import__c>) Database.queryWithBinds('SELECT ' + FIELDS +
            ' FROM Statement_Import__c WHERE Family__c = :fid AND Member__c = :me AND Account__c IN :accounts ORDER BY CreatedDate DESC LIMIT 30',
            new Map<String, Object>{ 'fid' => ctx.familyId, 'me' => ctx.userId, 'accounts' => accounts }, AccessLevel.SYSTEM_MODE)) result.add(dto(item));
        return result;
    }

    public static Map<String, Object> detail(UserContext ctx, Id importId) {
        EnhancementService.requireFeature(ctx, 'IMPORTS', 'READ');
        Statement_Import__c item = find(ctx, importId, false);
        Map<String, Object> result = dto(item);
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Statement_Row__c row : [SELECT Id, Row_No__c, Entry_JSON__c, Status__c, Error__c, Transaction__c FROM Statement_Row__c
            WHERE Family__c = :ctx.familyId AND Import__c = :importId WITH SYSTEM_MODE ORDER BY Row_No__c LIMIT 500]) {
            rows.add(new Map<String, Object>{ 'id' => row.Id, 'row' => row.Row_No__c, 'entry' => JSON.deserializeUntyped(row.Entry_JSON__c),
                'status' => row.Status__c, 'error' => row.Error__c, 'transactionId' => row.Transaction__c });
        }
        result.put('rows', rows);
        return result;
    }

    public static Map<String, Object> stage(UserContext ctx, Map<String, Object> body) {
        EnhancementService.requireFeature(ctx, 'IMPORTS', 'CREATE');
        AccessGuard.require(ctx, 'TRANSACTIONS', 'CREATE');
        Id accountId = VkfRest.toId(LedgerUtil.text(body, 'accountId'));
        Financial_Account__c account = TransactionService.usableAccount(ctx, accountId);
        Object raw = body.get('rows');
        if (!(raw instanceof List<Object>) || ((List<Object>) raw).isEmpty() || ((List<Object>) raw).size() > MAX_ROWS)
            throw EnhancementService.invalid('Review between 1 and 500 rows per import.');
        EnhancementService.lockFamily(ctx);
        DateTime recent = DateTime.now().addDays(-1);
        if ([SELECT COUNT() FROM Statement_Import__c WHERE Family__c = :ctx.familyId AND CreatedDate >= :recent WITH SYSTEM_MODE] >= 20)
            throw EnhancementService.invalid('Your family has reached the daily limit of 20 imports. Please try again tomorrow.');
        if ([SELECT COUNT() FROM Statement_Import__c WHERE Family__c = :ctx.familyId AND Member__c = :ctx.userId AND Status__c IN ('Draft','Processing') WITH SYSTEM_MODE] >= 3)
            throw EnhancementService.invalid('Finish or cancel an existing import first (maximum three active imports).');
        Statement_Import__c batch = new Statement_Import__c(Family__c = ctx.familyId, Member__c = ctx.userId, Account__c = accountId,
            File_Name__c = EnhancementService.title(body, 'fileName', 120), Status__c = 'Draft', Total__c = ((List<Object>) raw).size(),
            Imported__c = 0, Duplicates__c = 0, Failed__c = 0);
        insert as system batch;
        List<Statement_Row__c> rows = new List<Statement_Row__c>();
        CategorySelector categories = new CategorySelector(ctx);
        Integer position = 0;
        for (Object entry : (List<Object>) raw) {
            if (!(entry instanceof Map<String, Object>)) throw EnhancementService.invalid('Every row must be an object.');
            Map<String, Object> row = clean(ctx, account, categories, (Map<String, Object>) entry);
            rows.add(new Statement_Row__c(Family__c = ctx.familyId, Import__c = batch.Id, Row_No__c = ++position,
                Entry_JSON__c = JSON.serialize(row), Fingerprint__c = fingerprint(ctx.familyId, accountId, row), Status__c = 'Pending'));
        }
        insert as system rows;
        AuditService.log(ctx, 'STATEMENT_STAGED', 'Statement_Import__c', batch.Id, String.valueOf(rows.size()) + ' reviewed rows');
        return dto(batch);
    }

    public static Map<String, Object> startImport(UserContext ctx, Id importId, Boolean shouldCancel) {
        EnhancementService.requireFeature(ctx, 'IMPORTS', 'CREATE');
        Statement_Import__c batch = find(ctx, importId, true);
        if (shouldCancel) {
            if (batch.Status__c == 'Processing') throw new PortalException('CONFLICT').withError('Wait for this import to finish before removing its pending work.');
            if (batch.Status__c != 'Draft' && batch.Status__c != 'Partial') throw new PortalException('CONFLICT');
            batch.Status__c = 'Cancelled';
        } else {
            if (batch.Status__c == 'Processing' || batch.Status__c == 'Completed') return dto(batch);
            if (batch.Status__c != 'Draft' && batch.Status__c != 'Partial') throw new PortalException('CONFLICT');
            TransactionService.usableAccount(ctx, batch.Account__c);
            List<Statement_Row__c> retry = [SELECT Id FROM Statement_Row__c WHERE Family__c = :ctx.familyId AND Import__c = :importId AND Status__c = 'Failed' WITH SYSTEM_MODE];
            for (Statement_Row__c row : retry) { row.Status__c = 'Pending'; row.Error__c = null; }
            update as system retry;
            batch.Status__c = 'Processing'; batch.Error__c = null;
            batch.Job_Id__c = Database.executeBatch(new StatementImportWorker(batch.Id), 3);
        }
        update as system batch;
        AuditService.log(ctx, shouldCancel ? 'STATEMENT_CANCELLED' : 'STATEMENT_STARTED', 'Statement_Import__c', batch.Id, null);
        return dto(batch);
    }

    private static Map<String, Object> clean(UserContext ctx, Financial_Account__c account, CategorySelector categories, Map<String, Object> body) {
        String type = LedgerUtil.text(body, 'type');
        if (!TransactionService.ENTRY_TYPES.contains(type)) throw EnhancementService.invalid('Only reviewed income, expense and refund rows can be imported. Record transfers and card payments with the transfer workflow.');
        if (LedgerUtil.isLiability(account.Type__c) && (account.Type__c != 'Credit Card' || type == 'Income')) throw EnhancementService.invalid('Card credits must be reviewed as refunds. Use the loan payment workflow for loans.');
        Category__c category = categories.byId(VkfRest.toId(LedgerUtil.text(body, 'categoryId')));
        if (category.Active__c != true || category.Kind__c != (type == 'Income' ? 'Income' : 'Expense')) throw EnhancementService.invalid('Choose an active category matching every row.');
        return new Map<String, Object>{ 'accountId' => account.Id, 'type' => type, 'categoryId' => category.Id,
            'amount' => LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount'),
            'date' => String.valueOf(LedgerUtil.txnDate(LedgerUtil.dateValue(body, 'date', 'Date'))),
            'payee' => LedgerUtil.limited(LedgerUtil.text(body, 'payee'), 120, 'Description'),
            'referenceNo' => LedgerUtil.limited(LedgerUtil.text(body, 'referenceNo'), 60, 'Reference'),
            'notes' => LedgerUtil.limited(LedgerUtil.text(body, 'notes'), 255, 'Notes') };
    }

    @TestVisible
    private static String fingerprint(Id familyId, Id accountId, Map<String, Object> entry) {
        List<String> parts = new List<String>{ String.valueOf(familyId), String.valueOf(accountId), String.valueOf(entry.get('date')),
            String.valueOf(entry.get('type')), String.valueOf(((Decimal) entry.get('amount')).setScale(2)),
            normalized((String) entry.get('referenceNo')), normalized((String) entry.get('payee')) };
        return TokenService.hash(JSON.serialize(parts));
    }

    private static String normalized(String value) { return value == null ? '' : value.trim().toLowerCase().replaceAll('\\s+', ' '); }

    public static Map<String, Object> dto(Statement_Import__c batch) {
        return new Map<String, Object>{ 'id' => batch.Id, 'fileName' => batch.File_Name__c, 'accountId' => batch.Account__c,
            'status' => batch.Status__c, 'total' => batch.Total__c, 'imported' => batch.Imported__c,
            'duplicates' => batch.Duplicates__c, 'failed' => batch.Failed__c, 'error' => batch.Error__c, 'createdAt' => batch.CreatedDate };
    }
}
