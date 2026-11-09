/**
 * Savings schemes - PPF, SSY, NSC, KVP, SCSS, POMIS, Post Office TD/RD, NPS, EPF, SGB. Each sits
 * in its own Savings Scheme account, so the money is in net worth and every rupee in or out is a
 * ledger entry: deposits are transfers in, interest is income, and a valuation (NPS, SGB) is an
 * adjustment. Members see and manage their own; admins the family's.
 */
public without sharing class SavingsService {
    public static final String ACCOUNT_TYPE = 'Savings Scheme';
    public static final Set<String> STATUSES = new Set<String>{ 'Active', 'Matured', 'Closed' };

    public static SavingsDtos.Portfolio portfolio(UserContext ctx) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'READ');
        SavingsDtos.Portfolio p = new SavingsDtos.Portfolio();
        p.currencyCode = ctx.currencyCode;
        p.financialYear = DepositCalculator.financialYearLabel(Date.today());
        p.canEdit = AccessGuard.can(ctx, 'ACCOUNTS', 'EDIT');
        p.schemes = schemes(ctx, null);
        p.policies = InsuranceService.policies(ctx);
        p.taxes = TaxSavingsService.summaries(ctx, p.schemes, p.policies);
        for (SavingsDtos.Scheme s : p.schemes) {
            if (s.status == 'Active') {
                p.schemesValue += LedgerUtil.zeroIfNull(s.balance);
                p.schemesMaturityValue += s.maturityValue == null ? LedgerUtil.zeroIfNull(s.balance) : s.maturityValue;
            }
        }
        for (SavingsDtos.Policy x : p.policies) {
            if (x.status != 'Active' && x.status != 'Paid-up') {
                continue;
            }
            if (InsuranceService.HEALTH.contains(x.policyType)) {
                p.healthCover += LedgerUtil.zeroIfNull(x.sumAssured);
            } else if (InsuranceService.LIFE.contains(x.policyType)) {
                p.lifeCover += LedgerUtil.zeroIfNull(x.sumAssured);
            }
            if (x.status == 'Active') {
                p.yearlyPremiums += LedgerUtil.zeroIfNull(x.yearlyPremium);
            }
        }
        return p;
    }

    /** Schemes on accounts the caller can see; `onlyId` narrows to one. */
    public static List<SavingsDtos.Scheme> schemes(UserContext ctx, Id onlyId) {
        LedgerScope scope = new LedgerScope(ctx);
        Map<Id, Financial_Account__c> accounts = new Map<Id, Financial_Account__c>();
        for (Financial_Account__c a : new AccountSelector(ctx).visible(true)) {
            if (a.Type__c == ACCOUNT_TYPE) {
                accounts.put(a.Id, a);
            }
        }
        List<SavingsDtos.Scheme> result = new List<SavingsDtos.Scheme>();
        if (accounts.isEmpty()) {
            return result;
        }
        Id fid = ctx.familyId;
        Set<Id> accountIds = accounts.keySet();
        List<Savings_Scheme__c> rows = [
            SELECT Id, Account__c, Scheme__c, Account_Number__c, Beneficiary__c, Nominee__c, Start_Date__c, Maturity_Date__c, Tenure_Months__c,
                Rate__c, Principal__c, Planned_Contribution__c, Payout__c, Status__c, Value_As_Of__c, Notes__c
            FROM Savings_Scheme__c
            WHERE Family__c = :fid AND Account__c IN :accountIds
            WITH SYSTEM_MODE
            ORDER BY Status__c, Maturity_Date__c NULLS LAST
            LIMIT 500
        ];
        Date today = Date.today();
        Date fyStart = DepositCalculator.financialYearStart(today);
        Map<Id, Decimal> deposits = new Map<Id, Decimal>();
        Set<Id> withEntries = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Account__c a, Type__c t, SUM(Amount__c) s
            FROM Transaction__c
            WHERE Family__c = :fid AND Account__c IN :accountIds AND Status__c != 'Void'
                AND (Txn_Date__c >= :fyStart OR Type__c != 'Transfer In')
            WITH SYSTEM_MODE
            GROUP BY Account__c, Type__c
        ]) {
            Id accountId = (Id) ar.get('a');
            withEntries.add(accountId);
            if ((String) ar.get('t') == 'Transfer In') {
                deposits.put(accountId, LedgerUtil.zeroIfNull(ar.get('s')));
            }
        }
        for (Savings_Scheme__c x : rows) {
            if (onlyId != null && x.Id != onlyId) {
                continue;
            }
            Financial_Account__c a = accounts.get(x.Account__c);
            Decimal thisYear = LedgerUtil.zeroIfNull(deposits.get(a.Id));
            if (x.Start_Date__c != null && x.Start_Date__c >= fyStart) {
                thisYear += LedgerUtil.zeroIfNull(a.Opening_Balance__c);
            }
            result.add(dto(ctx, scope, x, a, thisYear, !withEntries.contains(a.Id), today));
        }
        return result;
    }

    public static SavingsDtos.Scheme get(UserContext ctx, Id schemeId) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'READ');
        List<SavingsDtos.Scheme> found = schemes(ctx, schemeId);
        if (found.isEmpty()) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that scheme.');
        }
        return found[0];
    }

    private static SavingsDtos.Scheme dto(UserContext ctx, LedgerScope scope, Savings_Scheme__c x, Financial_Account__c a, Decimal thisYear, Boolean noEntries, Date today) {
        SchemeRules.Rule rule = SchemeRules.of(x.Scheme__c);
        SavingsDtos.Scheme d = new SavingsDtos.Scheme();
        d.id = x.Id;
        d.accountId = a.Id;
        d.name = a.Name;
        d.scheme = x.Scheme__c;
        d.schemeLabel = rule == null ? x.Scheme__c : rule.label;
        d.kind = rule == null ? 'market' : rule.kind;
        d.institution = a.Institution__c;
        d.ownerId = a.Owner_Member__c;
        d.ownerName = a.Owner_Member__c == null ? null : FinanceDtos.personName(a.Owner_Member__r?.First_Name__c, a.Owner_Member__r?.Last_Name__c);
        d.canManage = scope.canManageAccount(a) && AccessGuard.can(ctx, 'ACCOUNTS', 'EDIT');
        d.accountNumberMasked = DepositDtos.mask(x.Account_Number__c);
        d.accountNumber = d.canManage ? x.Account_Number__c : d.accountNumberMasked;
        d.beneficiary = x.Beneficiary__c;
        d.nominee = x.Nominee__c;
        d.startDate = x.Start_Date__c;
        d.maturityDate = x.Maturity_Date__c;
        d.tenureMonths = x.Tenure_Months__c == null ? null : x.Tenure_Months__c.intValue();
        d.rate = x.Rate__c;
        d.principal = x.Principal__c;
        d.plannedContribution = x.Planned_Contribution__c;
        d.payout = x.Payout__c;
        d.status = x.Status__c == null ? 'Active' : x.Status__c;
        d.balance = a.Current_Balance__c == null ? LedgerUtil.zeroIfNull(a.Opening_Balance__c) : a.Current_Balance__c;
        d.valueAsOf = x.Value_As_Of__c;
        d.contributedThisYear = thisYear;
        d.taxSection = rule?.taxSection;
        if (x.Scheme__c == 'PO_TD' && (x.Tenure_Months__c == null || x.Tenure_Months__c.intValue() != 60)) {
            d.taxSection = null;
        }
        d.taxNote = rule?.taxNote;
        d.notes = x.Notes__c;
        d.maturityValue = d.status == 'Active' ? SchemeRules.maturityValue(x, d.balance, thisYear, today) : null;
        d.payoutAmount = SchemeRules.payoutAmount(x.Scheme__c, x.Principal__c, x.Rate__c);
        Date closes = SchemeRules.depositsCloseOn(x.Scheme__c, x.Start_Date__c, x.Maturity_Date__c);
        d.depositsOpen = d.status == 'Active' && rule != null && rule.kind != 'lump' && (closes == null || today <= closes);
        if (d.depositsOpen && rule.maxAmount != null && rule.kind == 'yearly') {
            d.roomThisYear = Math.max(0, rule.maxAmount - thisYear);
        }
        if (x.Start_Date__c != null && x.Maturity_Date__c != null && x.Maturity_Date__c > x.Start_Date__c) {
            Decimal done = x.Start_Date__c.daysBetween(today) * 100.0 / x.Start_Date__c.daysBetween(x.Maturity_Date__c);
            d.progressPct = Math.max(0, Math.min(100, done)).setScale(1, RoundingMode.HALF_UP);
            d.daysToMaturity = today.daysBetween(x.Maturity_Date__c);
        }
        d.canDelete = d.canManage && noEntries;
        return d;
    }

    // ------------------------------------------------------------------ writes

    /**
     * { scheme, name?, institution?, ownerId?, accountNumber?, beneficiary?, nominee?, startDate, tenureMonths?,
     *   maturityDate?, rate?, principal?, plannedContribution?, balance?, notes? } - opens the scheme's account
     * with today's balance (the amount invested for a new lump sum).
     */
    public static SavingsDtos.Scheme create(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'CREATE');
        Savings_Scheme__c x = new Savings_Scheme__c(Family__c = ctx.familyId, Status__c = 'Active');
        x.Scheme__c = LedgerUtil.text(body, 'scheme');
        SchemeRules.Rule rule = SchemeRules.of(x.Scheme__c);
        if (rule == null) {
            throw new PortalException('VALIDATION').withError('Choose a scheme.');
        }
        apply(x, rule, body, true);
        Decimal balance = LedgerUtil.has(body, 'balance') ? LedgerUtil.dec(body, 'balance', 'Current balance') : x.Principal__c;
        if (balance == null || balance < 0 || balance > LedgerUtil.MAX_AMOUNT) {
            throw new PortalException('VALIDATION').withError('Enter what the scheme holds today (0 if nothing yet).');
        }
        String name = LedgerUtil.text(body, 'name');
        Map<String, Object> account = new Map<String, Object>{
            'type' => ACCOUNT_TYPE,
            'name' => String.isBlank(name) ? (x.Scheme__c == 'OTHER' ? 'Savings scheme' : x.Scheme__c.replace('_', ' ')) : name,
            'institution' => LedgerUtil.text(body, 'institution'),
            'openingBalance' => balance,
            'openingDate' => String.valueOf(x.Start_Date__c > Date.today() ? Date.today() : x.Start_Date__c),
            'color' => 'emerald'
        };
        if (LedgerUtil.has(body, 'ownerId')) {
            account.put('ownerId', body.get('ownerId'));
        }
        FinanceDtos.Account created = AccountService.createAccount(ctx, account);
        x.Account__c = created.id;
        if (x.Value_As_Of__c == null && rule.kind == 'market') {
            x.Value_As_Of__c = Date.today();
        }
        insert as system x;
        AuditService.log(ctx, 'SCHEME_CREATED', 'Savings_Scheme__c', x.Id, x.Scheme__c);
        return get(ctx, x.Id);
    }

    /** The same fields as create, except the scheme kind and balance; name and institution rename the account. */
    public static SavingsDtos.Scheme updateScheme(UserContext ctx, Id schemeId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        Savings_Scheme__c x = editable(ctx, schemeId);
        apply(x, SchemeRules.of(x.Scheme__c), body, false);
        update as system x;
        Map<String, Object> account = new Map<String, Object>();
        for (String key : new List<String>{ 'name', 'institution' }) {
            if (LedgerUtil.has(body, key)) {
                account.put(key, body.get(key));
            }
        }
        if (!account.isEmpty()) {
            AccountService.updateAccount(ctx, x.Account__c, account);
        }
        AuditService.log(ctx, 'SCHEME_UPDATED', 'Savings_Scheme__c', x.Id, x.Scheme__c);
        return get(ctx, x.Id);
    }

    /** { fromAccountId, amount, date? } - a deposit, recorded as a transfer into the scheme. */
    public static SavingsDtos.Scheme contribute(UserContext ctx, Id schemeId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'CREATE');
        Savings_Scheme__c x = editable(ctx, schemeId);
        SavingsDtos.Scheme now = get(ctx, x.Id);
        if (now.depositsOpen != true) {
            throw new PortalException('VALIDATION').withError(
                now.kind == 'lump' ? 'A ' + now.schemeLabel + ' takes one deposit. Open a new one to invest more.' : 'This scheme no longer takes deposits.'
            );
        }
        Decimal amount = LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount');
        if (now.roomThisYear != null && amount > now.roomThisYear) {
            throw new PortalException('VALIDATION').withError(
                now.schemeLabel + ' takes at most Rs 1,50,000 in a financial year. Room left this year: Rs ' + now.roomThisYear.format() + '.'
            );
        }
        TransferService.createTransfer(ctx, new Map<String, Object>{
            'fromAccountId' => LedgerUtil.text(body, 'fromAccountId'),
            'toAccountId' => x.Account__c,
            'amount' => amount,
            'date' => onDate(body),
            'notes' => now.schemeLabel + ' deposit'
        });
        return get(ctx, x.Id);
    }

    /** { amount, date?, toAccountId? } - interest credited to the scheme, or paid out to a bank account. */
    public static SavingsDtos.Scheme creditInterest(UserContext ctx, Id schemeId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'CREATE');
        Savings_Scheme__c x = editable(ctx, schemeId);
        String to = LedgerUtil.text(body, 'toAccountId');
        Id category;
        for (Category__c c : CategoryService.ensureSeeded(ctx).all()) {
            if (c.Name == 'Interest and Dividends' && c.Kind__c == 'Income') {
                category = c.Id;
            }
        }
        TransactionService.createTransaction(ctx, new Map<String, Object>{
            'type' => 'Income',
            'amount' => LedgerUtil.dec(body, 'amount', 'Interest'),
            'accountId' => String.isBlank(to) ? String.valueOf(x.Account__c) : to,
            'categoryId' => category,
            'date' => onDate(body),
            'payee' => SchemeRules.of(x.Scheme__c).label + ' interest'
        });
        return get(ctx, x.Id);
    }

    /** { value, date? } - today's value of a market-linked scheme (NPS, SGB, EPF statement). */
    public static SavingsDtos.Scheme updateValue(UserContext ctx, Id schemeId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        Savings_Scheme__c x = editable(ctx, schemeId);
        AccountService.reconcile(ctx, x.Account__c, new Map<String, Object>{
            'actualBalance' => body.get('value'),
            'date' => onDate(body),
            'note' => SchemeRules.of(x.Scheme__c).label + ' valuation'
        });
        Date asOf = LedgerUtil.dateValue(body, 'date', 'Date');
        update as system new Savings_Scheme__c(Id = x.Id, Value_As_Of__c = asOf == null ? Date.today() : asOf);
        return get(ctx, x.Id);
    }

    /** { toAccountId?, date? } - matured or closed: the balance goes to an account and the scheme stops. */
    public static SavingsDtos.Scheme close(UserContext ctx, Id schemeId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        Savings_Scheme__c x = editable(ctx, schemeId);
        SavingsDtos.Scheme now = get(ctx, x.Id);
        if (now.status != 'Active') {
            throw new PortalException('CONFLICT').withError('This scheme is already ' + now.status.toLowerCase() + '.');
        }
        String to = LedgerUtil.text(body, 'toAccountId');
        if (now.balance > 0) {
            if (String.isBlank(to)) {
                throw new PortalException('VALIDATION').withError('Choose the account the money was paid into.');
            }
            TransferService.createTransfer(ctx, new Map<String, Object>{
                'fromAccountId' => x.Account__c, 'toAccountId' => to, 'amount' => now.balance,
                'date' => onDate(body), 'notes' => now.schemeLabel + ' closed'
            });
        }
        Date onDate = LedgerUtil.dateValue(body, 'date', 'Date');
        onDate = onDate == null ? Date.today() : onDate;
        update as system new Savings_Scheme__c(Id = x.Id, Status__c = x.Maturity_Date__c != null && onDate >= x.Maturity_Date__c ? 'Matured' : 'Closed');
        update as system new Financial_Account__c(Id = x.Account__c, Status__c = 'Closed');
        AuditService.log(ctx, 'SCHEME_CLOSED', 'Savings_Scheme__c', x.Id, x.Scheme__c);
        return get(ctx, x.Id);
    }

    /** A scheme added by mistake: only while nothing has been recorded on its account. */
    public static void deleteScheme(UserContext ctx, Id schemeId) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        Savings_Scheme__c x = editable(ctx, schemeId);
        if (new AccountSelector(ctx).hasTransactions(x.Account__c)) {
            throw new PortalException('CONFLICT').withError('This scheme has deposits or interest recorded. Close it instead.');
        }
        delete as system x;
        delete as system new Financial_Account__c(Id = x.Account__c);
        AuditService.log(ctx, 'SCHEME_DELETED', 'Savings_Scheme__c', x.Id, x.Scheme__c);
    }

    /** The date sent, or today. */
    private static String onDate(Map<String, Object> body) {
        String d = LedgerUtil.text(body, 'date');
        return String.isBlank(d) ? String.valueOf(Date.today()) : d;
    }

    private static Savings_Scheme__c editable(UserContext ctx, Id schemeId) {
        Id fid = ctx.familyId;
        List<Savings_Scheme__c> rows = [
            SELECT Id, Account__c, Scheme__c, Account_Number__c, Beneficiary__c, Nominee__c, Start_Date__c, Maturity_Date__c, Tenure_Months__c,
                Rate__c, Principal__c, Planned_Contribution__c, Payout__c, Status__c, Value_As_Of__c, Notes__c
            FROM Savings_Scheme__c
            WHERE Id = :schemeId AND Family__c = :fid
            WITH SYSTEM_MODE
        ];
        if (rows.isEmpty()) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that scheme.');
        }
        AccountService.manageable(ctx, new AccountSelector(ctx), rows[0].Account__c);
        return rows[0];
    }

    private static void apply(Savings_Scheme__c x, SchemeRules.Rule rule, Map<String, Object> body, Boolean creating) {
        List<String> errors = new List<String>();
        if (LedgerUtil.has(body, 'accountNumber')) {
            x.Account_Number__c = LedgerUtil.limited(LedgerUtil.text(body, 'accountNumber'), 40, 'Account number');
        }
        if (LedgerUtil.has(body, 'beneficiary')) {
            x.Beneficiary__c = LedgerUtil.limited(LedgerUtil.text(body, 'beneficiary'), 80, 'Beneficiary');
        }
        if (LedgerUtil.has(body, 'nominee')) {
            x.Nominee__c = LedgerUtil.limited(LedgerUtil.text(body, 'nominee'), 80, 'Nominee');
        }
        if (LedgerUtil.has(body, 'notes')) {
            x.Notes__c = LedgerUtil.limited(LedgerUtil.text(body, 'notes'), 255, 'Notes');
        }
        if (creating || LedgerUtil.has(body, 'startDate')) {
            x.Start_Date__c = LedgerUtil.dateValue(body, 'startDate', 'Opened on');
            if (x.Start_Date__c == null || x.Start_Date__c < Date.newInstance(1970, 1, 1) || x.Start_Date__c > Date.today().addDays(30)) {
                errors.add('Enter the date the scheme was opened (not more than 30 days ahead).');
            }
        }
        if (creating || LedgerUtil.has(body, 'rate')) {
            x.Rate__c = LedgerUtil.has(body, 'rate') ? LedgerUtil.dec(body, 'rate', 'Interest rate') : rule.rate;
            if (x.Rate__c != null && (x.Rate__c < 0 || x.Rate__c > 20)) {
                errors.add('Interest rate must be between 0% and 20%.');
            }
        }
        if (LedgerUtil.has(body, 'principal')) {
            x.Principal__c = LedgerUtil.dec(body, 'principal', 'Amount invested');
        }
        if (rule.kind == 'lump' && x.Principal__c == null) {
            errors.add('Enter the amount invested.');
        }
        if (x.Principal__c != null && rule.kind == 'lump') {
            if (rule.minAmount != null && x.Principal__c < rule.minAmount) {
                errors.add(rule.label + ' starts at Rs ' + rule.minAmount.format() + '.');
            }
            if (rule.maxAmount != null && x.Principal__c > rule.maxAmount) {
                errors.add(rule.label + ' takes at most Rs ' + rule.maxAmount.format() + '.');
            }
        }
        if (LedgerUtil.has(body, 'plannedContribution')) {
            x.Planned_Contribution__c = LedgerUtil.dec(body, 'plannedContribution', 'Planned deposit');
            if (x.Planned_Contribution__c != null && (x.Planned_Contribution__c < 0 || (rule.kind == 'yearly' && rule.maxAmount != null && x.Planned_Contribution__c > rule.maxAmount))) {
                errors.add('A yearly deposit in ' + rule.label + ' can be up to Rs 1,50,000.');
            }
        }
        if (x.Scheme__c == 'PO_RD' && (x.Planned_Contribution__c == null || x.Planned_Contribution__c < 100)) {
            errors.add('Enter the monthly instalment (at least Rs 100).');
        }
        if (creating || LedgerUtil.has(body, 'tenureMonths')) {
            Decimal months = LedgerUtil.has(body, 'tenureMonths') ? LedgerUtil.dec(body, 'tenureMonths', 'Tenure') : rule.months;
            x.Tenure_Months__c = months;
            if (x.Scheme__c == 'PO_TD' && months != null && !new Set<Integer>{ 12, 24, 36, 60 }.contains(months.intValue())) {
                errors.add('A Post Office Time Deposit runs 1, 2, 3 or 5 years.');
            }
            if (months != null && (months < 1 || months > 600)) {
                errors.add('Tenure must be between 1 and 600 months.');
            }
        }
        if (x.Start_Date__c != null) {
            Date computed = SchemeRules.maturityDate(x.Scheme__c, x.Start_Date__c, x.Tenure_Months__c == null ? null : x.Tenure_Months__c.intValue());
            if (computed != null && x.Scheme__c != 'OTHER' && x.Scheme__c != 'NPS' && x.Scheme__c != 'EPF') {
                x.Maturity_Date__c = computed;
            } else if (LedgerUtil.has(body, 'maturityDate')) {
                x.Maturity_Date__c = LedgerUtil.dateValue(body, 'maturityDate', 'Maturity date');
            } else if (computed != null) {
                x.Maturity_Date__c = computed;
            }
            if (x.Maturity_Date__c != null && (x.Maturity_Date__c <= x.Start_Date__c || x.Maturity_Date__c.year() > 2100)) {
                errors.add('Maturity must be after the opening date and before 2100.');
            }
        }
        x.Payout__c = rule.payout;
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }
    }
}
