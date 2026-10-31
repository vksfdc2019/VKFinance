/**
 * Financial accounts: bank, cash, wallets, credit cards, loans, deposits. Members manage
 * their own accounts; admins manage every account in the family. Balances are kept by
 * LedgerBalances - this service only ever moves them through the opening balance or an
 * Adjustment entry, so the ledger always explains the balance.
 */
public without sharing class AccountService {
    public static final List<String> TYPES = new List<String>{
        'Savings', 'Current', 'Cash', 'UPI Wallet', 'Credit Card', 'Loan', 'Fixed Deposit', 'Recurring Deposit', 'Investment'
    };
    public static final Set<String> COLORS = new Set<String>{
        'teal', 'emerald', 'sky', 'indigo', 'violet', 'rose', 'amber', 'orange', 'slate', 'zinc'
    };
    private static final Pattern LAST4 = Pattern.compile('^\\d{4}$');

    public static List<FinanceDtos.Account> listAccounts(UserContext ctx, Boolean includeClosed) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'READ');
        return toDtos(ctx, new AccountSelector(ctx).visible(includeClosed));
    }

    /** Every active account a transfer can go to, without balances - e.g. pocket money to a child's wallet. */
    public static List<FinanceDtos.AccountRef> transferTargets(UserContext ctx) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'CREATE');
        List<FinanceDtos.AccountRef> result = new List<FinanceDtos.AccountRef>();
        for (Financial_Account__c a : new AccountSelector(ctx).inFamily(false)) {
            if (a.Type__c != 'Loan') {
                result.add(FinanceDtos.accountRef(a));
            }
        }
        return result;
    }

    public static List<FinanceDtos.Account> toDtos(UserContext ctx, List<Financial_Account__c> accounts) {
        LedgerScope scope = new LedgerScope(ctx);
        Date today = Date.today();
        Map<Id, FinanceDtos.CardCycle> cycles = new Map<Id, FinanceDtos.CardCycle>();
        Date earliest;
        for (Financial_Account__c a : accounts) {
            if (a.Type__c == 'Credit Card') {
                FinanceDtos.CardCycle cycle = cardCycle(a, today);
                cycles.put(a.Id, cycle);
                earliest = earliest == null || cycle.lastStatementDate < earliest ? cycle.lastStatementDate : earliest;
            }
        }
        if (!cycles.isEmpty()) {
            Set<Id> cardIds = cycles.keySet();
            Id fid = ctx.familyId;
            Map<Id, Decimal> paidByCard = new Map<Id, Decimal>();
            for (Transaction__c t : [
                SELECT Account__c, Txn_Date__c, Amount__c, Direction__c, Type__c
                FROM Transaction__c
                WHERE Family__c = :fid AND Account__c IN :cardIds AND Status__c != 'Void' AND Txn_Date__c > :earliest
                WITH SYSTEM_MODE
                LIMIT 10000
            ]) {
                FinanceDtos.CardCycle cycle = cycles.get(t.Account__c);
                if (t.Txn_Date__c <= cycle.lastStatementDate) {
                    continue;
                }
                if (t.Direction__c == 'Debit') {
                    cycle.cycleSpend += t.Amount__c;
                } else if (CardStatementService.PAYMENT_TYPES.contains(t.Type__c)) {
                    paidByCard.put(t.Account__c, LedgerUtil.zeroIfNull(paidByCard.get(t.Account__c)) + t.Amount__c);
                }
            }
            CardStatementService.attachLatest(cycles, paidByCard, today);
            BillService.attachCardBills(ctx, cycles, today);
        }
        List<FinanceDtos.Account> result = new List<FinanceDtos.Account>();
        for (Financial_Account__c a : accounts) {
            FinanceDtos.Account d = FinanceDtos.account(a, scope);
            FinanceDtos.CardCycle cycle = cycles.get(a.Id);
            if (cycle != null) {
                if (a.Credit_Limit__c != null && a.Credit_Limit__c > 0) {
                    cycle.available = a.Credit_Limit__c - d.balance;
                    cycle.utilisationPct = (d.balance / a.Credit_Limit__c * 100).setScale(1, RoundingMode.HALF_UP);
                }
                d.card = cycle;
            }
            result.add(d);
        }
        CreditLimitGroupService.attach(ctx, result);
        DepositService.attach(ctx, result);
        return result;
    }

    /** Billing cycle from the statement day (clamped to month end); due date follows the last statement. */
    public static FinanceDtos.CardCycle cardCycle(Financial_Account__c a, Date today) {
        Integer day = a.Statement_Day__c == null ? 1 : a.Statement_Day__c.intValue();
        Date thisMonth = clampedDay(today.year(), today.month(), day);
        FinanceDtos.CardCycle c = new FinanceDtos.CardCycle();
        if (today > thisMonth) {
            c.lastStatementDate = thisMonth;
            Date next = today.addMonths(1);
            c.nextStatementDate = clampedDay(next.year(), next.month(), day);
        } else {
            Date prev = today.addMonths(-1);
            c.lastStatementDate = clampedDay(prev.year(), prev.month(), day);
            c.nextStatementDate = thisMonth;
        }
        Integer dueDays = a.Payment_Due_Days__c == null ? 20 : a.Payment_Due_Days__c.intValue();
        c.dueDate = c.lastStatementDate.addDays(dueDays);
        if (c.dueDate < today) {
            c.dueDate = c.nextStatementDate.addDays(dueDays);
        }
        c.cycleSpend = 0;
        return c;
    }

    private static Date clampedDay(Integer year, Integer month, Integer day) {
        return Date.newInstance(year, month, Math.min(day, Date.daysInMonth(year, month)));
    }

    public static FinanceDtos.Account createAccount(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'CREATE');
        AccountSelector selector = new AccountSelector(ctx);
        if (selector.countAccounts() >= 100) {
            throw new PortalException('CONFLICT').withError('Your family has reached the limit of 100 accounts.');
        }
        String type = LedgerUtil.text(body, 'type');
        if (!TYPES.contains(type)) {
            throw new PortalException('VALIDATION').withError('Choose an account type.');
        }
        Financial_Account__c a = new Financial_Account__c(
            Family__c = ctx.familyId,
            Type__c = type,
            Status__c = 'Active',
            Opening_Date__c = Date.today(),
            Opening_Balance__c = 0,
            Sort_Order__c = selector.countAccounts() + 1
        );
        a.Owner_Member__c = ctx.userId;
        applyFields(ctx, a, body, true);
        if (LedgerUtil.has(body, 'ownerId') && ctx.isAdmin()) {
            Id ownerId = VkfRest.toId(LedgerUtil.text(body, 'ownerId'));
            a.Owner_Member__c = ownerId == null ? null : new PortalUserSelector(ctx).memberInFamily(ownerId).Id;
        }
        a.Current_Balance__c = a.Opening_Balance__c;
        insert as system a;
        AuditService.log(ctx, 'ACCOUNT_CREATED', 'Financial_Account__c', a.Id, type);
        return toDtos(ctx, new List<Financial_Account__c>{ selector.byId(a.Id) })[0];
    }

    public static FinanceDtos.Account updateAccount(UserContext ctx, Id accountId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        AccountSelector selector = new AccountSelector(ctx);
        Financial_Account__c existing = manageable(ctx, selector, accountId);
        Financial_Account__c a = existing.clone(true, true, false, false);

        String type = LedgerUtil.text(body, 'type');
        if (type != null && type != existing.Type__c) {
            if (!TYPES.contains(type)) {
                throw new PortalException('VALIDATION').withError('Choose an account type.');
            }
            if (LedgerUtil.isLiability(type) != LedgerUtil.isLiability(existing.Type__c) && selector.hasTransactions(existing.Id)) {
                throw new PortalException('VALIDATION')
                    .withError('This account has transactions, so it can\'t switch between money you have and money you owe.');
            }
            if (DepositService.TYPES.contains(existing.Type__c) && [SELECT COUNT() FROM Deposit__c WHERE Account__c = :existing.Id WITH SYSTEM_MODE] > 0) {
                throw new PortalException('VALIDATION').withError('This account holds deposit terms, so its type can\'t change. Close the deposit instead.');
            }
            a.Type__c = type;
        }
        if (existing.Credit_Limit_Group__c != null && a.Type__c != 'Credit Card') {
            throw new PortalException('VALIDATION').withError('Remove the card from its shared limit before changing its type.');
        }
        if (existing.Credit_Limit_Group__c != null && LedgerUtil.has(body, 'creditLimit')) {
            throw new PortalException('VALIDATION').withError('Edit the shared limit in Shared credit limits. The independent limit is preserved for when this card leaves the group.');
        }
        applyFields(ctx, a, body, false);
        if (LedgerUtil.has(body, 'ownerId')) {
            if (!ctx.isAdmin()) {
                throw new PortalException('NOT_AUTHORIZED').withError('Only an admin can change an account\'s owner.');
            }
            Id ownerId = VkfRest.toId(LedgerUtil.text(body, 'ownerId'));
            a.Owner_Member__c = ownerId == null ? null : new PortalUserSelector(ctx).memberInFamily(ownerId).Id;
        }
        Decimal openingChange = LedgerUtil.zeroIfNull(a.Opening_Balance__c) - LedgerUtil.zeroIfNull(existing.Opening_Balance__c);
        Decimal balance = existing.Current_Balance__c == null ? LedgerUtil.zeroIfNull(existing.Opening_Balance__c) : existing.Current_Balance__c;

        String status = LedgerUtil.text(body, 'status');
        if (status != null && status != existing.Status__c) {
            if (status != 'Active' && status != 'Closed') {
                throw new PortalException('VALIDATION').withError('Status must be Active or Closed.');
            }
            if (status == 'Closed' && balance + openingChange != 0) {
                throw new PortalException('VALIDATION')
                    .withError('Bring the balance to zero before closing - transfer the money out or reconcile the account.');
            }
            a.Status__c = status;
        }

        Financial_Account__c changes = new Financial_Account__c(
            Id = a.Id,
            Name = a.Name,
            Type__c = a.Type__c,
            Institution__c = a.Institution__c,
            Last4__c = a.Last4__c,
            Opening_Balance__c = a.Opening_Balance__c,
            Opening_Date__c = a.Opening_Date__c,
            Credit_Limit__c = a.Credit_Limit__c,
            Statement_Day__c = a.Statement_Day__c,
            Payment_Due_Days__c = a.Payment_Due_Days__c,
            Min_Due_Pct__c = a.Min_Due_Pct__c,
            Is_Shared__c = a.Is_Shared__c,
            Status__c = a.Status__c,
            Color__c = a.Color__c,
            Owner_Member__c = a.Owner_Member__c
        );
        if (openingChange != 0) {
            changes.Current_Balance__c = balance + openingChange;
        }
        update as system changes;
        if (a.Type__c != existing.Type__c) {
            LedgerBalances.recalculate(new Set<Id>{ a.Id });
        }
        AuditService.log(ctx, 'ACCOUNT_UPDATED', 'Financial_Account__c', a.Id, String.join(new List<String>(body.keySet()), ','));
        return toDtos(ctx, new List<Financial_Account__c>{ selector.byId(a.Id) })[0];
    }

    /** Posts an Adjustment so the balance matches the bank or card statement. */
    public static FinanceDtos.Account reconcile(UserContext ctx, Id accountId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        AccountSelector selector = new AccountSelector(ctx);
        Financial_Account__c a = manageable(ctx, selector, accountId);
        if (a.Status__c != 'Active') {
            throw new PortalException('VALIDATION').withError('That account is closed.');
        }
        Decimal actual = LedgerUtil.dec(body, 'actualBalance', 'Actual balance');
        if (actual == null || actual.abs() > LedgerUtil.MAX_AMOUNT) {
            throw new PortalException('VALIDATION').withError('Enter the balance shown by your bank or card.');
        }
        actual = actual.setScale(2, RoundingMode.HALF_UP);
        Decimal current = a.Current_Balance__c == null ? LedgerUtil.zeroIfNull(a.Opening_Balance__c) : a.Current_Balance__c;
        Decimal diff = actual - current;
        if (diff != 0) {
            Boolean liability = LedgerUtil.isLiability(a.Type__c);
            // Assets go up with a Credit; liabilities (money owed) go up with a Debit.
            String direction = (diff > 0) != liability ? 'Credit' : 'Debit';
            Date d = LedgerUtil.dateValue(body, 'date', 'Date');
            Category__c adjustment = CategoryService.ensureSeeded(ctx).systemCategory('ADJUSTMENT');
            Transaction__c t = new Transaction__c(
                Family__c = ctx.familyId,
                Account__c = a.Id,
                Member__c = ctx.userId,
                Category__c = adjustment?.Id,
                Type__c = 'Adjustment',
                Direction__c = direction,
                Amount__c = diff.abs(),
                Txn_Date__c = LedgerUtil.txnDate(d == null ? Date.today() : d),
                Payee__c = 'Balance adjustment',
                Notes__c = LedgerUtil.limited(LedgerUtil.text(body, 'note'), 255, 'Note'),
                Status__c = 'Cleared',
                Source__c = 'Manual'
            );
            insert as system t;
            AuditService.log(ctx, 'ACCOUNT_RECONCILED', 'Financial_Account__c', a.Id, current + ' -> ' + actual);
        }
        return toDtos(ctx, new List<Financial_Account__c>{ selector.byId(a.Id) })[0];
    }

    public static Financial_Account__c manageable(UserContext ctx, AccountSelector selector, Id accountId) {
        Financial_Account__c a = selector.byId(accountId);
        LedgerScope scope = new LedgerScope(ctx);
        if (!scope.canSeeAccount(a)) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        if (!scope.canManageAccount(a)) {
            throw new PortalException('NOT_AUTHORIZED').withError('Only the account\'s owner or a family admin can change it.');
        }
        return a;
    }

    private static void applyFields(UserContext ctx, Financial_Account__c a, Map<String, Object> body, Boolean creating) {
        if (LedgerUtil.has(body, 'creditLimitGroupId')) {
            throw new PortalException('VALIDATION').withError('Use Shared credit limits to change group membership.');
        }
        List<String> errors = new List<String>();
        if (creating || LedgerUtil.has(body, 'name')) {
            String name = LedgerUtil.text(body, 'name');
            if (String.isBlank(name) || name.length() > 80) {
                errors.add('Name is required (up to 80 characters).');
            }
            a.Name = name;
        }
        if (LedgerUtil.has(body, 'institution')) {
            a.Institution__c = LedgerUtil.text(body, 'institution');
            if (a.Institution__c != null && a.Institution__c.length() > 80) {
                errors.add('Bank or provider can be up to 80 characters.');
            }
        }
        if (LedgerUtil.has(body, 'last4')) {
            a.Last4__c = LedgerUtil.text(body, 'last4');
            if (a.Last4__c != null && !LAST4.matcher(a.Last4__c).matches()) {
                errors.add('Enter only the last 4 digits - never the full number.');
            }
        }
        if (LedgerUtil.has(body, 'openingBalance')) {
            Decimal opening = LedgerUtil.dec(body, 'openingBalance', 'Opening balance');
            if (opening != null && opening.abs() > LedgerUtil.MAX_AMOUNT) {
                errors.add('Opening balance is too large.');
            }
            a.Opening_Balance__c = opening == null ? 0 : opening.setScale(2, RoundingMode.HALF_UP);
        }
        if (LedgerUtil.has(body, 'openingDate')) {
            Date d = LedgerUtil.dateValue(body, 'openingDate', 'Opening date');
            a.Opening_Date__c = d == null ? Date.today() : d;
        }
        if (LedgerUtil.has(body, 'isShared')) {
            a.Is_Shared__c = LedgerUtil.bool(body, 'isShared');
        }
        if (LedgerUtil.has(body, 'color')) {
            String c = LedgerUtil.text(body, 'color');
            if (c != null && !COLORS.contains(c)) {
                errors.add('Choose one of the offered colours.');
            }
            a.Color__c = c;
        }
        if (a.Type__c == 'Credit Card') {
            if (LedgerUtil.has(body, 'creditLimit')) {
                a.Credit_Limit__c = LedgerUtil.dec(body, 'creditLimit', 'Credit limit');
            }
            if (a.Credit_Limit__c == null || a.Credit_Limit__c <= 0 || a.Credit_Limit__c > LedgerUtil.MAX_AMOUNT) {
                errors.add('Credit limit must be more than zero.');
            }
            if (LedgerUtil.has(body, 'statementDay')) {
                a.Statement_Day__c = LedgerUtil.dec(body, 'statementDay', 'Statement day');
            }
            if (a.Statement_Day__c == null || a.Statement_Day__c < 1 || a.Statement_Day__c > 31) {
                errors.add('Statement day must be between 1 and 31.');
            }
            if (LedgerUtil.has(body, 'paymentDueDays')) {
                a.Payment_Due_Days__c = LedgerUtil.dec(body, 'paymentDueDays', 'Payment due days');
            }
            if (a.Payment_Due_Days__c == null) {
                a.Payment_Due_Days__c = 20;
            }
            if (a.Payment_Due_Days__c < 1 || a.Payment_Due_Days__c > 60) {
                errors.add('Payment due days must be between 1 and 60.');
            }
            if (LedgerUtil.has(body, 'minDuePct')) {
                a.Min_Due_Pct__c = LedgerUtil.dec(body, 'minDuePct', 'Minimum due %');
            }
            if (a.Min_Due_Pct__c == null) {
                a.Min_Due_Pct__c = 5;
            }
            if (a.Min_Due_Pct__c < 0 || a.Min_Due_Pct__c > 100) {
                errors.add('Minimum due % must be between 0 and 100.');
            }
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }
    }
}