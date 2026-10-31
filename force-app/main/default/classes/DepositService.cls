/**
 * Fixed and recurring deposits. The deposit account's ledger balance is the money put in; the terms
 * live in Deposit__c. Closing or renewing books the interest as Income on the deposit account and
 * then moves the money out with an ordinary transfer, so reports and the tax summary see it.
 *
 * Indian rules followed here: FD terms run 7 days to 10 years and RD terms 6 to 120 months; a
 * tax-saver FD (section 80C) holds at most ₹1,50,000, runs at least 5 years and can't be closed
 * early; banks deduct 10% TDS (section 194A, from 1 April 2025) once one person's deposit interest
 * from one bank passes ₹50,000 in a financial year, or ₹1,00,000 for a senior citizen, unless Form
 * 15G/15H is on file; and DICGC insures up to ₹5,00,000 per depositor per bank.
 */
public without sharing class DepositService {
    public static final Set<String> TYPES = new Set<String>{ 'Fixed Deposit', 'Recurring Deposit' };
    public static final List<String> COMPOUNDING = new List<String>{ 'Quarterly', 'Monthly', 'Half-yearly', 'Yearly' };
    public static final List<String> PAYOUTS = new List<String>{ 'On maturity', 'Monthly', 'Quarterly', 'Half-yearly', 'Yearly' };
    public static final List<String> ON_MATURITY = new List<String>{ 'Credit to account', 'Renew principal', 'Renew principal and interest' };
    public static final Integer FD_MIN_DAYS = 7;
    public static final Integer FD_MAX_MONTHS = 120;
    public static final Integer RD_MIN_MONTHS = 6;
    public static final Integer RD_MAX_MONTHS = 120;
    public static final Decimal MAX_RATE = 20;
    public static final Decimal TAX_SAVER_MAX = 150000;
    public static final Integer TAX_SAVER_MONTHS = 60;
    public static final Decimal TDS_THRESHOLD = 50000;
    public static final Decimal TDS_THRESHOLD_SENIOR = 100000;
    public static final Decimal TDS_RATE = 10;
    public static final Decimal DICGC_COVER = 500000;
    public static final Decimal DEFAULT_PENALTY = 1;
    public static final Integer REMIND_DAYS = 7;
    private static final Pattern NUMBER_FORMAT = Pattern.compile('^[A-Za-z0-9/ -]{4,30}$');
    /** Recurring rules can repeat on these; half-yearly payouts are recorded at maturity instead. */
    private static final Map<Integer, String> FREQUENCY = new Map<Integer, String>{ 1 => 'Monthly', 3 => 'Quarterly', 12 => 'Yearly' };

    private static final String PLAIN_FIELDS =
        'Id, Account__c, Family__c, Account_Key__c, Kind__c, Deposit_Number__c, Principal__c, Instalment__c, Rate__c, Senior_Citizen__c, ' +
        'Compounding__c, Payout__c, Start_Date__c, Tenure_Months__c, Tenure_Days__c, Maturity_Date__c, Maturity_Amount__c, Maturity_Quoted__c, ' +
        'On_Maturity__c, Payout_Account__c, Funding_Account__c, Schedule_Rule__c, Nominee__c, Tax_Saver__c, Penalty_Rate__c, ' +
        'Form_15_Submitted__c, Status__c, Closed_On__c, Amount_Received__c, Notes__c';
    private static final String FIELDS = PLAIN_FIELDS +
        ', Account__r.Name, Account__r.Institution__c, Account__r.Owner_Member__c, Account__r.Owner_Member__r.First_Name__c, ' +
        'Account__r.Owner_Member__r.Last_Name__c, Payout_Account__r.Name, Funding_Account__r.Name';

    // ------------------------------------------------------------------ reads

    public static DepositDtos.Portfolio portfolio(UserContext ctx) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'READ');
        LedgerScope scope = new LedgerScope(ctx);
        Map<Id, Financial_Account__c> accounts = new Map<Id, Financial_Account__c>();
        for (Financial_Account__c a : new AccountSelector(ctx).visible(false)) {
            if (TYPES.contains(a.Type__c)) {
                accounts.put(a.Id, a);
            }
        }
        Date today = Date.today();
        DepositDtos.Portfolio p = new DepositDtos.Portfolio();
        p.financialYear = DepositCalculator.financialYearLabel(today);
        p.tdsThreshold = TDS_THRESHOLD;
        p.tdsThresholdSenior = TDS_THRESHOLD_SENIOR;
        p.tdsRate = TDS_RATE;
        p.dicgcCover = DICGC_COVER;
        Map<String, DepositDtos.TdsLine> tds = new Map<String, DepositDtos.TdsLine>();
        Map<String, Boolean> senior = new Map<String, Boolean>();
        Map<String, DepositDtos.CoverLine> cover = new Map<String, DepositDtos.CoverLine>();
        for (Deposit__c x : query(ctx.familyId, accounts.keySet())) {
            DepositDtos.Deposit d = dto(x, scope.canManageAccount(accounts.get(x.Account__c)), today);
            p.deposits.add(d);
            if (d.status != 'Active') {
                continue;
            }
            p.invested += d.invested;
            p.currentValue += d.currentValue;
            p.maturityValue += d.maturityAmount;
            p.interestThisFy += d.interestThisFy;
            if (d.daysToMaturity <= 30) {
                p.maturingIn30Days++;
            }
            String key = d.ownerId + '|' + (d.institution == null ? '' : d.institution.toLowerCase());
            DepositDtos.TdsLine t = tds.get(key);
            if (t == null) {
                t = new DepositDtos.TdsLine();
                t.ownerName = d.ownerName == null ? 'Family' : d.ownerName;
                t.institution = d.institution;
                t.interest = 0;
                t.form15Submitted = true;
                tds.put(key, t);
                DepositDtos.CoverLine c = new DepositDtos.CoverLine();
                c.ownerName = t.ownerName;
                c.institution = d.institution;
                c.amount = 0;
                cover.put(key, c);
            }
            t.interest += d.interestThisFy;
            t.form15Submitted = t.form15Submitted && d.form15Submitted;
            senior.put(key, senior.get(key) == true || d.seniorCitizen);
            cover.get(key).amount += d.currentValue;
        }
        for (String key : tds.keySet()) {
            DepositDtos.TdsLine t = tds.get(key);
            t.threshold = senior.get(key) ? TDS_THRESHOLD_SENIOR : TDS_THRESHOLD;
            t.estimatedTds = t.interest > t.threshold && !t.form15Submitted ? (t.interest * TDS_RATE / 100).setScale(2, RoundingMode.HALF_UP) : 0;
            if (t.interest > 0) {
                p.tds.add(t);
            }
            DepositDtos.CoverLine c = cover.get(key);
            c.uncovered = Math.max(0, c.amount - DICGC_COVER);
            p.cover.add(c);
        }
        return p;
    }

    public static DepositDtos.Deposit get(UserContext ctx, Id accountId) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'READ');
        Financial_Account__c account = new AccountSelector(ctx).byId(accountId);
        LedgerScope scope = new LedgerScope(ctx);
        if (!scope.canSeeAccount(account)) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        List<Deposit__c> found = query(ctx.familyId, new Set<Id>{ account.Id });
        if (found.isEmpty()) {
            throw new PortalException('NOT_FOUND').withError('No deposit details have been added for this account yet.');
        }
        return dto(found[0], scope.canManageAccount(account), Date.today());
    }

    /** Adds the deposit terms to FD and RD accounts in an account list. */
    public static void attach(UserContext ctx, List<FinanceDtos.Account> accounts) {
        Map<Id, FinanceDtos.Account> byId = new Map<Id, FinanceDtos.Account>();
        for (FinanceDtos.Account a : accounts) {
            if (TYPES.contains(a.type)) {
                byId.put(a.id, a);
            }
        }
        if (byId.isEmpty()) {
            return;
        }
        Date today = Date.today();
        for (Deposit__c x : query(ctx.familyId, byId.keySet())) {
            FinanceDtos.Account a = byId.get(x.Account__c);
            a.deposit = dto(x, a.canManage == true, today);
        }
    }

    // ------------------------------------------------------------------ writes

    /** Creates or updates the terms of an FD or RD account. */
    public static DepositDtos.Deposit save(UserContext ctx, Id accountId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        Financial_Account__c account = AccountService.manageable(ctx, new AccountSelector(ctx), accountId);
        if (!TYPES.contains(account.Type__c)) {
            throw new PortalException('VALIDATION').withError('Deposit details are for fixed and recurring deposit accounts.');
        }
        if (account.Status__c != 'Active') {
            throw new PortalException('VALIDATION').withError('That account is closed.');
        }
        Deposit__c existing = editable(ctx.familyId, account.Id);
        if (existing != null && existing.Status__c != 'Active') {
            throw new PortalException('CONFLICT').withError('This deposit has already been closed.');
        }
        Boolean creating = existing == null;
        Decimal previousPrincipal = creating ? null : existing.Principal__c;
        Deposit__c x = creating
            ? new Deposit__c(
                  Account__c = account.Id, Family__c = ctx.familyId, Account_Key__c = account.Id, Status__c = 'Active',
                  Compounding__c = 'Quarterly', Payout__c = 'On maturity', On_Maturity__c = 'Credit to account', Penalty_Rate__c = DEFAULT_PENALTY
              )
            : existing;
        x.Kind__c = account.Type__c == 'Recurring Deposit' ? 'RD' : 'FD';
        apply(ctx, account, x, body, creating);
        upsert as system x;

        syncOpeningBalance(ctx, account, x, previousPrincipal);
        syncSchedule(ctx, account, x, LedgerUtil.has(body, 'autoPost') ? LedgerUtil.bool(body, 'autoPost') : true);
        AuditService.log(ctx, creating ? 'DEPOSIT_CREATED' : 'DEPOSIT_UPDATED', 'Deposit__c', x.Id, x.Kind__c + ' ' + x.Rate__c + '% to ' + x.Maturity_Date__c);
        return get(ctx, account.Id);
    }

    /**
     * Records the deposit paying out, at maturity or early. The interest (or, early, the penalised
     * value) is booked first; the whole amount then moves to the receiving account and the deposit
     * account closes at zero.
     */
    public static DepositDtos.Deposit close(UserContext ctx, Id accountId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        Financial_Account__c account = AccountService.manageable(ctx, new AccountSelector(ctx), accountId);
        Deposit__c x = activeDeposit(ctx.familyId, account.Id);
        Date today = Date.today();
        Date onDate = LedgerUtil.has(body, 'date') ? LedgerUtil.dateValue(body, 'date', 'Date') : minDate(today, x.Maturity_Date__c);
        if (onDate == null || onDate < x.Start_Date__c) {
            throw new PortalException('VALIDATION').withError('The closing date must be on or after the date it was invested.');
        }
        Boolean early = onDate < x.Maturity_Date__c;
        if (early && lockedIn(x, onDate)) {
            throw new PortalException('VALIDATION').withError('A tax-saver FD can\'t be closed in its first 5 years.');
        }
        Decimal received = LedgerUtil.has(body, 'amountReceived')
            ? LedgerUtil.amount(LedgerUtil.dec(body, 'amountReceived', 'Amount received'), 'Amount received')
            : early ? prematureValue(x, onDate) : x.Maturity_Amount__c;
        Id toId = LedgerUtil.has(body, 'toAccountId') ? VkfRest.toId(LedgerUtil.text(body, 'toAccountId')) : x.Payout_Account__c;
        Financial_Account__c target = receivingAccount(ctx, toId, account.Id);

        bookTo(ctx, account, received, onDate, early ? 'Interest - closed early' : 'Interest on maturity');
        TransferService.createTransfer(ctx, new Map<String, Object>{
            'fromAccountId' => account.Id, 'toAccountId' => target.Id, 'amount' => received, 'date' => String.valueOf(onDate),
            'notes' => (account.Name + (early ? ' closed early' : ' matured')).left(255)
        });
        stopSchedule(ctx, x);
        update as system new Deposit__c(Id = x.Id, Status__c = early ? 'Closed Early' : 'Matured', Closed_On__c = onDate, Amount_Received__c = received);
        AccountService.updateAccount(ctx, account.Id, new Map<String, Object>{ 'status' => 'Closed' });
        AuditService.log(ctx, early ? 'DEPOSIT_CLOSED_EARLY' : 'DEPOSIT_MATURED', 'Deposit__c', x.Id, String.valueOf(received));
        return dto(query(ctx.familyId, new Set<Id>{ account.Id })[0], true, today);
    }

    /**
     * Renews a matured FD for a new term, from its maturity date by default. With the interest,
     * the whole maturity amount stays in; without it, the interest moves to the payout account.
     */
    public static DepositDtos.Deposit renew(UserContext ctx, Id accountId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        Financial_Account__c account = AccountService.manageable(ctx, new AccountSelector(ctx), accountId);
        Deposit__c x = activeDeposit(ctx.familyId, account.Id);
        if (x.Kind__c == 'RD') {
            throw new PortalException('VALIDATION').withError('An RD can\'t be renewed - start a new RD instead.');
        }
        Date onDate = LedgerUtil.has(body, 'date') ? LedgerUtil.dateValue(body, 'date', 'Date') : x.Maturity_Date__c;
        if (onDate == null || onDate < x.Maturity_Date__c) {
            throw new PortalException('VALIDATION').withError('A deposit renews on or after its maturity date.');
        }
        Decimal received = LedgerUtil.has(body, 'amountReceived')
            ? LedgerUtil.amount(LedgerUtil.dec(body, 'amountReceived', 'Amount received'), 'Amount received')
            : x.Maturity_Amount__c;
        Boolean withInterest = LedgerUtil.has(body, 'includeInterest')
            ? LedgerUtil.bool(body, 'includeInterest')
            : x.On_Maturity__c != 'Renew principal';
        String oldTerms = x.Principal__c + ' at ' + x.Rate__c + '% ' + x.Start_Date__c + ' to ' + x.Maturity_Date__c;

        bookTo(ctx, account, received, onDate, 'Interest on maturity');
        Decimal principal = received;
        Decimal interest = received - x.Principal__c;
        if (!withInterest && interest > 0) {
            Id toId = LedgerUtil.has(body, 'toAccountId') ? VkfRest.toId(LedgerUtil.text(body, 'toAccountId')) : x.Payout_Account__c;
            Financial_Account__c target = receivingAccount(ctx, toId, account.Id);
            TransferService.createTransfer(ctx, new Map<String, Object>{
                'fromAccountId' => account.Id, 'toAccountId' => target.Id, 'amount' => interest, 'date' => String.valueOf(onDate),
                'notes' => ('Interest from ' + account.Name).left(255)
            });
            principal = x.Principal__c;
        }
        Map<String, Object> terms = new Map<String, Object>{
            'principal' => principal, 'startDate' => String.valueOf(onDate), 'maturityAmount' => body.get('maturityAmount'),
            'rate' => LedgerUtil.has(body, 'rate') ? body.get('rate') : x.Rate__c,
            'tenureMonths' => LedgerUtil.has(body, 'tenureMonths') ? body.get('tenureMonths') : x.Tenure_Months__c,
            'tenureDays' => LedgerUtil.has(body, 'tenureDays') ? body.get('tenureDays') : x.Tenure_Days__c
        };
        apply(ctx, account, x, terms, false);
        update as system x;
        syncSchedule(ctx, account, x, true);
        AuditService.log(ctx, 'DEPOSIT_RENEWED', 'Deposit__c', x.Id, 'was ' + oldTerms);
        return get(ctx, account.Id);
    }

    // ------------------------------------------------------------------ automation

    /** Daily: tell the owner (or the admins) a week before a deposit matures, and again once it has. */
    public static Integer notifyMaturities(Id familyId, Date today, Set<Id> admins) {
        Integer sent = 0;
        Date horizon = today.addDays(REMIND_DAYS);
        for (Deposit__c x : [
            SELECT Id, Kind__c, Maturity_Date__c, Maturity_Amount__c, On_Maturity__c, Account__r.Name, Account__r.Owner_Member__c
            FROM Deposit__c
            WHERE Family__c = :familyId AND Status__c = 'Active' AND Maturity_Date__c <= :horizon AND Maturity_Date__c >= :today.addDays(-30)
            WITH SYSTEM_MODE
            LIMIT 200
        ]) {
            Integer days = today.daysBetween(x.Maturity_Date__c);
            Set<Id> who = x.Account__r.Owner_Member__c == null ? admins.clone() : new Set<Id>{ x.Account__r.Owner_Member__c };
            String amount = DuesProcessor.money(x.Maturity_Amount__c);
            NotificationService.Message m = days > 0
                ? new NotificationService.Message(
                      'DEPOSIT_MATURING', 'info', x.Account__r.Name + ' matures in ' + days + (days == 1 ? ' day' : ' days'),
                      amount + ' on ' + x.Maturity_Date__c.format() + '. On maturity: ' + x.On_Maturity__c.toLowerCase() + '.',
                      '/accounts', 'DEPMAT:' + x.Id + ':soon'
                  )
                : new NotificationService.Message(
                      'DEPOSIT_MATURED', 'warning', x.Account__r.Name + ' has matured',
                      amount + ' is due. Record where the money went, or renew it, on the Accounts page.',
                      '/accounts', 'DEPMAT:' + x.Id + ':due'
                  );
            sent += NotificationService.notify(familyId, who, m);
        }
        return sent;
    }

    // ------------------------------------------------------------------ the terms

    private static void apply(UserContext ctx, Financial_Account__c account, Deposit__c x, Map<String, Object> body, Boolean creating) {
        List<String> errors = new List<String>();
        Boolean rd = x.Kind__c == 'RD';
        if (LedgerUtil.has(body, 'depositNumber')) {
            x.Deposit_Number__c = LedgerUtil.text(body, 'depositNumber');
            if (x.Deposit_Number__c != null && !NUMBER_FORMAT.matcher(x.Deposit_Number__c).matches()) {
                errors.add('Deposit number can be 4 to 30 letters, digits, spaces, / or -.');
            }
        }
        if (creating || LedgerUtil.has(body, 'rate')) {
            x.Rate__c = LedgerUtil.dec(body, 'rate', 'Interest rate');
        }
        if (x.Rate__c == null || x.Rate__c <= 0 || x.Rate__c > MAX_RATE) {
            errors.add('Interest rate must be more than 0% and at most ' + MAX_RATE + '%.');
        }
        if (LedgerUtil.has(body, 'seniorCitizen')) {
            x.Senior_Citizen__c = LedgerUtil.bool(body, 'seniorCitizen');
        }
        if (creating || LedgerUtil.has(body, 'startDate')) {
            x.Start_Date__c = LedgerUtil.dateValue(body, 'startDate', 'Invested on');
        }
        if (x.Start_Date__c == null || x.Start_Date__c < Date.newInstance(2000, 1, 1) || x.Start_Date__c > Date.today().addDays(30)) {
            errors.add('Invested on must be a date up to 30 days from today.');
        }

        Boolean tenureGiven = LedgerUtil.has(body, 'tenureMonths') || LedgerUtil.has(body, 'tenureDays');
        if (LedgerUtil.has(body, 'tenureMonths')) {
            x.Tenure_Months__c = wholeNumber(body, 'tenureMonths', 'Tenure months', errors);
        }
        if (LedgerUtil.has(body, 'tenureDays')) {
            x.Tenure_Days__c = wholeNumber(body, 'tenureDays', 'Tenure days', errors);
        }
        if (!tenureGiven && LedgerUtil.has(body, 'maturityDate') && x.Start_Date__c != null) {
            // Only the bank's maturity date was given: split it into months and days.
            Date maturity = LedgerUtil.dateValue(body, 'maturityDate', 'Maturity date');
            if (maturity == null || maturity <= x.Start_Date__c) {
                errors.add('Maturity date must be after the date it was invested.');
            } else {
                Integer months = x.Start_Date__c.monthsBetween(maturity);
                if (x.Start_Date__c.addMonths(months) > maturity) {
                    months--;
                }
                x.Tenure_Months__c = months;
                x.Tenure_Days__c = x.Start_Date__c.addMonths(months).daysBetween(maturity);
            }
        }
        Integer months = x.Tenure_Months__c == null ? 0 : x.Tenure_Months__c.intValue();
        Integer days = x.Tenure_Days__c == null ? 0 : x.Tenure_Days__c.intValue();
        x.Tenure_Months__c = months;
        x.Tenure_Days__c = days;
        if (x.Start_Date__c != null) {
            x.Maturity_Date__c = DepositCalculator.maturityDate(x.Start_Date__c, months, days);
        }

        if (LedgerUtil.has(body, 'compounding')) {
            x.Compounding__c = LedgerUtil.text(body, 'compounding');
            if (!COMPOUNDING.contains(x.Compounding__c)) {
                errors.add('Choose how often interest compounds.');
            }
        }
        if (LedgerUtil.has(body, 'payout')) {
            x.Payout__c = LedgerUtil.text(body, 'payout');
            if (!PAYOUTS.contains(x.Payout__c)) {
                errors.add('Choose when interest is paid.');
            }
        }
        if (LedgerUtil.has(body, 'taxSaver')) {
            x.Tax_Saver__c = LedgerUtil.bool(body, 'taxSaver');
        }
        if (LedgerUtil.has(body, 'onMaturity')) {
            x.On_Maturity__c = LedgerUtil.text(body, 'onMaturity');
            if (!ON_MATURITY.contains(x.On_Maturity__c)) {
                errors.add('Choose what happens on maturity.');
            }
        }

        if (rd) {
            if (creating || LedgerUtil.has(body, 'instalment')) {
                x.Instalment__c = LedgerUtil.dec(body, 'instalment', 'Monthly instalment');
            }
            if (x.Instalment__c == null || x.Instalment__c <= 0 || x.Instalment__c > LedgerUtil.MAX_AMOUNT) {
                errors.add('Monthly instalment must be more than zero.');
            }
            if (months < RD_MIN_MONTHS || months > RD_MAX_MONTHS || days != 0) {
                errors.add('An RD runs ' + RD_MIN_MONTHS + ' to ' + RD_MAX_MONTHS + ' whole months.');
            }
            // Banks compound RDs quarterly and pay everything at maturity.
            x.Compounding__c = 'Quarterly';
            x.Payout__c = 'On maturity';
            x.Tax_Saver__c = false;
            x.On_Maturity__c = 'Credit to account';
            x.Principal__c = null;
        } else {
            if (creating || LedgerUtil.has(body, 'principal')) {
                x.Principal__c = LedgerUtil.dec(body, 'principal', 'Amount invested');
            }
            if (x.Principal__c == null || x.Principal__c <= 0 || x.Principal__c > LedgerUtil.MAX_AMOUNT) {
                errors.add('Amount invested must be more than zero.');
            }
            Integer totalDays = x.Start_Date__c == null ? 0 : x.Start_Date__c.daysBetween(x.Maturity_Date__c);
            if (totalDays < FD_MIN_DAYS || (x.Start_Date__c != null && x.Maturity_Date__c > x.Start_Date__c.addMonths(FD_MAX_MONTHS))) {
                errors.add('An FD runs from ' + FD_MIN_DAYS + ' days to 10 years.');
            }
            if (x.Tax_Saver__c == true) {
                if (x.Start_Date__c != null && x.Maturity_Date__c < x.Start_Date__c.addMonths(TAX_SAVER_MONTHS)) {
                    errors.add('A tax-saver FD runs at least 5 years.');
                }
                if (x.Principal__c != null && x.Principal__c > TAX_SAVER_MAX) {
                    errors.add('A tax-saver FD can hold up to ₹1,50,000 (the section 80C limit).');
                }
            }
            x.Instalment__c = null;
        }

        if (LedgerUtil.has(body, 'penaltyRate')) {
            x.Penalty_Rate__c = LedgerUtil.dec(body, 'penaltyRate', 'Premature penalty');
        }
        if (x.Penalty_Rate__c == null || x.Penalty_Rate__c < 0 || x.Penalty_Rate__c > 5) {
            errors.add('Premature penalty must be between 0% and 5%.');
        }
        if (LedgerUtil.has(body, 'form15Submitted')) {
            x.Form_15_Submitted__c = LedgerUtil.bool(body, 'form15Submitted');
        }
        if (LedgerUtil.has(body, 'nominee')) {
            x.Nominee__c = LedgerUtil.limited(LedgerUtil.text(body, 'nominee'), 80, 'Nominee');
        }
        if (LedgerUtil.has(body, 'notes')) {
            x.Notes__c = LedgerUtil.limited(LedgerUtil.text(body, 'notes'), 255, 'Notes');
        }
        if (LedgerUtil.has(body, 'payoutAccountId')) {
            Id payoutId = VkfRest.toId(LedgerUtil.text(body, 'payoutAccountId'));
            x.Payout_Account__c = payoutId == null ? null : receivingAccount(ctx, payoutId, account.Id).Id;
        }
        if (LedgerUtil.has(body, 'fundingAccountId')) {
            Id fundingId = VkfRest.toId(LedgerUtil.text(body, 'fundingAccountId'));
            x.Funding_Account__c = !rd || fundingId == null ? null : receivingAccount(ctx, fundingId, account.Id).Id;
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }

        Decimal calculated = calculatedMaturity(x);
        if (LedgerUtil.has(body, 'maturityAmount')) {
            Decimal quoted = LedgerUtil.dec(body, 'maturityAmount', 'Maturity amount');
            x.Maturity_Quoted__c = quoted != null;
            if (quoted != null) {
                x.Maturity_Amount__c = LedgerUtil.amount(quoted, 'Maturity amount');
                if (x.Maturity_Amount__c < invested(x)) {
                    throw new PortalException('VALIDATION').withError('The maturity amount can\'t be less than the amount invested.');
                }
            }
        }
        if (x.Maturity_Quoted__c != true) {
            x.Maturity_Amount__c = calculated;
        }
    }

    // ------------------------------------------------------------------ figures

    public static Decimal calculatedMaturity(Deposit__c x) {
        if (x.Kind__c == 'RD') {
            return DepositCalculator.rdMaturity(x.Instalment__c, x.Rate__c, x.Tenure_Months__c.intValue(), x.Start_Date__c);
        }
        if (cumulative(x)) {
            return DepositCalculator.fdValue(x.Principal__c, x.Rate__c, x.Compounding__c, x.Start_Date__c, x.Maturity_Date__c, x.Maturity_Date__c);
        }
        return x.Principal__c + DepositCalculator.brokenPeriodInterest(x.Principal__c, x.Rate__c, x.Start_Date__c, x.Maturity_Date__c, x.Payout__c);
    }

    public static Decimal invested(Deposit__c x) {
        return x.Kind__c == 'RD' ? x.Instalment__c * x.Tenure_Months__c : x.Principal__c;
    }

    /** What the deposit is worth on `asOf` at its own rate. */
    public static Decimal valueOn(Deposit__c x, Date asOf) {
        if (asOf >= x.Maturity_Date__c) {
            return x.Maturity_Amount__c;
        }
        if (x.Kind__c == 'RD') {
            return DepositCalculator.rdValue(x.Instalment__c, x.Rate__c, x.Start_Date__c, x.Tenure_Months__c.intValue(), asOf);
        }
        if (cumulative(x)) {
            return DepositCalculator.fdValue(x.Principal__c, x.Rate__c, x.Compounding__c, x.Start_Date__c, x.Maturity_Date__c, asOf);
        }
        return x.Principal__c;
    }

    /** Interest the deposit earns in the financial year `today` falls in - what banks total for TDS. */
    public static Decimal interestInFinancialYear(Deposit__c x, Date today) {
        Date fyStart = DepositCalculator.financialYearStart(today);
        Date fromDate = maxDate(fyStart, x.Start_Date__c);
        Date toDate = minDate(fyStart.addYears(1).addDays(-1), x.Maturity_Date__c);
        if (toDate <= fromDate) {
            return 0;
        }
        if (x.Kind__c == 'FD' && !cumulative(x)) {
            return (x.Principal__c * x.Rate__c / 100 * fromDate.daysBetween(toDate) / 365).setScale(2, RoundingMode.HALF_UP);
        }
        Decimal grown = valueOn(x, toDate) - valueOn(x, fromDate);
        if (x.Kind__c == 'RD') {
            Integer months = x.Tenure_Months__c.intValue();
            Integer paidIn = DepositCalculator.rdInstalmentsDue(x.Start_Date__c, months, toDate) - DepositCalculator.rdInstalmentsDue(x.Start_Date__c, months, fromDate);
            grown -= x.Instalment__c * paidIn;
        }
        return Math.max(0, grown).setScale(2, RoundingMode.HALF_UP);
    }

    /** Early closure: the bank's rate cut applies to the whole time the money was in. */
    public static Decimal prematureValue(Deposit__c x, Date onDate) {
        Decimal penalised = Math.max(0, x.Rate__c - LedgerUtil.zeroIfNull(x.Penalty_Rate__c));
        if (x.Kind__c == 'RD') {
            return penalised == 0
                ? x.Instalment__c * DepositCalculator.rdInstalmentsDue(x.Start_Date__c, x.Tenure_Months__c.intValue(), onDate)
                : DepositCalculator.rdValue(x.Instalment__c, penalised, x.Start_Date__c, x.Tenure_Months__c.intValue(), onDate);
        }
        if (cumulative(x)) {
            return penalised == 0 ? x.Principal__c : DepositCalculator.fdValue(x.Principal__c, penalised, x.Compounding__c, x.Start_Date__c, onDate, onDate);
        }
        // Payout deposits already paid interest at the full rate; the bank recovers the excess.
        Decimal excess = x.Principal__c * (x.Rate__c - penalised) / 100 * x.Start_Date__c.daysBetween(onDate) / 365;
        return (x.Principal__c - excess).setScale(2, RoundingMode.HALF_UP);
    }

    public static Boolean lockedIn(Deposit__c x, Date onDate) {
        return x.Tax_Saver__c == true && onDate < x.Start_Date__c.addMonths(TAX_SAVER_MONTHS);
    }

    private static Boolean cumulative(Deposit__c x) {
        return x.Payout__c == null || x.Payout__c == 'On maturity';
    }

    public static DepositDtos.Deposit dto(Deposit__c x, Boolean canManage, Date today) {
        DepositDtos.Deposit d = new DepositDtos.Deposit();
        d.id = x.Id;
        d.accountId = x.Account__c;
        d.accountName = x.Account__r?.Name;
        d.institution = x.Account__r?.Institution__c;
        d.ownerId = x.Account__r?.Owner_Member__c;
        d.ownerName = d.ownerId == null ? null : FinanceDtos.personName(x.Account__r.Owner_Member__r?.First_Name__c, x.Account__r.Owner_Member__r?.Last_Name__c);
        d.kind = x.Kind__c;
        d.depositNumberMasked = DepositDtos.mask(x.Deposit_Number__c);
        d.depositNumber = canManage ? x.Deposit_Number__c : d.depositNumberMasked;
        d.principal = x.Principal__c;
        d.instalment = x.Instalment__c;
        d.rate = x.Rate__c;
        d.seniorCitizen = x.Senior_Citizen__c == true;
        d.compounding = x.Compounding__c;
        d.payout = x.Payout__c;
        d.startDate = x.Start_Date__c;
        d.tenureMonths = x.Tenure_Months__c == null ? 0 : x.Tenure_Months__c.intValue();
        d.tenureDays = x.Tenure_Days__c == null ? 0 : x.Tenure_Days__c.intValue();
        d.maturityDate = x.Maturity_Date__c;
        d.maturityAmount = x.Maturity_Amount__c;
        d.maturityQuoted = x.Maturity_Quoted__c == true;
        d.calculatedMaturity = calculatedMaturity(x);
        d.onMaturity = x.On_Maturity__c;
        d.payoutAccountId = x.Payout_Account__c;
        d.payoutAccountName = x.Payout_Account__r?.Name;
        d.fundingAccountId = x.Funding_Account__c;
        d.fundingAccountName = x.Funding_Account__r?.Name;
        d.scheduleRuleId = x.Schedule_Rule__c;
        d.nominee = x.Nominee__c;
        d.taxSaver = x.Tax_Saver__c == true;
        d.penaltyRate = x.Penalty_Rate__c;
        d.form15Submitted = x.Form_15_Submitted__c == true;
        d.status = x.Status__c;
        d.closedOn = x.Closed_On__c;
        d.amountReceived = x.Amount_Received__c;
        d.notes = x.Notes__c;

        d.invested = invested(x);
        Boolean payout = x.Kind__c == 'FD' && !cumulative(x);
        if (payout) {
            d.payoutPerPeriod = DepositCalculator.payoutPerPeriod(x.Principal__c, x.Rate__c, x.Payout__c);
            d.interestAtMaturity = d.payoutPerPeriod * DepositCalculator.payoutCount(x.Start_Date__c, x.Maturity_Date__c, x.Payout__c) +
                (x.Maturity_Amount__c - x.Principal__c);
        } else {
            d.interestAtMaturity = x.Maturity_Amount__c - d.invested;
            if (x.Kind__c == 'FD') {
                d.effectiveYield = DepositCalculator.effectiveYield(x.Principal__c, x.Maturity_Amount__c, x.Start_Date__c, x.Maturity_Date__c);
            }
        }
        Integer totalDays = Math.max(1, x.Start_Date__c.daysBetween(x.Maturity_Date__c));
        d.daysToMaturity = today.daysBetween(x.Maturity_Date__c);
        Decimal elapsedPct = x.Start_Date__c.daysBetween(today) * 100.0 / totalDays;
        d.progressPct = Math.min(100.0, Math.max(0.0, elapsedPct)).setScale(1, RoundingMode.HALF_UP);
        if (x.Kind__c == 'RD') {
            d.instalmentsDue = DepositCalculator.rdInstalmentsDue(x.Start_Date__c, x.Tenure_Months__c.intValue(), today);
        }
        d.lockedIn = lockedIn(x, today);
        if (x.Status__c == 'Active') {
            d.currentValue = valueOn(x, today);
            d.interestThisFy = interestInFinancialYear(x, today);
            if (today < x.Maturity_Date__c && today >= x.Start_Date__c && !d.lockedIn) {
                d.prematureValue = prematureValue(x, today);
            }
        } else {
            d.currentValue = 0;
            d.interestThisFy = 0;
        }
        return d;
    }

    // ------------------------------------------------------------------ ledger and schedule

    /** Books the difference between what the deposit pays out and its ledger balance. */
    private static void bookTo(UserContext ctx, Financial_Account__c account, Decimal received, Date onDate, String note) {
        Financial_Account__c fresh = new AccountSelector(ctx).byId(account.Id);
        Decimal balance = fresh.Current_Balance__c == null ? LedgerUtil.zeroIfNull(fresh.Opening_Balance__c) : fresh.Current_Balance__c;
        Decimal diff = received - balance;
        if (diff > 0) {
            TransactionService.createTransaction(ctx, new Map<String, Object>{
                'type' => 'Income', 'accountId' => account.Id, 'amount' => diff, 'categoryId' => interestCategory(ctx),
                'date' => String.valueOf(onDate), 'payee' => (account.Institution__c == null ? account.Name : account.Institution__c).left(120),
                'notes' => note
            });
        } else if (diff < 0) {
            AccountService.reconcile(ctx, account.Id, new Map<String, Object>{
                'actualBalance' => received, 'date' => String.valueOf(onDate), 'note' => 'Premature withdrawal penalty'
            });
        }
    }

    private static Id interestCategory(UserContext ctx) {
        Category__c fallback;
        for (Category__c c : CategoryService.ensureSeeded(ctx).all()) {
            if (c.Kind__c != 'Income') {
                continue;
            }
            if (c.Name == 'Interest and Dividends') {
                return c.Id;
            }
            fallback = fallback == null ? c : fallback;
        }
        if (fallback == null) {
            throw new PortalException('VALIDATION').withError('Add an income category for interest first.');
        }
        return fallback.Id;
    }

    /** A bank, cash or wallet account in the family that money can land in. */
    private static Financial_Account__c receivingAccount(UserContext ctx, Id accountId, Id depositAccountId) {
        if (accountId == null) {
            throw new PortalException('VALIDATION').withError('Choose the account the money goes to.');
        }
        Financial_Account__c a = TransactionService.usableAccount(ctx, accountId);
        if (a.Id == depositAccountId || LedgerUtil.isLiability(a.Type__c) || TYPES.contains(a.Type__c)) {
            throw new PortalException('VALIDATION').withError('Choose a bank, cash or wallet account.');
        }
        return a;
    }

    /**
     * A new FD's account starts with the amount invested, and an RD's with the instalments paid so
     * far - but only while the account has no entries, so the ledger never contradicts itself.
     */
    private static void syncOpeningBalance(UserContext ctx, Financial_Account__c account, Deposit__c x, Decimal previousPrincipal) {
        AccountSelector selector = new AccountSelector(ctx);
        Financial_Account__c fresh = selector.byId(account.Id);
        if (selector.hasTransactions(account.Id)) {
            return;
        }
        Decimal opening = LedgerUtil.zeroIfNull(fresh.Opening_Balance__c);
        Decimal wanted;
        Date openingDate;
        if (x.Kind__c == 'RD') {
            wanted = x.Instalment__c * DepositCalculator.rdInstalmentsDue(x.Start_Date__c, x.Tenure_Months__c.intValue(), Date.today());
            openingDate = Date.today();
            if (opening != 0) {
                return;
            }
        } else {
            wanted = x.Principal__c;
            openingDate = x.Start_Date__c;
            if (opening != 0 && opening != previousPrincipal) {
                return;
            }
        }
        if (wanted != opening) {
            AccountService.updateAccount(ctx, account.Id, new Map<String, Object>{ 'openingBalance' => wanted, 'openingDate' => String.valueOf(openingDate) });
        }
    }

    /**
     * Keeps one recurring rule per deposit: the RD instalment as a monthly transfer from the funding
     * account, or a payout FD's interest as income into the payout account.
     */
    private static void syncSchedule(UserContext ctx, Financial_Account__c account, Deposit__c x, Boolean autoPost) {
        Date today = Date.today();
        Map<String, Object> rule;
        if (x.Kind__c == 'RD' && x.Funding_Account__c != null) {
            Integer months = x.Tenure_Months__c.intValue();
            Integer paid = DepositCalculator.rdInstalmentsDue(x.Start_Date__c, months, today);
            if (paid < months) {
                rule = new Map<String, Object>{
                    'name' => ('RD instalment · ' + account.Name).left(80), 'type' => 'Transfer', 'amount' => x.Instalment__c,
                    'accountId' => x.Funding_Account__c, 'toAccountId' => account.Id, 'frequency' => 'Monthly',
                    'nextRunDate' => String.valueOf(x.Start_Date__c.addMonths(paid)), 'endDate' => String.valueOf(x.Start_Date__c.addMonths(months - 1))
                };
            }
        } else if (x.Kind__c == 'FD' && !cumulative(x) && x.Payout_Account__c != null) {
            Integer step = DepositCalculator.payoutMonths(x.Payout__c);
            Integer n = 1;
            while (x.Start_Date__c.addMonths(step * n) <= today) {
                n++;
            }
            Date next = x.Start_Date__c.addMonths(step * n);
            if (FREQUENCY.containsKey(step) && next <= x.Maturity_Date__c) {
                rule = new Map<String, Object>{
                    'name' => ('FD interest · ' + account.Name).left(80), 'type' => 'Income',
                    'amount' => DepositCalculator.payoutPerPeriod(x.Principal__c, x.Rate__c, x.Payout__c),
                    'accountId' => x.Payout_Account__c, 'categoryId' => interestCategory(ctx), 'frequency' => FREQUENCY.get(step),
                    'payee' => (account.Institution__c == null ? account.Name : account.Institution__c).left(120),
                    'nextRunDate' => String.valueOf(next), 'endDate' => String.valueOf(x.Maturity_Date__c)
                };
            }
        }
        if (rule == null) {
            stopSchedule(ctx, x);
            return;
        }
        rule.put('mode', autoPost ? 'Auto-post' : 'Suggest');
        rule.put('active', true);
        if (x.Schedule_Rule__c != null && AccessGuard.can(ctx, 'RECURRING', 'EDIT')) {
            RecurringService.updateRule(ctx, x.Schedule_Rule__c, rule);
        } else if (x.Schedule_Rule__c == null && AccessGuard.can(ctx, 'RECURRING', 'CREATE')) {
            Id ruleId = RecurringService.createRule(ctx, rule).id;
            update as system new Deposit__c(Id = x.Id, Schedule_Rule__c = ruleId);
            x.Schedule_Rule__c = ruleId;
        }
    }

    private static void stopSchedule(UserContext ctx, Deposit__c x) {
        if (x.Schedule_Rule__c != null && AccessGuard.can(ctx, 'RECURRING', 'EDIT')) {
            RecurringService.updateRule(ctx, x.Schedule_Rule__c, new Map<String, Object>{ 'active' => false });
        }
    }

    // ------------------------------------------------------------------ queries

    private static List<Deposit__c> query(Id familyId, Set<Id> accountIds) {
        return (List<Deposit__c>) Database.queryWithBinds(
            'SELECT ' + FIELDS + ' FROM Deposit__c WHERE Family__c = :fid AND Account__c IN :ids ORDER BY Maturity_Date__c LIMIT 500',
            new Map<String, Object>{ 'fid' => familyId, 'ids' => accountIds },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Deposit__c editable(Id familyId, Id accountId) {
        List<Deposit__c> found = (List<Deposit__c>) Database.queryWithBinds(
            'SELECT ' + PLAIN_FIELDS + ' FROM Deposit__c WHERE Family__c = :fid AND Account__c = :aid LIMIT 1 FOR UPDATE',
            new Map<String, Object>{ 'fid' => familyId, 'aid' => accountId },
            AccessLevel.SYSTEM_MODE
        );
        return found.isEmpty() ? null : found[0];
    }

    private static Deposit__c activeDeposit(Id familyId, Id accountId) {
        Deposit__c x = editable(familyId, accountId);
        if (x == null) {
            throw new PortalException('VALIDATION').withError('Add the deposit details first.');
        }
        if (x.Status__c != 'Active') {
            throw new PortalException('CONFLICT').withError('This deposit has already been closed.');
        }
        return x;
    }

    private static Decimal wholeNumber(Map<String, Object> body, String key, String label, List<String> errors) {
        Decimal v = LedgerUtil.dec(body, key, label);
        if (v != null && (v < 0 || v > 999 || v != v.round())) {
            errors.add(label + ' must be a whole number.');
        }
        return v;
    }

    private static Date minDate(Date a, Date b) {
        return a < b ? a : b;
    }

    private static Date maxDate(Date a, Date b) {
        return a > b ? a : b;
    }
}
