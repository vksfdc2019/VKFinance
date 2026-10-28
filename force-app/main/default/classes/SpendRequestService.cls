/** Approval is separate from recording an expense. Only an explicit record action posts money. */
public without sharing class SpendRequestService {
    private static final String FIELDS = 'Name, Title__c, Amount__c, Child__c, Child__r.First_Name__c, Account__c, Account__r.Name, ' +
        'Category__c, Category__r.Name, Status__c, Note__c, Decision_Note__c, Decided_At__c, Valid_Until__c, Transaction__c, CreatedDate';

    private static Spend_Request__c find(UserContext ctx, Id requestId, Boolean lockRow) {
        Spend_Request__c r = (Spend_Request__c) EnhancementService.record(ctx, 'Spend_Request__c', FIELDS, requestId, lockRow);
        if (!ctx.isAdmin() && r.Child__c != ctx.userId) throw new PortalException('NOT_FOUND');
        return r;
    }

    public static List<Map<String, Object>> listRequests(UserContext ctx) {
        EnhancementService.requireFeature(ctx, 'REQUESTS', 'READ');
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Spend_Request__c r : (List<Spend_Request__c>) Database.queryWithBinds('SELECT ' + FIELDS +
            ' FROM Spend_Request__c WHERE Family__c = :fid' + (ctx.isAdmin() ? '' : ' AND Child__c = :me') +
            ' ORDER BY CreatedDate DESC LIMIT 100', new Map<String, Object>{ 'fid' => ctx.familyId, 'me' => ctx.userId }, AccessLevel.SYSTEM_MODE)) result.add(dto(r));
        return result;
    }

    public static Map<String, Object> create(UserContext ctx, Map<String, Object> body) {
        EnhancementService.requireFeature(ctx, 'REQUESTS', 'CREATE');
        if (ctx.role != 'Child') throw new PortalException('NOT_AUTHORIZED');
        Financial_Account__c account = TransactionService.usableAccount(ctx, VkfRest.toId(LedgerUtil.text(body, 'accountId')));
        if (account.Owner_Member__c != ctx.userId || LedgerUtil.isLiability(account.Type__c)) throw EnhancementService.invalid('Choose your own cash, bank or wallet account.');
        Category__c category = new CategorySelector(ctx).byId(VkfRest.toId(LedgerUtil.text(body, 'categoryId')));
        if (category.Kind__c != 'Expense' || category.Active__c == false) throw EnhancementService.invalid('Choose an active expense category.');
        Date expiry = LedgerUtil.dateValue(body, 'validUntil', 'Valid until');
        if (expiry == null) expiry = Date.today().addDays(7);
        if (expiry < Date.today() || expiry > Date.today().addDays(90)) throw EnhancementService.invalid('Choose a date within the next 90 days.');
        EnhancementService.lockFamily(ctx);
        Date today = Date.today();
        if ([SELECT COUNT() FROM Spend_Request__c WHERE Family__c = :ctx.familyId AND Child__c = :ctx.userId AND Status__c = 'Pending' AND Valid_Until__c >= :today WITH SYSTEM_MODE] >= 20)
            throw EnhancementService.invalid('You already have 20 pending requests.');
        Spend_Request__c r = new Spend_Request__c(Family__c = ctx.familyId, Child__c = ctx.userId,
            Title__c = EnhancementService.title(body, 'title', 120), Amount__c = LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount'),
            Account__c = account.Id, Category__c = category.Id, Status__c = 'Pending', Valid_Until__c = expiry,
            Note__c = LedgerUtil.limited(LedgerUtil.text(body, 'note'), 255, 'Note'));
        insert as system r;
        NotificationService.notify(ctx.familyId, SystemContext.adminIds(ctx.familyId), new NotificationService.Message('SPEND_REQUEST', 'info',
            'A spend request needs your review', r.Title__c, '/enhancements/requests', 'REQUEST:' + r.Id));
        AuditService.log(ctx, 'SPEND_REQUEST_CREATED', 'Spend_Request__c', r.Id, null);
        return dto(find(ctx, r.Id, false));
    }

    public static Map<String, Object> act(UserContext ctx, Id requestId, String action, Map<String, Object> body) {
        String permission = action == 'approve' || action == 'decline' ? 'APPROVE' : action == 'cancel' ? 'CANCEL' : 'READ';
        EnhancementService.requireFeature(ctx, 'REQUESTS', permission);
        Spend_Request__c r = find(ctx, requestId, true);
        if (action == 'record') {
            if (r.Status__c == 'Recorded') return dto(r); // Safe retry of the same explicit action.
            if (r.Status__c != 'Approved' || r.Valid_Until__c < Date.today()) throw new PortalException('CONFLICT').withError('This request is not currently approved.');
            FinanceDtos.Txn txn = TransactionService.createTransaction(ctx, new Map<String, Object>{ 'type' => 'Expense', 'amount' => r.Amount__c,
                'accountId' => r.Account__c, 'categoryId' => r.Category__c, 'memberId' => r.Child__c, 'date' => String.valueOf(Date.today()),
                'payee' => r.Title__c, 'notes' => 'Approved spend request ' + r.Name });
            r.Transaction__c = txn.id; r.Status__c = 'Recorded';
        } else if (action == 'cancel') {
            if (r.Child__c != ctx.userId || (r.Status__c != 'Pending' && r.Status__c != 'Approved')) throw new PortalException('CONFLICT');
            r.Status__c = 'Cancelled';
        } else if (action == 'approve' || action == 'decline') {
            if (!ctx.isAdmin()) throw new PortalException('NOT_AUTHORIZED');
            if (r.Status__c != 'Pending' || r.Valid_Until__c < Date.today()) throw new PortalException('CONFLICT').withError('Only a current pending request can be decided.');
            r.Status__c = action == 'approve' ? 'Approved' : 'Declined';
            r.Decided_By__c = ctx.userId; r.Decided_At__c = Datetime.now();
            r.Decision_Note__c = LedgerUtil.limited(LedgerUtil.text(body, 'note'), 255, 'Decision note');
        } else throw new PortalException('NOT_FOUND');
        update as system r;
        NotificationService.notify(ctx.familyId, new Set<Id>{ r.Child__c }, new NotificationService.Message('SPEND_DECISION', 'info',
            'Spend request: ' + r.Status__c, r.Title__c, '/enhancements/requests', 'REQUEST:' + r.Id + ':' + r.Status__c));
        AuditService.log(ctx, 'SPEND_REQUEST_' + r.Status__c.toUpperCase(), 'Spend_Request__c', r.Id, null);
        return dto(r);
    }

    private static Map<String, Object> dto(Spend_Request__c r) {
        return new Map<String, Object>{ 'id' => r.Id, 'title' => r.Title__c, 'amount' => r.Amount__c, 'childId' => r.Child__c,
            'childName' => r.Child__r?.First_Name__c, 'accountName' => r.Account__r?.Name, 'categoryName' => r.Category__r?.Name,
            'status' => r.Status__c, 'note' => r.Note__c, 'decisionNote' => r.Decision_Note__c, 'validUntil' => r.Valid_Until__c,
            'transactionId' => r.Transaction__c, 'expired' => r.Valid_Until__c < Date.today(), 'createdAt' => r.CreatedDate };
    }
}
