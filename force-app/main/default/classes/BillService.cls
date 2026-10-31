/**
 * Recurring bills and their due occurrences. Paying posts a Bill Payment expense from the
 * chosen account; a linked credit-card bill posts a transfer instead. Then the bill rolls
 * forward to its next due date. Members see and pay only the bills assigned to them.
 */
public without sharing class BillService {
    public static final List<String> FREQUENCIES = new List<String>{ 'Monthly', 'Bi-monthly', 'Quarterly', 'Half-yearly', 'Yearly', 'One-time' };

    public static Date nextDate(Date d, String frequency) {
        switch on frequency {
            when 'Monthly' {
                return d.addMonths(1);
            }
            when 'Bi-monthly' {
                return d.addMonths(2);
            }
            when 'Quarterly' {
                return d.addMonths(3);
            }
            when 'Half-yearly' {
                return d.addMonths(6);
            }
            when 'Yearly' {
                return d.addMonths(12);
            }
            when else {
                return null;
            }
        }
    }

    public static String statusFor(Bill_Instance__c i, Date today) {
        if (i.Status__c == 'Paid' || i.Status__c == 'Skipped') {
            return i.Status__c;
        }
        if (LedgerUtil.zeroIfNull(i.Amount_Paid__c) > 0) {
            return 'Partially Paid';
        }
        if (i.Due_Date__c < today) {
            return 'Overdue';
        }
        return i.Due_Date__c <= today.addDays(7) ? 'Due' : 'Upcoming';
    }

    private static Id scopeMember(UserContext ctx) {
        return new LedgerScope(ctx).wholeFamily() ? null : ctx.userId;
    }

    public static CommitmentDtos.BillsView listBills(UserContext ctx) {
        AccessGuard.require(ctx, 'BILLS', 'READ');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        List<Bill__c> bills = selector.bills(scopeMember(ctx));
        Map<Id, Bill__c> byId = new Map<Id, Bill__c>(bills);
        Map<Id, Category__c> categories = new CategorySelector(ctx).byIdMap();
        CommitmentDtos.BillsView v = new CommitmentDtos.BillsView();
        v.canEdit = AccessGuard.can(ctx, 'BILLS', 'EDIT');
        Date today = Date.today();

        Map<Id, Decimal> paidByBill = new Map<Id, Decimal>();
        for (Bill_Instance__c i : selector.instances(byId.keySet(), new Set<String>{ 'Paid', 'Partially Paid' }, null)) {
            if (i.Paid_On__c != null && i.Paid_On__c >= today.addMonths(-12)) {
                paidByBill.put(i.Bill__c, (paidByBill.containsKey(i.Bill__c) ? paidByBill.get(i.Bill__c) : 0) + LedgerUtil.zeroIfNull(i.Amount_Paid__c));
            }
            if (i.Status__c == 'Paid' && i.Paid_On__c != null && i.Paid_On__c >= today.addDays(-45)) {
                v.recentlyPaid.add(instance(ctx, i, byId.get(i.Bill__c), categories));
            }
        }
        for (Bill__c b : bills) {
            CommitmentDtos.Bill d = bill(b, categories);
            d.paidLast12Months = paidByBill.containsKey(b.Id) ? paidByBill.get(b.Id) : 0;
            v.bills.add(d);
        }
        for (Bill_Instance__c i : selector.instances(byId.keySet(), CommitmentSelector.OPEN_BILL, today.addDays(90))) {
            CommitmentDtos.BillInstance d = instance(ctx, i, byId.get(i.Bill__c), categories);
            v.open.add(d);
            Decimal left = LedgerUtil.zeroIfNull(i.Amount_Due__c) - LedgerUtil.zeroIfNull(i.Amount_Paid__c);
            if (d.status == 'Overdue') {
                v.overdue += left;
            } else if (i.Due_Date__c <= today.addDays(30)) {
                v.dueNext30 += left;
            }
        }
        return v;
    }

    public static CommitmentDtos.Bill createBill(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'BILLS', 'CREATE');
        Bill__c b = new Bill__c(Family__c = ctx.familyId, Active__c = true, Frequency__c = 'Monthly', Reminder_Days__c = 3);
        applyFields(ctx, b, body, true);
        insert as system b;
        ensureOpenInstance(b);
        AuditService.log(ctx, 'BILL_CREATED', 'Bill__c', b.Id, b.Name);
        return bill(new CommitmentSelector(ctx).billById(b.Id), new CategorySelector(ctx).byIdMap());
    }

    public static CommitmentDtos.Bill updateBill(UserContext ctx, Id billId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'BILLS', 'EDIT');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        Bill__c existing = selector.billById(billId);
        Bill__c b = existing.clone(true, true, false, false);
        applyFields(ctx, b, body, false);
        update as system new Bill__c(
            Id = b.Id, Name = b.Name, Category__c = b.Category__c, Consumer_No__c = b.Consumer_No__c, Frequency__c = b.Frequency__c,
            Next_Due_Date__c = b.Next_Due_Date__c, Expected_Amount__c = b.Expected_Amount__c, Pay_From_Account__c = b.Pay_From_Account__c,
            Credit_Card_Account__c = b.Credit_Card_Account__c,
            Auto_Pay__c = b.Auto_Pay__c, Reminder_Days__c = b.Reminder_Days__c, Responsible_Member__c = b.Responsible_Member__c, Active__c = b.Active__c
        );
        // An unpaid, untouched occurrence follows the bill's new due date and amount.
        List<Bill_Instance__c> open = selector.instances(new Set<Id>{ b.Id }, new Set<String>{ 'Upcoming', 'Due', 'Overdue' }, null);
        if (b.Active__c != true) {
            delete as system open;
        } else if (!open.isEmpty() && LedgerUtil.zeroIfNull(open[0].Amount_Paid__c) == 0) {
            update as system new Bill_Instance__c(Id = open[0].Id, Due_Date__c = b.Next_Due_Date__c, Amount_Due__c = b.Expected_Amount__c);
        } else {
            ensureOpenInstance(b);
        }
        AuditService.log(ctx, 'BILL_UPDATED', 'Bill__c', b.Id, String.join(new List<String>(body.keySet()), ','));
        return bill(selector.billById(b.Id), new CategorySelector(ctx).byIdMap());
    }

    /** Pays (part of) a due occurrence from an account the caller can use. */
    public static CommitmentDtos.BillInstance payInstance(UserContext ctx, Id instanceId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'BILLS', 'PAY');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        // Serialize payments so simultaneous submissions cannot settle the same bill twice.
        List<Bill_Instance__c> locked = [SELECT Id FROM Bill_Instance__c WHERE Id = :instanceId AND Family__c = :ctx.familyId WITH SYSTEM_MODE FOR UPDATE];
        Bill_Instance__c i = selector.instanceById(instanceId);
        Bill__c b = visibleBill(ctx, selector, i.Bill__c);
        if (!CommitmentSelector.OPEN_BILL.contains(i.Status__c)) {
            throw new PortalException('CONFLICT').withError('This bill is already ' + i.Status__c.toLowerCase() + '.');
        }
        Decimal remaining = LedgerUtil.zeroIfNull(i.Amount_Due__c) - LedgerUtil.zeroIfNull(i.Amount_Paid__c);
        Decimal amount = LedgerUtil.has(body, 'amount') ? LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount') : remaining;
        if (amount == null || amount <= 0) {
            throw new PortalException('VALIDATION').withError('Enter the amount you paid.');
        }
        Id accountId = LedgerUtil.has(body, 'accountId') ? VkfRest.toId(LedgerUtil.text(body, 'accountId')) : b.Pay_From_Account__c;
        Financial_Account__c account = TransactionService.usableAccount(ctx, accountId);
        if (account.Type__c == 'Loan') {
            throw new PortalException('VALIDATION').withError('Pay bills from a bank, cash, wallet or card account.');
        }
        Date paidOn = LedgerUtil.txnDate(LedgerUtil.has(body, 'date') ? LedgerUtil.dateValue(body, 'date', 'Date') : Date.today());

        if (b.Credit_Card_Account__c != null) {
            if (LedgerUtil.isLiability(account.Type__c)) {
                throw new PortalException('VALIDATION').withError('Pay a credit-card bill from a bank, cash or wallet account.');
            }
            if (amount > remaining) {
                throw new PortalException('VALIDATION').withError('The payment exceeds the remaining bill amount.');
            }
            FinanceDtos.Transfer payment = TransferService.createTransfer(ctx, new Map<String, Object>{
                'fromAccountId' => account.Id, 'toAccountId' => b.Credit_Card_Account__c,
                'amount' => amount, 'date' => String.valueOf(paidOn),
                'paymentMode' => LedgerUtil.text(body, 'paymentMode'), 'notes' => LedgerUtil.text(body, 'notes')
            }, i.Id);
            if (LedgerUtil.bool(body, 'auto')) {
                update as system new List<Transaction__c>{
                    new Transaction__c(Id = payment.outLeg.id, Source__c = 'Auto-pay'),
                    new Transaction__c(Id = payment.inLeg.id, Source__c = 'Auto-pay')
                };
            }
            return instance(ctx, selector.instanceById(i.Id), b, new CategorySelector(ctx).byIdMap());
        }
        insert as system new Transaction__c(
            Family__c = ctx.familyId, Account__c = account.Id, Category__c = b.Category__c, Type__c = 'Bill Payment', Direction__c = 'Debit',
            Amount__c = amount, Txn_Date__c = paidOn, Payee__c = b.Name.left(120), Member__c = ctx.userId, Bill_Instance__c = i.Id,
            Payment_Mode__c = TransactionService.mode(LedgerUtil.text(body, 'paymentMode')),
            Notes__c = LedgerUtil.limited(LedgerUtil.text(body, 'notes'), 255, 'Notes'), Status__c = 'Cleared',
            Source__c = LedgerUtil.bool(body, 'auto') ? 'Auto-pay' : 'Manual'
        );
        Decimal paid = LedgerUtil.zeroIfNull(i.Amount_Paid__c) + amount;
        Boolean settled = paid >= LedgerUtil.zeroIfNull(i.Amount_Due__c);
        update as system new Bill_Instance__c(Id = i.Id, Amount_Paid__c = paid, Paid_On__c = paidOn, Status__c = settled ? 'Paid' : 'Partially Paid');
        if (settled) {
            rollForward(b, i.Due_Date__c);
        }
        AuditService.log(ctx, 'BILL_PAID', 'Bill_Instance__c', i.Id, b.Name + ' ' + amount);
        return instance(ctx, selector.instanceById(i.Id), b, new CategorySelector(ctx).byIdMap());
    }

    public static void skipInstance(UserContext ctx, Id instanceId) {
        AccessGuard.require(ctx, 'BILLS', 'EDIT');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        Bill_Instance__c i = selector.instanceById(instanceId);
        Bill__c b = selector.billById(i.Bill__c);
        if (!CommitmentSelector.OPEN_BILL.contains(i.Status__c) || LedgerUtil.zeroIfNull(i.Amount_Paid__c) > 0) {
            throw new PortalException('CONFLICT').withError('Only an unpaid bill can be skipped.');
        }
        update as system new Bill_Instance__c(Id = i.Id, Status__c = 'Skipped');
        rollForward(b, i.Due_Date__c);
        AuditService.log(ctx, 'BILL_SKIPPED', 'Bill_Instance__c', i.Id, b.Name);
    }

    /** Allocate a normal card transfer to the oldest open linked bill, or the occurrence being paid. */
    public static void recordCardPayment(UserContext ctx, Id cardId, Id debitId, Id creditId, Decimal amount, Date paidOn, Id requestedInstanceId) {
        Set<String> open = CommitmentSelector.OPEN_BILL;
        List<Bill_Instance__c> rows = [
            SELECT Id, Bill__c, Due_Date__c, Amount_Due__c, Amount_Paid__c, Status__c
            FROM Bill_Instance__c
            WHERE Family__c = :ctx.familyId AND Bill__r.Family__c = :ctx.familyId
                AND Bill__r.Credit_Card_Account__c = :cardId AND Status__c IN :open
                AND (Bill__r.Active__c = true OR Id = :requestedInstanceId)
            WITH SYSTEM_MODE FOR UPDATE
        ];
        Bill_Instance__c chosen;
        for (Bill_Instance__c row : rows) {
            if (requestedInstanceId != null && row.Id != requestedInstanceId) continue;
            if (row.Amount_Due__c == null || row.Amount_Due__c <= LedgerUtil.zeroIfNull(row.Amount_Paid__c)) continue;
            if (chosen == null || row.Due_Date__c < chosen.Due_Date__c) chosen = row;
        }
        if (chosen == null) {
            if (requestedInstanceId != null) throw new PortalException('CONFLICT').withError('This card bill is no longer open.');
            return;
        }
        Decimal allocated = Math.min(amount, chosen.Amount_Due__c - LedgerUtil.zeroIfNull(chosen.Amount_Paid__c));
        update as system new List<Transaction__c>{
            new Transaction__c(Id = debitId, Bill_Instance__c = chosen.Id, Bill_Payment_Amount__c = allocated),
            new Transaction__c(Id = creditId, Bill_Instance__c = chosen.Id, Bill_Payment_Amount__c = allocated)
        };
        chosen.Amount_Paid__c = LedgerUtil.zeroIfNull(chosen.Amount_Paid__c) + allocated;
        chosen.Paid_On__c = paidOn;
        chosen.Status__c = chosen.Amount_Paid__c >= chosen.Amount_Due__c ? 'Paid' : 'Partially Paid';
        update as system chosen;
        if (chosen.Status__c == 'Paid') rollForward(new CommitmentSelector(ctx).billById(chosen.Bill__c), chosen.Due_Date__c);
        AuditService.log(ctx, 'BILL_PAID', 'Bill_Instance__c', chosen.Id, 'Card payment ' + allocated);
    }

    /** The linked bill overrides the estimated ledger statement without changing either balance. */
    public static void attachCardBills(UserContext ctx, Map<Id, FinanceDtos.CardCycle> cycles, Date today) {
        Set<Id> cardIds = cycles.keySet();
        Map<Id, Bill_Instance__c> selected = new Map<Id, Bill_Instance__c>();
        for (Bill_Instance__c row : [
            SELECT Id, Bill__c, Bill__r.Credit_Card_Account__c, Due_Date__c, Amount_Due__c, Amount_Paid__c, Paid_On__c, Status__c
            FROM Bill_Instance__c
            WHERE Family__c = :ctx.familyId AND Bill__r.Family__c = :ctx.familyId
                AND Bill__r.Credit_Card_Account__c IN :cardIds AND Status__c != 'Skipped'
                AND (Bill__r.Active__c = true OR Status__c = 'Paid')
            WITH SYSTEM_MODE
        ]) {
            Id cardId = row.Bill__r.Credit_Card_Account__c;
            Bill_Instance__c current = selected.get(cardId);
            Integer rank = cardBillRank(row, today);
            Integer currentRank = current == null ? 99 : cardBillRank(current, today);
            if (current == null || rank < currentRank || (rank == currentRank &&
                (row.Status__c == 'Paid' ? row.Due_Date__c > current.Due_Date__c : row.Due_Date__c < current.Due_Date__c))) {
                selected.put(cardId, row);
            }
        }
        for (Id cardId : selected.keySet()) {
            Bill_Instance__c row = selected.get(cardId);
            FinanceDtos.CardBill bill = new FinanceDtos.CardBill();
            bill.billId = row.Bill__c; bill.instanceId = row.Id;
            bill.amount = row.Amount_Due__c; bill.amountPaid = LedgerUtil.zeroIfNull(row.Amount_Paid__c);
            bill.dueDate = row.Due_Date__c; bill.status = statusFor(row, today);
            cycles.get(cardId).bill = bill;
        }
    }

    private static Integer cardBillRank(Bill_Instance__c row, Date today) {
        Date monthStart = today.toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        if (row.Status__c != 'Paid') {
            if (row.Due_Date__c <= today) return 0;
            return row.Due_Date__c <= monthEnd ? 1 : 3;
        }
        Boolean currentMonth = row.Due_Date__c >= monthStart && row.Due_Date__c <= monthEnd;
        Boolean paidThisMonth = row.Paid_On__c != null && row.Paid_On__c >= monthStart && row.Paid_On__c <= monthEnd;
        return currentMonth || paidThisMonth ? 2 : 4;
    }

    /** Called when a bill payment is voided: the occurrence owes that money again. */
    public static void revertPayment(Transaction__c t) {
        // Both transfer legs carry the bill reference, but its allocation is reversed only once.
        if (t.Type__c == 'Card Payment' && t.Direction__c == 'Credit') return;
        List<Bill_Instance__c> rows = [
            SELECT Id, Bill__c, Bill__r.Frequency__c, Bill__r.Credit_Card_Account__c, Amount_Due__c, Amount_Paid__c, Due_Date__c, Status__c
            FROM Bill_Instance__c
            WHERE Id = :t.Bill_Instance__c
            WITH SYSTEM_MODE
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            return;
        }
        Bill_Instance__c i = rows[0];
        i.Amount_Paid__c = Math.max(0, LedgerUtil.zeroIfNull(i.Amount_Paid__c) - (t.Bill_Payment_Amount__c == null ? t.Amount__c : t.Bill_Payment_Amount__c));
        i.Status__c = 'Due';
        i.Status__c = statusFor(i, Date.today());
        if (i.Amount_Paid__c == 0) {
            i.Paid_On__c = null;
        }
        update as system i;
        if (i.Bill__r.Credit_Card_Account__c != null && i.Bill__r.Frequency__c == 'One-time') {
            update as system new Bill__c(Id = i.Bill__c, Active__c = true);
        }
    }

    /** Daily: make sure every active bill has one open occurrence and statuses are current. */
    public static void refresh(Id familyId, Date today) {
        List<Bill__c> bills = [
            SELECT Id, Name, Frequency__c, Next_Due_Date__c, Expected_Amount__c, Active__c, Family__c
            FROM Bill__c
            WHERE Family__c = :familyId AND Active__c = TRUE
            WITH SYSTEM_MODE
        ];
        Set<Id> withOpen = new Set<Id>();
        List<Bill_Instance__c> changed = new List<Bill_Instance__c>();
        for (Bill_Instance__c i : [
            SELECT Id, Bill__c, Due_Date__c, Amount_Due__c, Amount_Paid__c, Status__c
            FROM Bill_Instance__c
            WHERE Family__c = :familyId AND Status__c IN :CommitmentSelector.OPEN_BILL
            WITH SYSTEM_MODE
        ]) {
            withOpen.add(i.Bill__c);
            String status = statusFor(i, today);
            if (status != i.Status__c) {
                changed.add(new Bill_Instance__c(Id = i.Id, Status__c = status));
            }
        }
        update as system changed;
        for (Bill__c b : bills) {
            if (!withOpen.contains(b.Id)) {
                ensureOpenInstance(b);
            }
        }
    }

    private static void rollForward(Bill__c b, Date fromDue) {
        Date next = nextDate(fromDue, b.Frequency__c);
        if (next == null) {
            update as system new Bill__c(Id = b.Id, Active__c = false);
            return;
        }
        b.Next_Due_Date__c = next;
        update as system new Bill__c(Id = b.Id, Next_Due_Date__c = next);
        ensureOpenInstance(b);
    }

    private static void ensureOpenInstance(Bill__c b) {
        if (b.Next_Due_Date__c == null || b.Active__c != true) {
            return;
        }
        Set<String> open = CommitmentSelector.OPEN_BILL;
        if ([SELECT COUNT() FROM Bill_Instance__c WHERE Bill__c = :b.Id AND Status__c IN :open WITH SYSTEM_MODE] > 0) {
            return;
        }
        Bill_Instance__c i = new Bill_Instance__c(
            Bill__c = b.Id,
            Family__c = b.Family__c,
            Due_Date__c = b.Next_Due_Date__c,
            Amount_Due__c = b.Expected_Amount__c,
            Amount_Paid__c = 0,
            Unique_Key__c = b.Id + '-' + String.valueOf(b.Next_Due_Date__c)
        );
        i.Status__c = statusFor(i, Date.today());
        Database.upsert(new List<Bill_Instance__c>{ i }, Bill_Instance__c.Unique_Key__c, true, AccessLevel.SYSTEM_MODE);
    }

    private static Bill__c visibleBill(UserContext ctx, CommitmentSelector selector, Id billId) {
        Bill__c b = selector.billById(billId);
        if (!new LedgerScope(ctx).wholeFamily() && b.Responsible_Member__c != ctx.userId) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        return b;
    }

    private static void applyFields(UserContext ctx, Bill__c b, Map<String, Object> body, Boolean creating) {
        List<String> errors = new List<String>();
        if (creating || LedgerUtil.has(body, 'name')) {
            b.Name = LedgerUtil.text(body, 'name');
            if (String.isBlank(b.Name) || b.Name.length() > 80) {
                errors.add('Biller name is required (up to 80 characters).');
            }
        }
        if (creating || LedgerUtil.has(body, 'categoryId')) {
            Category__c c = CategoryService.ensureSeeded(ctx).byId(VkfRest.toId(LedgerUtil.text(body, 'categoryId')));
            if (c.Kind__c != 'Expense') {
                errors.add('Choose a spending category.');
            }
            b.Category__c = c.Id;
        }
        if (LedgerUtil.has(body, 'frequency')) {
            b.Frequency__c = LedgerUtil.text(body, 'frequency');
            if (!FREQUENCIES.contains(b.Frequency__c)) {
                errors.add('Choose how often the bill comes.');
            }
        }
        if (creating || LedgerUtil.has(body, 'nextDueDate')) {
            b.Next_Due_Date__c = LedgerUtil.dateValue(body, 'nextDueDate', 'Next due date');
            if (b.Next_Due_Date__c == null) {
                errors.add('Next due date is required.');
            }
        }
        if (LedgerUtil.has(body, 'expectedAmount')) {
            Decimal amount = LedgerUtil.dec(body, 'expectedAmount', 'Expected amount');
            b.Expected_Amount__c = amount == null ? null : LedgerUtil.amount(amount, 'Expected amount');
        }
        if (LedgerUtil.has(body, 'consumerNo')) {
            b.Consumer_No__c = LedgerUtil.limited(LedgerUtil.text(body, 'consumerNo'), 40, 'Consumer number');
        }
        if (LedgerUtil.has(body, 'payFromAccountId')) {
            Id accountId = VkfRest.toId(LedgerUtil.text(body, 'payFromAccountId'));
            b.Pay_From_Account__c = accountId == null ? null : TransactionService.usableAccount(ctx, accountId).Id;
        }
        if (LedgerUtil.has(body, 'active')) {
            b.Active__c = LedgerUtil.bool(body, 'active');
        }
        if (LedgerUtil.has(body, 'creditCardAccountId')) {
            Id cardId = VkfRest.toId(LedgerUtil.text(body, 'creditCardAccountId'));
            if (b.Id != null && cardId != b.Credit_Card_Account__c &&
                [SELECT COUNT() FROM Bill_Instance__c WHERE Bill__c = :b.Id AND Amount_Paid__c > 0 WITH SYSTEM_MODE] > 0) {
                errors.add('A bill with payments cannot be moved to a different card.');
            }
            b.Credit_Card_Account__c = cardId;
        }
        if (b.Credit_Card_Account__c != null) {
            Financial_Account__c card = TransactionService.usableAccount(ctx, b.Credit_Card_Account__c);
            if (card.Type__c != 'Credit Card') errors.add('Choose a credit-card account for this bill.');
            // Lock the account before checking for another active link, including concurrent creates.
            List<Financial_Account__c> lockedCards = [SELECT Id FROM Financial_Account__c WHERE Id = :card.Id AND Family__c = :ctx.familyId WITH SYSTEM_MODE FOR UPDATE];
            if ((creating || b.Active__c) && [SELECT COUNT() FROM Bill__c WHERE Family__c = :ctx.familyId
                AND Credit_Card_Account__c = :card.Id AND Active__c = true AND Id != :b.Id WITH SYSTEM_MODE] > 0) {
                errors.add('This card already has an active bill. Edit that bill instead.');
            }
            if (b.Pay_From_Account__c != null && LedgerUtil.isLiability(new AccountSelector(ctx).byId(b.Pay_From_Account__c).Type__c)) {
                errors.add('Pay a credit-card bill from a bank, cash or wallet account.');
            }
        }
        if (LedgerUtil.has(body, 'autoPay')) {
            b.Auto_Pay__c = LedgerUtil.bool(body, 'autoPay');
        }
        if (b.Auto_Pay__c == true && (b.Pay_From_Account__c == null || b.Expected_Amount__c == null)) {
            errors.add('Auto-pay needs an account to pay from and an expected amount.');
        }
        if (LedgerUtil.has(body, 'reminderDays')) {
            Decimal days = LedgerUtil.dec(body, 'reminderDays', 'Reminder days');
            if (days == null || days < 0 || days > 15) {
                errors.add('Remind between 0 and 15 days before.');
            }
            b.Reminder_Days__c = days;
        }
        if (LedgerUtil.has(body, 'responsibleId')) {
            Id memberId = VkfRest.toId(LedgerUtil.text(body, 'responsibleId'));
            b.Responsible_Member__c = memberId == null ? null : new PortalUserSelector(ctx).memberInFamily(memberId).Id;
        } else if (creating) {
            b.Responsible_Member__c = ctx.userId;
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }
    }

    public static CommitmentDtos.Bill bill(Bill__c b, Map<Id, Category__c> categories) {
        CommitmentDtos.Bill d = new CommitmentDtos.Bill();
        d.id = b.Id;
        d.name = b.Name;
        d.categoryId = b.Category__c;
        Category__c c = categories.get(b.Category__c);
        if (c != null) {
            FinanceDtos.Category view = FinanceDtos.category(c, categories);
            d.categoryName = c.Name;
            d.icon = view.icon;
            d.color = view.color;
        }
        d.consumerNo = b.Consumer_No__c;
        d.frequency = b.Frequency__c;
        d.nextDueDate = b.Next_Due_Date__c;
        d.expectedAmount = b.Expected_Amount__c;
        d.payFromAccountId = b.Pay_From_Account__c;
        d.payFromAccountName = b.Pay_From_Account__r?.Name;
        d.creditCardAccountId = b.Credit_Card_Account__c;
        d.creditCardAccountName = b.Credit_Card_Account__r?.Name;
        d.autoPay = b.Auto_Pay__c;
        d.reminderDays = b.Reminder_Days__c == null ? null : b.Reminder_Days__c.intValue();
        d.responsibleId = b.Responsible_Member__c;
        d.responsibleName = b.Responsible_Member__c == null
            ? null
            : FinanceDtos.personName(b.Responsible_Member__r?.First_Name__c, b.Responsible_Member__r?.Last_Name__c);
        d.active = b.Active__c;
        return d;
    }

    public static CommitmentDtos.BillInstance instance(UserContext ctx, Bill_Instance__c i, Bill__c b, Map<Id, Category__c> categories) {
        CommitmentDtos.BillInstance d = new CommitmentDtos.BillInstance();
        CommitmentDtos.Bill parent = bill(b, categories);
        d.id = i.Id;
        d.billId = b.Id;
        d.billName = b.Name;
        d.categoryName = parent.categoryName;
        d.icon = parent.icon;
        d.color = parent.color;
        d.dueDate = i.Due_Date__c;
        d.amountDue = i.Amount_Due__c;
        d.amountPaid = i.Amount_Paid__c;
        d.status = statusFor(i, Date.today());
        d.autoPay = b.Auto_Pay__c;
        d.payFromAccountId = b.Pay_From_Account__c;
        d.responsibleName = parent.responsibleName;
        d.creditCardAccountId = b.Credit_Card_Account__c;
        d.daysLeft = CommitmentDtos.daysUntil(i.Due_Date__c);
        d.canPay = AccessGuard.can(ctx, 'BILLS', 'PAY') && CommitmentSelector.OPEN_BILL.contains(d.status) &&
            (new LedgerScope(ctx).wholeFamily() || b.Responsible_Member__c == ctx.userId) && ctx.role != 'Viewer';
        return d;
    }
}