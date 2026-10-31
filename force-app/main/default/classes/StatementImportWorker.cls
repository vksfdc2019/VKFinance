/** Scope three bounds governor usage while retaining existing transaction business rules. */
public without sharing class StatementImportWorker implements Database.Batchable<SObject> {
    private Id importId;
    public StatementImportWorker(Id importId) { this.importId = importId; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id, Import__c, Family__c, Entry_JSON__c, Fingerprint__c, Status__c
            FROM Statement_Row__c WHERE Import__c = :importId AND Status__c = 'Pending' WITH SYSTEM_MODE]);
    }

    public void execute(Database.BatchableContext bc, List<Statement_Row__c> scope) {
        Statement_Import__c batch = [SELECT Id, Family__c, Member__c, Status__c FROM Statement_Import__c WHERE Id = :importId WITH SYSTEM_MODE FOR UPDATE];
        if (batch.Status__c != 'Processing') return;
        UserContext ctx = SystemContext.forMember(batch.Member__c);
        for (Statement_Row__c row : scope) {
            Savepoint sp = Database.setSavepoint();
            try {
                if (ctx == null || ctx.familyId != batch.Family__c || ctx.status != 'Active') throw new PortalException('NOT_AUTHORIZED');
                EnhancementService.requireFeature(ctx, 'IMPORTS', 'CREATE');
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(row.Entry_JSON__c);
                Map<String, Object> binds = new Map<String, Object>{ 'fid' => batch.Family__c, 'key' => row.Fingerprint__c,
                    'accountId' => VkfRest.toId((String) body.get('accountId')), 'day' => Date.valueOf((String) body.get('date')),
                    'amount' => LedgerUtil.dec(body, 'amount', 'Amount'), 'type' => (String) body.get('type') };
                String reference = LedgerUtil.text(body, 'referenceNo'), payee = LedgerUtil.text(body, 'payee');
                String manualMatch = '';
                if (String.isNotBlank(reference) || String.isNotBlank(payee)) {
                    manualMatch = ' OR (Account__c = :accountId AND Txn_Date__c = :day AND Amount__c = :amount AND Type__c = :type AND Status__c != \'Void\' AND ' +
                        (String.isNotBlank(reference) ? 'Reference_No__c = :match' : 'Payee__c = :match') + ')';
                    binds.put('match', String.isNotBlank(reference) ? reference : payee);
                }
                List<Transaction__c> duplicate = (List<Transaction__c>) Database.queryWithBinds(
                    'SELECT Id FROM Transaction__c WHERE Family__c = :fid AND (Import_Key__c = :key' + manualMatch + ') LIMIT 1', binds, AccessLevel.SYSTEM_MODE);
                if (!duplicate.isEmpty()) {
                    row.Status__c = 'Duplicate'; row.Transaction__c = duplicate[0].Id;
                } else {
                    FinanceDtos.Txn txn = TransactionService.createTransaction(ctx, body);
                    update as system new Transaction__c(Id = txn.id, Import_Key__c = row.Fingerprint__c, Source__c = 'Import');
                    row.Status__c = 'Imported'; row.Transaction__c = txn.id;
                }
                row.Error__c = null;
            } catch (Exception e) {
                Database.rollback(sp);
                row.Status__c = 'Failed'; row.Transaction__c = null;
                row.Error__c = e instanceof PortalException && !((PortalException) e).errors.isEmpty() ? ((PortalException) e).errors[0].left(255) :
                    'This row could not be imported. Check permissions, account status and category, then retry.';
            }
            Database.releaseSavepoint(sp);
            update as system row;
        }
    }

    public void finish(Database.BatchableContext bc) {
        Statement_Import__c batch = [SELECT Id, Family__c, Member__c, Job_Id__c FROM Statement_Import__c WHERE Id = :importId WITH SYSTEM_MODE FOR UPDATE];
        Map<String, Integer> totals = new Map<String, Integer>();
        for (AggregateResult ar : [SELECT Status__c state, COUNT(Id) n FROM Statement_Row__c WHERE Import__c = :importId AND Family__c = :batch.Family__c WITH SYSTEM_MODE GROUP BY Status__c])
            totals.put((String) ar.get('state'), (Integer) ar.get('n'));
        batch.Imported__c = totals.containsKey('Imported') ? totals.get('Imported') : 0;
        batch.Duplicates__c = totals.containsKey('Duplicate') ? totals.get('Duplicate') : 0;
        batch.Failed__c = (totals.containsKey('Failed') ? totals.get('Failed') : 0) + (totals.containsKey('Pending') ? totals.get('Pending') : 0);
        batch.Status__c = batch.Failed__c > 0 ? 'Partial' : 'Completed';
        if (batch.Failed__c > 0) batch.Error__c = 'Review the failed rows and retry. Successful rows will not be posted again.';
        update as system batch;
        AuditService.log(batch.Family__c, batch.Member__c, 'STATEMENT_FINISHED', 'Statement_Import__c', batch.Id, batch.Status__c);
        NotificationService.notify(batch.Family__c, new Set<Id>{ batch.Member__c }, new NotificationService.Message('STATEMENT_IMPORT', 'info',
            'Statement import ' + batch.Status__c.toLowerCase(), String.valueOf(batch.Imported__c) + ' imported; ' + batch.Duplicates__c + ' duplicates; ' + batch.Failed__c + ' to review.',
            '/enhancements/imports', 'IMPORT:' + batch.Id + ':' + Datetime.now().getTime()));
    }
}