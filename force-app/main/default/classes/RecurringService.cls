/**
 * Repeating entries - salary on the 1st, rent on the 3rd, SIP on the 10th. Auto-post rules
 * post themselves; Suggest rules ask their owner to confirm. Posting runs as the rule's
 * owner through the normal services, so all permission and account checks still apply.
 */
public without sharing class RecurringService {
    public static final List<String> FREQUENCIES = new List<String>{ 'Weekly', 'Monthly', 'Quarterly', 'Yearly' };
    public static final Integer MAX_CATCH_UP = 3;

    public static Date advance(Date d, String frequency) {
        switch on frequency {
            when 'Weekly' {
                return d.addDays(7);
            }
            when 'Quarterly' {
                return d.addMonths(3);
            }
            when 'Yearly' {
                return d.addMonths(12);
            }
            when else {
                return d.addMonths(1);
            }
        }
    }

    public static List<CommitmentDtos.Rule> listRules(UserContext ctx) {
        AccessGuard.require(ctx, 'RECURRING', 'READ');
        Map<Id, Category__c> categories = new CategorySelector(ctx).byIdMap();
        List<CommitmentDtos.Rule> result = new List<CommitmentDtos.Rule>();
        for (Recurring_Rule__c r : new CommitmentSelector(ctx).rules(ctx.isAdmin() ? null : ctx.userId)) {
            result.add(dto(ctx, r, categories));
        }
        return result;
    }

    public static CommitmentDtos.Rule createRule(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'RECURRING', 'CREATE');
        Recurring_Rule__c r = new Recurring_Rule__c(Family__c = ctx.familyId, Active__c = true, Frequency__c = 'Monthly', Mode__c = 'Suggest');
        applyFields(ctx, r, body, true);
        insert as system r;
        AuditService.log(ctx, 'RECURRING_CREATED', 'Recurring_Rule__c', r.Id, r.Name);
        return dto(ctx, new CommitmentSelector(ctx).ruleById(r.Id), new CategorySelector(ctx).byIdMap());
    }

    public static CommitmentDtos.Rule updateRule(UserContext ctx, Id ruleId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'RECURRING', 'EDIT');
        Recurring_Rule__c existing = editable(ctx, ruleId);
        Recurring_Rule__c r = existing.clone(true, true, false, false);
        applyFields(ctx, r, body, false);
        update as system new Recurring_Rule__c(
            Id = r.Id, Name = r.Name, Type__c = r.Type__c, Amount__c = r.Amount__c, Account__c = r.Account__c, To_Account__c = r.To_Account__c,
            Category__c = r.Category__c, Payee__c = r.Payee__c, Payment_Mode__c = r.Payment_Mode__c, Frequency__c = r.Frequency__c,
            Next_Run_Date__c = r.Next_Run_Date__c, End_Date__c = r.End_Date__c, Mode__c = r.Mode__c, Active__c = r.Active__c, Member__c = r.Member__c
        );
        AuditService.log(ctx, 'RECURRING_UPDATED', 'Recurring_Rule__c', r.Id, String.join(new List<String>(body.keySet()), ','));
        return dto(ctx, new CommitmentSelector(ctx).ruleById(r.Id), new CategorySelector(ctx).byIdMap());
    }

    /** Posts the next occurrence now (confirming a suggestion), then moves the rule on. */
    public static CommitmentDtos.Rule postNow(UserContext ctx, Id ruleId, Boolean skip) {
        AccessGuard.require(ctx, 'RECURRING', 'EDIT');
        Recurring_Rule__c r = editable(ctx, ruleId);
        if (r.Active__c != true || r.Next_Run_Date__c == null) {
            throw new PortalException('CONFLICT').withError('This rule is paused or finished.');
        }
        if (!skip) {
            post(ctx, r, Date.today() < r.Next_Run_Date__c ? Date.today() : r.Next_Run_Date__c);
        }
        moveOn(r);
        AuditService.log(ctx, skip ? 'RECURRING_SKIPPED' : 'RECURRING_POSTED', 'Recurring_Rule__c', r.Id, r.Name);
        return dto(ctx, new CommitmentSelector(ctx).ruleById(r.Id), new CategorySelector(ctx).byIdMap());
    }

    /** Daily: post due Auto-post rules (catching up a few missed runs) and remind about suggestions. */
    public static Integer runDue(Id familyId, Date today) {
        Integer posted = 0;
        for (Recurring_Rule__c r : [
            SELECT Id, Name, Family__c, Member__c, Type__c, Amount__c, Account__c, To_Account__c, Category__c, Payee__c, Payment_Mode__c,
                Frequency__c, Next_Run_Date__c, End_Date__c, Mode__c, Active__c
            FROM Recurring_Rule__c
            WHERE Family__c = :familyId AND Active__c = TRUE AND Next_Run_Date__c <= :today
            WITH SYSTEM_MODE
            LIMIT 200
        ]) {
            UserContext owner = SystemContext.forMember(r.Member__c);
            if (r.Mode__c == 'Suggest' || owner == null) {
                NotificationService.notify(familyId, new Set<Id>{ r.Member__c }, new NotificationService.Message(
                    'RECURRING_CONFIRM', 'info', 'Confirm ' + r.Name, 'Due ' + r.Next_Run_Date__c.format() + ' · tap to post or skip.',
                    '/recurring', 'REC:' + r.Id + ':' + r.Next_Run_Date__c
                ));
                continue;
            }
            Savepoint sp = Database.setSavepoint();
            try {
                for (Integer i = 0; i < MAX_CATCH_UP && r.Active__c && r.Next_Run_Date__c <= today; i++) {
                    post(owner, r, r.Next_Run_Date__c);
                    moveOn(r);
                    posted++;
                }
            } catch (Exception e) {
                Database.rollback(sp);
                NotificationService.notify(familyId, new Set<Id>{ r.Member__c }, new NotificationService.Message(
                    'RECURRING_FAILED', 'warning', r.Name + ' could not post', String.valueOf(e.getMessage()).left(200), '/recurring',
                    'RECFAIL:' + r.Id + ':' + r.Next_Run_Date__c
                ));
            }
        }
        return posted;
    }

    private static void post(UserContext ctx, Recurring_Rule__c r, Date onDate) {
        Map<String, Object> body = new Map<String, Object>{
            'amount' => r.Amount__c, 'date' => String.valueOf(onDate), 'notes' => 'Recurring: ' + r.Name, 'paymentMode' => r.Payment_Mode__c
        };
        Id postedId;
        if (r.Type__c == 'Transfer') {
            body.put('fromAccountId', r.Account__c);
            body.put('toAccountId', r.To_Account__c);
            postedId = TransferService.createTransfer(ctx, body).outLeg.id;
        } else {
            body.put('type', r.Type__c);
            body.put('accountId', r.Account__c);
            body.put('categoryId', r.Category__c);
            body.put('payee', r.Payee__c);
            postedId = TransactionService.createTransaction(ctx, body).id;
        }
        update as system new Transaction__c(Id = postedId, Recurring_Rule__c = r.Id, Source__c = 'Recurring');
    }

    private static void moveOn(Recurring_Rule__c r) {
        Date ran = r.Next_Run_Date__c;
        Date next = advance(ran, r.Frequency__c);
        Boolean finished = r.End_Date__c != null && next > r.End_Date__c;
        r.Next_Run_Date__c = finished ? null : next;
        r.Active__c = !finished;
        update as system new Recurring_Rule__c(Id = r.Id, Last_Run_Date__c = ran, Next_Run_Date__c = r.Next_Run_Date__c, Active__c = r.Active__c);
    }

    private static Recurring_Rule__c editable(UserContext ctx, Id ruleId) {
        Recurring_Rule__c r = new CommitmentSelector(ctx).ruleById(ruleId);
        if (!ctx.isAdmin() && r.Member__c != ctx.userId) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        return r;
    }

    private static void applyFields(UserContext ctx, Recurring_Rule__c r, Map<String, Object> body, Boolean creating) {
        List<String> errors = new List<String>();
        if (creating || LedgerUtil.has(body, 'name')) {
            r.Name = LedgerUtil.text(body, 'name');
            if (String.isBlank(r.Name) || r.Name.length() > 80) {
                errors.add('Name is required (up to 80 characters).');
            }
        }
        if (creating || LedgerUtil.has(body, 'type')) {
            r.Type__c = LedgerUtil.text(body, 'type');
            if (r.Type__c != 'Expense' && r.Type__c != 'Income' && r.Type__c != 'Transfer') {
                errors.add('Type must be Expense, Income or Transfer.');
            }
        }
        if (creating || LedgerUtil.has(body, 'amount')) {
            r.Amount__c = LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount');
        }
        if (creating || LedgerUtil.has(body, 'accountId')) {
            r.Account__c = TransactionService.usableAccount(ctx, VkfRest.toId(LedgerUtil.text(body, 'accountId'))).Id;
        }
        if (r.Type__c == 'Transfer') {
            if (creating || LedgerUtil.has(body, 'toAccountId')) {
                Id toId = VkfRest.toId(LedgerUtil.text(body, 'toAccountId'));
                r.To_Account__c = toId == null ? null : new AccountSelector(ctx).byId(toId).Id;
            }
            if (r.To_Account__c == null || r.To_Account__c == r.Account__c) {
                errors.add('Choose a different account to transfer to.');
            }
            r.Category__c = null;
        } else if (creating || LedgerUtil.has(body, 'categoryId')) {
            Category__c c = CategoryService.ensureSeeded(ctx).byId(VkfRest.toId(LedgerUtil.text(body, 'categoryId')));
            if (c.Kind__c != (r.Type__c == 'Income' ? 'Income' : 'Expense')) {
                errors.add('Choose a category that matches the type.');
            }
            r.Category__c = c.Id;
            r.To_Account__c = null;
        }
        if (LedgerUtil.has(body, 'payee')) {
            r.Payee__c = LedgerUtil.limited(LedgerUtil.text(body, 'payee'), 120, 'Payee');
        }
        if (LedgerUtil.has(body, 'paymentMode')) {
            r.Payment_Mode__c = TransactionService.mode(LedgerUtil.text(body, 'paymentMode'));
        }
        if (LedgerUtil.has(body, 'frequency')) {
            r.Frequency__c = LedgerUtil.text(body, 'frequency');
            if (!FREQUENCIES.contains(r.Frequency__c)) {
                errors.add('Choose how often it repeats.');
            }
        }
        if (creating || LedgerUtil.has(body, 'nextRunDate')) {
            r.Next_Run_Date__c = LedgerUtil.dateValue(body, 'nextRunDate', 'Next date');
            if (r.Next_Run_Date__c == null) {
                errors.add('Choose the next date.');
            }
        }
        if (LedgerUtil.has(body, 'endDate')) {
            r.End_Date__c = LedgerUtil.dateValue(body, 'endDate', 'End date');
        }
        if (LedgerUtil.has(body, 'mode')) {
            r.Mode__c = LedgerUtil.text(body, 'mode');
            if (r.Mode__c != 'Auto-post' && r.Mode__c != 'Suggest') {
                errors.add('Mode must be Auto-post or Suggest.');
            }
        }
        if (LedgerUtil.has(body, 'active')) {
            r.Active__c = LedgerUtil.bool(body, 'active');
        }
        if (creating) {
            r.Member__c = new LedgerScope(ctx).memberFor(VkfRest.toId(LedgerUtil.text(body, 'memberId')), new PortalUserSelector(ctx));
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }
    }

    private static CommitmentDtos.Rule dto(UserContext ctx, Recurring_Rule__c r, Map<Id, Category__c> categories) {
        CommitmentDtos.Rule d = new CommitmentDtos.Rule();
        d.id = r.Id;
        d.name = r.Name;
        d.type = r.Type__c;
        d.amount = r.Amount__c;
        d.accountId = r.Account__c;
        d.accountName = r.Account__r?.Name;
        d.toAccountId = r.To_Account__c;
        d.toAccountName = r.To_Account__r?.Name;
        d.categoryId = r.Category__c;
        Category__c c = categories.get(r.Category__c);
        if (c != null) {
            FinanceDtos.Category view = FinanceDtos.category(c, categories);
            d.categoryName = c.Name;
            d.icon = view.icon;
            d.color = view.color;
        } else if (r.Type__c == 'Transfer') {
            d.icon = 'arrow-left-right';
            d.color = '#0f766e';
        }
        d.payee = r.Payee__c;
        d.paymentMode = r.Payment_Mode__c;
        d.frequency = r.Frequency__c;
        d.nextRunDate = r.Next_Run_Date__c;
        d.endDate = r.End_Date__c;
        d.mode = r.Mode__c;
        d.active = r.Active__c;
        d.lastRunDate = r.Last_Run_Date__c;
        d.memberId = r.Member__c;
        d.memberName = r.Member__c == null ? null : FinanceDtos.personName(r.Member__r?.First_Name__c, r.Member__r?.Last_Name__c);
        d.canEdit = AccessGuard.can(ctx, 'RECURRING', 'EDIT') && (ctx.isAdmin() || r.Member__c == ctx.userId);
        return d;
    }
}