/**
 * Insurance policies - LIC and other life plans, health, vehicle and home cover. The premium is kept
 * as a bill, so it gets the bill reminders, appears in the money position and calendar, and is paid
 * like any bill. Indian rules applied here:
 *   - IRDAI grace period: 15 days for monthly premiums, 30 days for other modes; after it the
 *     policy can lapse (revivable within 5 years).
 *   - 80C counts a life premium only up to 10% of the sum assured (policies from 1 April 2012); above
 *     that the maturity amount is taxable too - Section 10(10D).
 *   - 10(10D) also taxes the maturity of non-ULIP plans whose yearly premium is over Rs 5 lakh
 *     (issued from 1 April 2023), and of ULIPs over Rs 2.5 lakh (issued from 1 February 2021).
 * Members see and manage their own policies; admins the family's.
 */
public without sharing class InsuranceService {
    public static final Set<String> LIFE = new Set<String>{ 'Term', 'Endowment', 'Money-back', 'Whole life', 'ULIP', 'Pension' };
    public static final Set<String> HEALTH = new Set<String>{ 'Health' };
    public static final Set<String> TYPES = new Set<String>{ 'Term', 'Endowment', 'Money-back', 'Whole life', 'ULIP', 'Pension', 'Health', 'Vehicle', 'Home', 'Other' };
    public static final Map<String, Integer> PER_YEAR = new Map<String, Integer>{ 'Monthly' => 12, 'Quarterly' => 4, 'Half-yearly' => 2, 'Yearly' => 1, 'Single' => 0 };
    public static final Set<String> STATUSES = new Set<String>{ 'Active', 'Lapsed', 'Paid-up', 'Matured', 'Surrendered' };
    private static final String FIELDS =
        'Id, Owner_Member__c, Owner_Member__r.First_Name__c, Owner_Member__r.Last_Name__c, Insurer__c, Plan_Name__c, Policy_Type__c, ' +
        'Policy_Number__c, Insured_Name__c, Sum_Assured__c, Premium__c, Frequency__c, Start_Date__c, Next_Due_Date__c, Policy_Term_Years__c, ' +
        'Premium_Term_Years__c, Maturity_Date__c, Maturity_Value__c, Nominee__c, Tax_Section__c, Pay_From_Account__c, Pay_From_Account__r.Name, ' +
        'Bill__c, Status__c, Notes__c';

    public static List<SavingsDtos.Policy> policies(UserContext ctx) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'READ');
        List<Insurance_Policy__c> rows = query(ctx, null);
        Set<Id> billIds = new Set<Id>();
        for (Insurance_Policy__c x : rows) {
            if (x.Bill__c != null) {
                billIds.add(x.Bill__c);
            }
        }
        Map<Id, Bill_Instance__c> openByBill = new Map<Id, Bill_Instance__c>();
        if (!billIds.isEmpty()) {
            for (Bill_Instance__c i : new CommitmentSelector(ctx).instances(billIds, CommitmentSelector.OPEN_BILL, null)) {
                if (!openByBill.containsKey(i.Bill__c)) {
                    openByBill.put(i.Bill__c, i);
                }
            }
        }
        LedgerScope scope = new LedgerScope(ctx);
        List<SavingsDtos.Policy> result = new List<SavingsDtos.Policy>();
        for (Insurance_Policy__c x : rows) {
            result.add(dto(ctx, scope, x, openByBill.get(x.Bill__c), Date.today()));
        }
        return result;
    }

    private static List<Insurance_Policy__c> query(UserContext ctx, Id onlyId) {
        Map<String, Object> binds = new Map<String, Object>{ 'fid' => ctx.familyId };
        String soql = 'SELECT ' + FIELDS + ' FROM Insurance_Policy__c WHERE Family__c = :fid';
        if (!new LedgerScope(ctx).wholeFamily()) {
            soql += ' AND Owner_Member__c = :me';
            binds.put('me', ctx.userId);
        }
        if (onlyId != null) {
            soql += ' AND Id = :pid';
            binds.put('pid', onlyId);
        }
        soql += ' ORDER BY Status__c, Next_Due_Date__c NULLS LAST LIMIT 500';
        return (List<Insurance_Policy__c>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    public static SavingsDtos.Policy get(UserContext ctx, Id policyId) {
        for (SavingsDtos.Policy p : policies(ctx)) {
            if (p.id == policyId) {
                return p;
            }
        }
        throw new PortalException('NOT_FOUND').withError('We couldn\'t find that policy.');
    }

    @TestVisible
    private static SavingsDtos.Policy dto(UserContext ctx, LedgerScope scope, Insurance_Policy__c x, Bill_Instance__c open, Date today) {
        SavingsDtos.Policy d = new SavingsDtos.Policy();
        d.id = x.Id;
        d.insurer = x.Insurer__c;
        d.planName = x.Plan_Name__c;
        d.policyType = x.Policy_Type__c;
        d.ownerId = x.Owner_Member__c;
        d.ownerName = x.Owner_Member__c == null ? null : FinanceDtos.personName(x.Owner_Member__r?.First_Name__c, x.Owner_Member__r?.Last_Name__c);
        d.canManage = AccessGuard.can(ctx, 'ACCOUNTS', 'EDIT') && (scope.wholeFamily() && ctx.isAdmin() || x.Owner_Member__c == ctx.userId) && ctx.role != 'Viewer';
        d.policyNumber = d.canManage ? x.Policy_Number__c : DepositDtos.mask(x.Policy_Number__c);
        d.policyNumberMasked = DepositDtos.mask(x.Policy_Number__c);
        d.insuredName = x.Insured_Name__c;
        d.sumAssured = x.Sum_Assured__c;
        d.premium = x.Premium__c;
        d.frequency = x.Frequency__c;
        Integer perYear = PER_YEAR.containsKey(x.Frequency__c) ? PER_YEAR.get(x.Frequency__c) : 0;
        d.yearlyPremium = x.Premium__c == null ? 0 : x.Premium__c * perYear;
        d.startDate = x.Start_Date__c;
        d.policyTermYears = x.Policy_Term_Years__c == null ? null : x.Policy_Term_Years__c.intValue();
        d.premiumTermYears = x.Premium_Term_Years__c == null ? null : x.Premium_Term_Years__c.intValue();
        d.premiumsEnd = x.Start_Date__c == null || d.premiumTermYears == null ? null : x.Start_Date__c.addYears(d.premiumTermYears).addDays(-1);
        d.maturityDate = x.Maturity_Date__c;
        d.maturityValue = x.Maturity_Value__c;
        d.nominee = x.Nominee__c;
        d.taxSection = x.Tax_Section__c;
        d.payFromAccountId = x.Pay_From_Account__c;
        d.payFromAccountName = x.Pay_From_Account__r?.Name;
        d.billId = x.Bill__c;
        d.status = x.Status__c == null ? 'Active' : x.Status__c;
        d.notes = x.Notes__c;
        d.graceDays = x.Frequency__c == 'Monthly' ? 15 : 30;
        d.nextDueDate = open != null ? open.Due_Date__c : x.Next_Due_Date__c;
        d.openInstanceId = open?.Id;
        d.premiumState = premiumState(d, today);
        d.graceEnds = d.nextDueDate == null ? null : d.nextDueDate.addDays(d.graceDays);
        d.taxWarnings = taxWarnings(d);
        return d;
    }

    private static String premiumState(SavingsDtos.Policy d, Date today) {
        if (d.status != 'Active' || d.frequency == 'Single') {
            return 'None';
        }
        if (d.premiumsEnd != null && today > d.premiumsEnd) {
            return 'Finished';
        }
        if (d.nextDueDate == null) {
            return 'None';
        }
        if (today > d.nextDueDate.addDays(d.graceDays)) {
            return 'Overdue';
        }
        if (today > d.nextDueDate) {
            return 'In grace';
        }
        return today.daysBetween(d.nextDueDate) <= 15 ? 'Due' : 'Upcoming';
    }

    @TestVisible
    private static List<String> taxWarnings(SavingsDtos.Policy d) {
        List<String> out = new List<String>();
        if (!LIFE.contains(d.policyType) || d.startDate == null || d.yearlyPremium == null || d.yearlyPremium <= 0) {
            return out;
        }
        if (d.sumAssured != null && d.sumAssured > 0 && d.startDate >= Date.newInstance(2012, 4, 1) && d.yearlyPremium > d.sumAssured * 0.1) {
            out.add('The yearly premium is over 10% of the sum assured, so only Rs ' + (d.sumAssured * 0.1).setScale(0).format() +
                ' a year counts for 80C, and the maturity amount is taxable.');
        }
        if (d.policyType == 'ULIP' && d.startDate >= Date.newInstance(2021, 2, 1) && d.yearlyPremium > 250000) {
            out.add('ULIP premium over Rs 2.5 lakh a year: gains at maturity are taxed as capital gains.');
        } else if (d.policyType != 'ULIP' && d.policyType != 'Term' && d.startDate >= Date.newInstance(2023, 4, 1) && d.yearlyPremium > 500000) {
            out.add('Yearly premium over Rs 5 lakh: the maturity amount is taxable under Section 10(10D).');
        }
        return out;
    }

    // ------------------------------------------------------------------ writes

    /**
     * { insurer, planName?, policyType, policyNumber?, ownerId?, insuredName?, sumAssured?, premium?, frequency,
     *   startDate?, nextDueDate?, policyTermYears?, premiumTermYears?, maturityValue?, nominee?, taxSection?,
     *   payFromAccountId?, status?, notes? } - a premium with a due date becomes a bill.
     */
    public static SavingsDtos.Policy save(UserContext ctx, Id policyId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ACCOUNTS', policyId == null ? 'CREATE' : 'EDIT');
        Insurance_Policy__c x = policyId == null
            ? new Insurance_Policy__c(Family__c = ctx.familyId, Owner_Member__c = ctx.userId, Status__c = 'Active')
            : editable(ctx, policyId);
        apply(ctx, x, body, policyId == null);
        upsert as system x;
        syncBill(ctx, x);
        AuditService.log(ctx, policyId == null ? 'POLICY_CREATED' : 'POLICY_UPDATED', 'Insurance_Policy__c', x.Id, x.Insurer__c);
        return get(ctx, x.Id);
    }

    /** Removes the policy and its premium bill; premiums already paid stay in the ledger. */
    public static void deletePolicy(UserContext ctx, Id policyId) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        Insurance_Policy__c x = editable(ctx, policyId);
        Id billId = x.Bill__c;
        delete as system x;
        if (billId != null) {
            delete as system new Bill__c(Id = billId);
        }
        AuditService.log(ctx, 'POLICY_DELETED', 'Insurance_Policy__c', x.Id, x.Insurer__c);
    }

    private static Insurance_Policy__c editable(UserContext ctx, Id policyId) {
        List<Insurance_Policy__c> rows = query(ctx, policyId);
        if (rows.isEmpty()) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that policy.');
        }
        Insurance_Policy__c x = rows[0];
        if (!(ctx.isAdmin() || x.Owner_Member__c == ctx.userId) || ctx.role == 'Viewer') {
            AuditService.log(ctx, 'ACCESS_DENIED', 'Insurance_Policy__c', x.Id, 'POLICY:EDIT');
            throw new PortalException('NOT_AUTHORIZED').withError('Only the policy holder or an admin can change this policy.');
        }
        return x;
    }

    /** The premium as a bill: created when a premium falls due, kept in step, paused when premiums stop. */
    private static void syncBill(UserContext ctx, Insurance_Policy__c x) {
        Boolean wanted = x.Status__c == 'Active' && x.Frequency__c != 'Single' && x.Premium__c != null && x.Premium__c > 0 && x.Next_Due_Date__c != null;
        if (x.Bill__c == null && !wanted) {
            return;
        }
        Map<String, Object> bill = new Map<String, Object>{
            'name' => (x.Insurer__c + ' premium' + (String.isBlank(x.Policy_Number__c) ? '' : ' · ' + x.Policy_Number__c.right(4))).left(80),
            'categoryId' => categoryFor(ctx, x.Policy_Type__c),
            'frequency' => x.Frequency__c,
            'expectedAmount' => x.Premium__c,
            'consumerNo' => x.Policy_Number__c,
            'active' => wanted,
            'responsibleId' => x.Owner_Member__c == null ? null : String.valueOf(x.Owner_Member__c)
        };
        if (x.Pay_From_Account__c != null) {
            bill.put('payFromAccountId', String.valueOf(x.Pay_From_Account__c));
        }
        if (x.Bill__c == null) {
            bill.put('nextDueDate', String.valueOf(x.Next_Due_Date__c));
            Id billId = BillService.createBill(ctx, bill).id;
            update as system new Insurance_Policy__c(Id = x.Id, Bill__c = billId);
        } else {
            BillService.updateBill(ctx, x.Bill__c, bill);
        }
    }

    private static String categoryFor(UserContext ctx, String policyType) {
        String name = policyType == 'Health' ? 'Health Insurance Premium' : policyType == 'Vehicle' ? 'Vehicle Insurance' : policyType == 'Home' ? 'Home Insurance' : 'Life / Term';
        Id fallback;
        for (Category__c c : CategoryService.ensureSeeded(ctx).all()) {
            if (c.Name == name) {
                return c.Id;
            }
            if (c.Name == 'Insurance') {
                fallback = c.Id;
            }
        }
        return fallback;
    }

    private static void apply(UserContext ctx, Insurance_Policy__c x, Map<String, Object> body, Boolean creating) {
        List<String> errors = new List<String>();
        if (creating || LedgerUtil.has(body, 'insurer')) {
            x.Insurer__c = LedgerUtil.text(body, 'insurer');
            if (String.isBlank(x.Insurer__c) || x.Insurer__c.length() > 80) {
                errors.add('Enter the insurer, e.g. LIC of India (up to 80 characters).');
            }
        }
        if (creating || LedgerUtil.has(body, 'policyType')) {
            x.Policy_Type__c = LedgerUtil.text(body, 'policyType');
            if (!TYPES.contains(x.Policy_Type__c)) {
                errors.add('Choose the type of policy.');
            }
        }
        if (creating || LedgerUtil.has(body, 'frequency')) {
            x.Frequency__c = LedgerUtil.text(body, 'frequency');
            if (!PER_YEAR.containsKey(x.Frequency__c)) {
                errors.add('Choose how often the premium is paid.');
            }
        }
        if (LedgerUtil.has(body, 'status')) {
            x.Status__c = LedgerUtil.text(body, 'status');
            if (!STATUSES.contains(x.Status__c)) {
                errors.add('Choose a valid policy status.');
            }
        }
        Map<String, Integer> texts = new Map<String, Integer>{ 'planName' => 80, 'policyNumber' => 40, 'insuredName' => 80, 'nominee' => 80, 'notes' => 255 };
        Map<String, String> fields = new Map<String, String>{
            'planName' => 'Plan_Name__c', 'policyNumber' => 'Policy_Number__c', 'insuredName' => 'Insured_Name__c', 'nominee' => 'Nominee__c', 'notes' => 'Notes__c'
        };
        for (String key : texts.keySet()) {
            if (LedgerUtil.has(body, key)) {
                x.put(fields.get(key), LedgerUtil.limited(LedgerUtil.text(body, key), texts.get(key), key));
            }
        }
        for (String key : new List<String>{ 'sumAssured', 'premium', 'maturityValue' }) {
            if (LedgerUtil.has(body, key)) {
                Decimal v = LedgerUtil.dec(body, key, key);
                if (v != null && (v < 0 || v > LedgerUtil.MAX_AMOUNT)) {
                    errors.add('Amounts must be positive.');
                }
                x.put(key == 'sumAssured' ? 'Sum_Assured__c' : key == 'premium' ? 'Premium__c' : 'Maturity_Value__c', v);
            }
        }
        if (LedgerUtil.has(body, 'startDate')) {
            x.Start_Date__c = LedgerUtil.dateValue(body, 'startDate', 'Policy start');
        }
        if (LedgerUtil.has(body, 'nextDueDate')) {
            x.Next_Due_Date__c = LedgerUtil.dateValue(body, 'nextDueDate', 'Next premium due');
        }
        for (String key : new List<String>{ 'policyTermYears', 'premiumTermYears' }) {
            if (LedgerUtil.has(body, key)) {
                Decimal v = LedgerUtil.dec(body, key, key);
                if (v != null && (v < 1 || v > 100 || v != v.round())) {
                    errors.add('Terms are whole years from 1 to 100.');
                }
                x.put(key == 'policyTermYears' ? 'Policy_Term_Years__c' : 'Premium_Term_Years__c', v);
            }
        }
        if (x.Premium_Term_Years__c != null && x.Policy_Term_Years__c != null && x.Premium_Term_Years__c > x.Policy_Term_Years__c) {
            errors.add('Premiums cannot be paid for longer than the policy runs.');
        }
        x.Maturity_Date__c = x.Start_Date__c == null || x.Policy_Term_Years__c == null ? null : x.Start_Date__c.addYears(x.Policy_Term_Years__c.intValue());
        if (LedgerUtil.has(body, 'taxSection')) {
            String section = LedgerUtil.text(body, 'taxSection');
            x.Tax_Section__c = String.isBlank(section) || section == 'None' ? null : section;
            if (x.Tax_Section__c != null && x.Tax_Section__c != '80C' && x.Tax_Section__c != '80D') {
                errors.add('Tax section can be 80C, 80D or none.');
            }
        } else if (creating) {
            x.Tax_Section__c = LIFE.contains(x.Policy_Type__c) ? '80C' : HEALTH.contains(x.Policy_Type__c) ? '80D' : null;
        }
        if (LedgerUtil.has(body, 'payFromAccountId')) {
            String id = LedgerUtil.text(body, 'payFromAccountId');
            x.Pay_From_Account__c = String.isBlank(id) ? null : TransactionService.usableAccount(ctx, VkfRest.toId(id)).Id;
        }
        if (creating && LedgerUtil.has(body, 'ownerId') && ctx.isAdmin()) {
            Id ownerId = VkfRest.toId(LedgerUtil.text(body, 'ownerId'));
            x.Owner_Member__c = ownerId == null ? ctx.userId : new PortalUserSelector(ctx).memberInFamily(ownerId).Id;
        }
        if (x.Frequency__c != null && x.Frequency__c != 'Single' && x.Status__c == 'Active' && (x.Premium__c == null || x.Premium__c <= 0)) {
            errors.add('Enter the premium amount.');
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }
    }
}
