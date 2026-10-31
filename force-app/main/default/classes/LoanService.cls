/**
 * Loans and EMIs. Each loan owns a Loan-type account whose ledger balance is the outstanding
 * principal - so payments, prepayments and voids all flow through the normal ledger. Only
 * the next WINDOW instalments are stored; the full schedule is computed on demand.
 *
 * Paying an EMI posts: interest as an Expense (EMI and Loans -> Loan Interest) and principal
 * as two linked legs (bank Debit, loan account Credit) - all three share one group id.
 */
public without sharing class LoanService {
    public static final Integer WINDOW = 12;
    public static final List<String> TYPES = new List<String>{ 'Home', 'Car', 'Personal', 'Education', 'Gold', 'Consumer Durable', 'Card EMI', 'Other' };
    public static final List<String> RATE_TYPES = new List<String>{ 'Fixed', 'Floating' };

    public static String statusFor(Date due, Date today) {
        return due < today ? 'Overdue' : due <= today.addDays(7) ? 'Due' : 'Upcoming';
    }

    private static Decimal outstanding(Loan__c l) {
        if (l.Loan_Account__r != null && l.Loan_Account__r.Current_Balance__c != null) {
            return l.Loan_Account__r.Current_Balance__c;
        }
        return LedgerUtil.zeroIfNull(l.Outstanding_Principal__c);
    }

    private static Loan__c visible(UserContext ctx, CommitmentSelector selector, Id loanId) {
        Loan__c l = selector.loanById(loanId);
        if (!new LedgerScope(ctx).wholeFamily() && l.Borrower_Member__c != ctx.userId) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        return l;
    }

    public static List<CommitmentDtos.Loan> listLoans(UserContext ctx) {
        AccessGuard.require(ctx, 'LOANS', 'READ');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        List<Loan__c> loans = selector.loans(new LedgerScope(ctx).wholeFamily() ? null : ctx.userId);
        Map<Id, EMI_Installment__c> nextByLoan = new Map<Id, EMI_Installment__c>();
        for (EMI_Installment__c i : selector.installments(new Map<Id, Loan__c>(loans).keySet(), CommitmentSelector.OPEN_EMI)) {
            if (!nextByLoan.containsKey(i.Loan__c)) {
                nextByLoan.put(i.Loan__c, i);
            }
        }
        List<CommitmentDtos.Loan> result = new List<CommitmentDtos.Loan>();
        for (Loan__c l : loans) {
            result.add(dto(ctx, l, nextByLoan.get(l.Id)));
        }
        markDeletable(result);
        return result;
    }

    /** Counts the EMIs paid here; a loan can be deleted while nothing has been paid or adjusted on its account. */
    private static void markDeletable(List<CommitmentDtos.Loan> loans) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> loanIds = new Set<Id>();
        for (CommitmentDtos.Loan d : loans) {
            accountIds.add(d.loanAccountId);
            loanIds.add(d.id);
        }
        Map<Id, Integer> paidByLoan = new Map<Id, Integer>();
        for (AggregateResult r : [SELECT Loan__c l, COUNT(Id) n FROM EMI_Installment__c WHERE Loan__c IN :loanIds AND Status__c = 'Paid' WITH SYSTEM_MODE GROUP BY Loan__c]) {
            paidByLoan.put((Id) r.get('l'), (Integer) r.get('n'));
        }
        for (CommitmentDtos.Loan d : loans) {
            d.installmentsPaidHere = paidByLoan.containsKey(d.id) ? paidByLoan.get(d.id) : 0;
        }
        Set<Id> used = new Set<Id>();
        for (AggregateResult r : [SELECT Account__c a FROM Transaction__c WHERE Account__c IN :accountIds WITH SYSTEM_MODE GROUP BY Account__c]) {
            used.add((Id) r.get('a'));
        }
        for (CommitmentDtos.Loan d : loans) {
            d.canDelete = d.canEdit && d.installmentsPaidHere == 0 && !used.contains(d.loanAccountId);
        }
    }

    private static CommitmentDtos.Loan dto(UserContext ctx, Loan__c l, EMI_Installment__c next) {
        CommitmentDtos.Loan d = new CommitmentDtos.Loan();
        d.id = l.Id;
        d.name = l.Name;
        d.lender = l.Lender__c;
        d.loanType = l.Loan_Type__c;
        d.principal = l.Principal__c;
        d.annualRate = l.Annual_Rate__c;
        d.rateType = l.Rate_Type__c == null ? 'Fixed' : l.Rate_Type__c;
        d.tenureMonths = l.Tenure_Months__c == null ? null : l.Tenure_Months__c.intValue();
        d.firstEmiDate = l.Start_Date__c;
        d.emi = l.EMI_Amount__c;
        d.outstanding = Math.max(0, outstanding(l));
        d.installmentsPaid = l.Installments_Paid__c == null ? 0 : l.Installments_Paid__c.intValue();
        d.repaidPct = l.Principal__c == null || l.Principal__c == 0 ? 0 : ((l.Principal__c - d.outstanding) / l.Principal__c * 100).setScale(1, RoundingMode.HALF_UP);
        d.debitAccountId = l.Debit_Account__c;
        d.debitAccountName = l.Debit_Account__r?.Name;
        d.loanAccountId = l.Loan_Account__c;
        d.autoDebit = l.Auto_Debit__c;
        d.status = l.Status__c;
        d.borrowerId = l.Borrower_Member__c;
        d.borrowerName = l.Borrower_Member__c == null ? null : FinanceDtos.personName(l.Borrower_Member__r?.First_Name__c, l.Borrower_Member__r?.Last_Name__c);
        d.next = next == null ? null : CommitmentDtos.installment(next);
        d.canPay = AccessGuard.can(ctx, 'LOANS', 'PAY') && l.Status__c == 'Active';
        d.canEdit = AccessGuard.can(ctx, 'LOANS', 'EDIT');
        d.loanAccountNumberMasked = DepositDtos.mask(l.Loan_Account_No__c);
        d.loanAccountNumber = d.canEdit ? l.Loan_Account_No__c : d.loanAccountNumberMasked;
        d.interestRemaining = 0;
        d.installmentsLeft = 0;
        if (l.Status__c == 'Active' && d.outstanding > 0 && l.EMI_Amount__c != null && l.EMI_Amount__c > 0) {
            Integer no = d.installmentsPaid + 1;
            List<EmiCalculator.Row> rows = EmiCalculator.schedule(d.outstanding, l.Annual_Rate__c, l.EMI_Amount__c, no, l.Start_Date__c.addMonths(no - 1), 600);
            for (EmiCalculator.Row r : rows) {
                d.interestRemaining += r.interest;
            }
            d.installmentsLeft = rows.size();
            d.payoffDate = rows.isEmpty() ? null : rows[rows.size() - 1].dueDate;
        }
        return d;
    }

    public static CommitmentDtos.Loan createLoan(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'LOANS', 'CREATE');
        List<String> errors = new List<String>();
        String name = LedgerUtil.text(body, 'name');
        if (String.isBlank(name) || name.length() > 80) {
            errors.add('Loan name is required (up to 80 characters).');
        }
        String loanType = LedgerUtil.text(body, 'loanType');
        if (!TYPES.contains(loanType)) {
            errors.add('Choose a loan type.');
        }
        Decimal principal = LedgerUtil.dec(body, 'principal', 'Loan amount');
        Decimal rate = LedgerUtil.dec(body, 'annualRate', 'Interest rate');
        Decimal tenure = LedgerUtil.dec(body, 'tenureMonths', 'Tenure');
        Date firstEmi = LedgerUtil.dateValue(body, 'firstEmiDate', 'First EMI date');
        Decimal paidAlready = LedgerUtil.dec(body, 'installmentsPaid', 'EMIs already paid');
        Decimal bankOutstanding = LedgerUtil.dec(body, 'outstandingAmount', 'Outstanding amount');
        String rateType = String.isBlank(LedgerUtil.text(body, 'rateType')) ? 'Fixed' : LedgerUtil.text(body, 'rateType');
        if (!RATE_TYPES.contains(rateType)) {
            errors.add('Choose fixed or floating interest.');
        }
        if (principal == null || principal <= 0 || principal > LedgerUtil.MAX_AMOUNT) {
            errors.add('Loan amount must be more than zero.');
        }
        if (rate == null || rate < 0 || rate > 50) {
            errors.add('Interest rate must be between 0 and 50%.');
        }
        if (tenure == null || tenure < 1 || tenure > 480 || tenure.scale() > 0 && tenure != tenure.round()) {
            errors.add('Tenure must be between 1 and 480 months.');
        }
        if (firstEmi == null) {
            errors.add('First EMI date is required.');
        }
        Integer paid = paidAlready == null ? 0 : paidAlready.intValue();
        if (tenure != null && (paid < 0 || paid >= tenure)) {
            errors.add('EMIs already paid must be less than the tenure.');
        }
        if (bankOutstanding != null && principal != null && (bankOutstanding <= 0 || bankOutstanding > principal)) {
            errors.add('Outstanding amount must be more than zero and no more than the loan amount.');
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }
        Decimal emi = LedgerUtil.dec(body, 'emiAmount', 'EMI');
        emi = emi == null ? EmiCalculator.emi(principal, rate, tenure.intValue()) : LedgerUtil.amount(emi, 'EMI');
        // The bank's own outstanding figure wins over our reconstruction of the EMIs already paid.
        Decimal owed = bankOutstanding != null ? bankOutstanding.setScale(2, RoundingMode.HALF_UP) : EmiCalculator.outstandingAfter(principal, rate, emi, paid);

        Id debitId = VkfRest.toId(LedgerUtil.text(body, 'debitAccountId'));
        Financial_Account__c debit = debitId == null ? null : TransactionService.usableAccount(ctx, debitId);
        if (debit != null && LedgerUtil.isLiability(debit.Type__c)) {
            throw new PortalException('VALIDATION').withError('EMIs are paid from a bank, cash or wallet account.');
        }
        Boolean autoDebit = LedgerUtil.bool(body, 'autoDebit');
        if (autoDebit && debit == null) {
            throw new PortalException('VALIDATION').withError('Auto-debit needs the account the EMI is taken from.');
        }
        Id borrower = new LedgerScope(ctx).memberFor(VkfRest.toId(LedgerUtil.text(body, 'borrowerId')), new PortalUserSelector(ctx));
        String lender = LedgerUtil.limited(LedgerUtil.text(body, 'lender'), 80, 'Lender');
        String accountNo = accountNumber(LedgerUtil.text(body, 'loanAccountNumber'));

        Financial_Account__c loanAccount = new Financial_Account__c(
            Family__c = ctx.familyId, Name = name, Type__c = 'Loan', Institution__c = lender, Opening_Balance__c = owed,
            Current_Balance__c = owed, Opening_Date__c = Date.today(), Owner_Member__c = borrower, Color__c = 'rose', Status__c = 'Active'
        );
        insert as system loanAccount;
        Loan__c loan = new Loan__c(
            Family__c = ctx.familyId, Name = name, Lender__c = lender, Loan_Type__c = loanType, Principal__c = principal,
            Annual_Rate__c = rate, Rate_Type__c = rateType, Tenure_Months__c = tenure, Start_Date__c = firstEmi, EMI_Amount__c = emi, Outstanding_Principal__c = owed,
            Installments_Paid__c = paid, Debit_Account__c = debit?.Id, Loan_Account__c = loanAccount.Id, Auto_Debit__c = autoDebit,
            Borrower_Member__c = borrower, Status__c = 'Active', Loan_Account_No__c = accountNo
        );
        insert as system loan;
        syncWindow(loan.Id);
        AuditService.log(ctx, 'LOAN_CREATED', 'Loan__c', loan.Id, name + ' ' + principal);
        return listOne(ctx, loan.Id);
    }

    /** Fields that change the loan's maths; editing any of them re-prices the loan. */
    private static final Set<String> TERMS = new Set<String>{
        'principal', 'annualRate', 'tenureMonths', 'firstEmiDate', 'emiAmount', 'installmentsPaid', 'outstandingAmount'
    };

    /**
     * Edits a loan. Details (name, lender, account number, type, borrower, debit account) just change.
     * A correction to the terms re-prices it: EMIs paid here keep their numbers, the outstanding becomes
     * the bank's figure (or is worked out again), and the loan account's ledger follows - by moving its
     * opening balance while it has no entries, otherwise with one adjustment entry.
     */
    public static CommitmentDtos.Loan updateLoan(UserContext ctx, Id loanId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'LOANS', 'EDIT');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        Loan__c l = visible(ctx, selector, loanId);
        Loan__c changes = new Loan__c(Id = l.Id);
        Financial_Account__c account = new Financial_Account__c(Id = l.Loan_Account__c);
        Boolean accountChanged = false;
        if (LedgerUtil.has(body, 'name')) {
            changes.Name = LedgerUtil.text(body, 'name');
            if (String.isBlank(changes.Name) || changes.Name.length() > 80) {
                throw new PortalException('VALIDATION').withError('Loan name is required (up to 80 characters).');
            }
            account.Name = changes.Name;
            accountChanged = true;
        }
        if (LedgerUtil.has(body, 'lender')) {
            changes.Lender__c = LedgerUtil.limited(LedgerUtil.text(body, 'lender'), 80, 'Lender');
            account.Institution__c = changes.Lender__c;
            accountChanged = true;
        }
        if (LedgerUtil.has(body, 'loanType')) {
            changes.Loan_Type__c = LedgerUtil.text(body, 'loanType');
            if (!TYPES.contains(changes.Loan_Type__c)) {
                throw new PortalException('VALIDATION').withError('Choose a loan type.');
            }
        }
        if (LedgerUtil.has(body, 'loanAccountNumber')) {
            changes.Loan_Account_No__c = accountNumber(LedgerUtil.text(body, 'loanAccountNumber'));
        }
        if (LedgerUtil.has(body, 'rateType')) {
            changes.Rate_Type__c = LedgerUtil.text(body, 'rateType');
            if (!RATE_TYPES.contains(changes.Rate_Type__c)) {
                throw new PortalException('VALIDATION').withError('Choose fixed or floating interest.');
            }
        }
        if (LedgerUtil.has(body, 'borrowerId')) {
            changes.Borrower_Member__c = new LedgerScope(ctx).memberFor(VkfRest.toId(LedgerUtil.text(body, 'borrowerId')), new PortalUserSelector(ctx));
            account.Owner_Member__c = changes.Borrower_Member__c;
            accountChanged = true;
        }
        if (LedgerUtil.has(body, 'debitAccountId')) {
            Id debitId = VkfRest.toId(LedgerUtil.text(body, 'debitAccountId'));
            Financial_Account__c debit = debitId == null ? null : TransactionService.usableAccount(ctx, debitId);
            if (debit != null && LedgerUtil.isLiability(debit.Type__c)) {
                throw new PortalException('VALIDATION').withError('EMIs are paid from a bank, cash or wallet account.');
            }
            changes.Debit_Account__c = debit?.Id;
        }
        if (LedgerUtil.has(body, 'autoDebit')) {
            changes.Auto_Debit__c = LedgerUtil.bool(body, 'autoDebit');
        }
        if ((LedgerUtil.has(body, 'autoDebit') ? changes.Auto_Debit__c : l.Auto_Debit__c) == true &&
            (LedgerUtil.has(body, 'debitAccountId') ? changes.Debit_Account__c : l.Debit_Account__c) == null) {
            throw new PortalException('VALIDATION').withError('Auto-debit needs the account the EMI is taken from.');
        }
        Boolean reprice = false;
        for (String key : body.keySet()) {
            reprice = reprice || TERMS.contains(key);
        }
        Decimal owed;
        if (reprice) {
            owed = correctTerms(l, body, changes);
        }
        update as system changes;
        if (accountChanged) {
            update as system account;
        }
        if (reprice) {
            moveBalance(ctx, l, owed);
            syncWindow(l.Id);
        }
        AuditService.log(ctx, reprice ? 'LOAN_CORRECTED' : 'LOAN_UPDATED', 'Loan__c', l.Id, String.join(new List<String>(body.keySet()), ','));
        return listOne(ctx, l.Id);
    }

    /** Validates corrected terms onto `changes` and returns what is owed under them. */
    private static Decimal correctTerms(Loan__c l, Map<String, Object> body, Loan__c changes) {
        if (l.Status__c != 'Active') {
            throw new PortalException('CONFLICT').withError('This loan is closed.');
        }
        List<String> errors = new List<String>();
        Decimal principal = LedgerUtil.has(body, 'principal') ? LedgerUtil.dec(body, 'principal', 'Loan amount') : l.Principal__c;
        Decimal rate = LedgerUtil.has(body, 'annualRate') ? LedgerUtil.dec(body, 'annualRate', 'Interest rate') : l.Annual_Rate__c;
        Decimal tenure = LedgerUtil.has(body, 'tenureMonths') ? LedgerUtil.dec(body, 'tenureMonths', 'Tenure') : l.Tenure_Months__c;
        Date firstEmi = LedgerUtil.has(body, 'firstEmiDate') ? LedgerUtil.dateValue(body, 'firstEmiDate', 'First EMI date') : l.Start_Date__c;
        Decimal paidValue = LedgerUtil.has(body, 'installmentsPaid') ? LedgerUtil.dec(body, 'installmentsPaid', 'EMIs paid') : l.Installments_Paid__c;
        Decimal bankOutstanding = LedgerUtil.dec(body, 'outstandingAmount', 'Outstanding amount');
        if (principal == null || principal <= 0 || principal > LedgerUtil.MAX_AMOUNT) {
            errors.add('Loan amount must be more than zero.');
        }
        if (rate == null || rate < 0 || rate > 50) {
            errors.add('Interest rate must be between 0 and 50%.');
        }
        if (tenure == null || tenure < 1 || tenure > 480 || tenure != tenure.round()) {
            errors.add('Tenure must be between 1 and 480 months.');
        }
        if (firstEmi == null) {
            errors.add('First EMI date is required.');
        }
        Integer paid = paidValue == null ? 0 : paidValue.intValue();
        Integer paidHere = paidHere(l.Id);
        if (paid < paidHere) {
            errors.add(paidHere + (paidHere == 1 ? ' EMI was' : ' EMIs were') + ' recorded here, so EMIs paid can\'t be fewer.');
        }
        if (tenure != null && (paid < 0 || paid >= tenure)) {
            errors.add('EMIs paid must be less than the tenure.');
        }
        if (bankOutstanding != null && (bankOutstanding <= 0 || bankOutstanding > LedgerUtil.MAX_AMOUNT)) {
            errors.add('Outstanding amount must be more than zero.');
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }
        Decimal quotedEmi = LedgerUtil.dec(body, 'emiAmount', 'EMI');
        Boolean termsMoved = principal != l.Principal__c || rate != l.Annual_Rate__c || tenure != l.Tenure_Months__c;
        Decimal emi = quotedEmi != null
            ? LedgerUtil.amount(quotedEmi, 'EMI')
            : termsMoved || LedgerUtil.has(body, 'emiAmount') ? EmiCalculator.emi(principal, rate, tenure.intValue()) : l.EMI_Amount__c;

        changes.Principal__c = principal;
        changes.Annual_Rate__c = rate;
        changes.Tenure_Months__c = tenure;
        changes.Start_Date__c = firstEmi;
        changes.Installments_Paid__c = paid;
        changes.EMI_Amount__c = emi;
        // Without the bank's figure, work it out again only while nothing has been paid here.
        if (bankOutstanding != null) {
            return bankOutstanding.setScale(2, RoundingMode.HALF_UP);
        }
        return paidHere == 0 && !hasEntries(l.Loan_Account__c) ? EmiCalculator.outstandingAfter(principal, rate, emi, paid) : null;
    }

    /** Brings the loan account's balance to `owed`; null leaves the ledger as it is. */
    private static void moveBalance(UserContext ctx, Loan__c l, Decimal owed) {
        if (owed == null) {
            return;
        }
        if (hasEntries(l.Loan_Account__c)) {
            AccountService.reconcile(ctx, l.Loan_Account__c, new Map<String, Object>{
                'actualBalance' => owed, 'date' => String.valueOf(Date.today()), 'note' => 'Outstanding corrected to the bank\'s figure'
            });
        } else {
            update as system new Financial_Account__c(Id = l.Loan_Account__c, Opening_Balance__c = owed, Current_Balance__c = owed);
        }
    }

    /**
     * Removes a loan added by mistake, with its schedule and loan account. Only while nothing has been
     * paid or adjusted on it, so no history is lost; otherwise prepay it in full to close it.
     */
    public static void deleteLoan(UserContext ctx, Id loanId) {
        AccessGuard.require(ctx, 'LOANS', 'EDIT');
        Loan__c l = visible(ctx, new CommitmentSelector(ctx), loanId);
        if (hasEntries(l.Loan_Account__c) || paidHere(l.Id) > 0) {
            throw new PortalException('CONFLICT').withError('Payments are recorded against this loan, so it can\'t be deleted. Prepay the outstanding to close it instead.');
        }
        delete as system [SELECT Id FROM Loan_Rate_Change__c WHERE Loan__c = :l.Id WITH SYSTEM_MODE];
        delete as system [SELECT Id FROM EMI_Installment__c WHERE Loan__c = :l.Id WITH SYSTEM_MODE];
        delete as system new Loan__c(Id = l.Id);
        if (l.Loan_Account__c != null) {
            delete as system new Financial_Account__c(Id = l.Loan_Account__c);
        }
        AuditService.log(ctx, 'LOAN_DELETED', 'Loan__c', l.Id, l.Name);
    }

    private static Integer paidHere(Id loanId) {
        return [SELECT COUNT() FROM EMI_Installment__c WHERE Loan__c = :loanId AND Status__c = 'Paid' WITH SYSTEM_MODE];
    }

    private static Boolean hasEntries(Id accountId) {
        return accountId != null && [SELECT COUNT() FROM Transaction__c WHERE Account__c = :accountId WITH SYSTEM_MODE LIMIT 1] > 0;
    }

    private static final Pattern ACCOUNT_NUMBER = Pattern.compile('^[A-Za-z0-9/ -]{4,30}$');

    private static String accountNumber(String value) {
        if (value != null && !ACCOUNT_NUMBER.matcher(value).matches()) {
            throw new PortalException('VALIDATION').withError('Loan account number can be 4 to 30 letters, digits, spaces, / or -.');
        }
        return value;
    }

    /**
     * A new interest rate from the next unpaid EMI. The bank either keeps the EMI and changes how many are left
     * (adjust = Tenure) or keeps the end date and changes the EMI (adjust = EMI). An EMI quoted by the bank wins over the maths.
     */
    public static CommitmentDtos.Loan changeRate(UserContext ctx, Id loanId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'LOANS', 'EDIT');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        Loan__c l = visible(ctx, selector, loanId);
        if (l.Status__c != 'Active') {
            throw new PortalException('CONFLICT').withError('This loan is closed.');
        }
        Decimal rate = LedgerUtil.dec(body, 'annualRate', 'Interest rate');
        if (rate == null || rate < 0 || rate > 50) {
            throw new PortalException('VALIDATION').withError('Interest rate must be between 0 and 50%.');
        }
        String adjust = String.isBlank(LedgerUtil.text(body, 'adjust')) ? 'Tenure' : LedgerUtil.text(body, 'adjust');
        if (adjust != 'EMI' && adjust != 'Tenure') {
            throw new PortalException('VALIDATION').withError('Choose whether the EMI or the tenure changes.');
        }
        Decimal bankEmi = LedgerUtil.dec(body, 'emiAmount', 'EMI');
        if (rate == l.Annual_Rate__c && (bankEmi == null || bankEmi == l.EMI_Amount__c)) {
            throw new PortalException('VALIDATION').withError('The loan is already at ' + rate + '%.');
        }
        Date effective = LedgerUtil.has(body, 'effectiveDate') ? LedgerUtil.dateValue(body, 'effectiveDate', 'Effective date') : Date.today();
        String note = LedgerUtil.limited(LedgerUtil.text(body, 'note'), 255, 'Note');

        CommitmentDtos.Loan before = dto(ctx, l, null);
        if (before.outstanding <= 0) {
            throw new PortalException('CONFLICT').withError('Nothing is left to repay on this loan.');
        }
        Decimal emi = bankEmi != null
            ? LedgerUtil.amount(bankEmi, 'EMI')
            : adjust == 'EMI' ? EmiCalculator.emi(before.outstanding, rate, Math.max(1, before.installmentsLeft)) : l.EMI_Amount__c;
        List<EmiCalculator.Row> rows;
        try {
            rows = EmiCalculator.schedule(before.outstanding, rate, emi, 1, Date.today(), 600);
        } catch (PortalException e) {
            throw new PortalException('VALIDATION').withError('At ' + rate + '% an EMI of ' + emi + ' doesn\'t cover the interest - let the EMI change instead.');
        }
        if (rows.isEmpty() || rows[rows.size() - 1].closing > 0) {
            throw new PortalException('VALIDATION').withError('At ' + rate + '% this EMI would take over 50 years to repay - let the EMI change instead.');
        }

        insert as system new Loan_Rate_Change__c(
            Loan__c = l.Id, Family__c = ctx.familyId, Effective_Date__c = effective, Old_Rate__c = l.Annual_Rate__c, New_Rate__c = rate,
            Old_EMI__c = l.EMI_Amount__c, New_EMI__c = emi, Old_EMIs_Left__c = before.installmentsLeft, New_EMIs_Left__c = rows.size(),
            Outstanding__c = before.outstanding, Adjusted__c = bankEmi != null && bankEmi != l.EMI_Amount__c ? 'EMI' : adjust, Note__c = note
        );
        update as system new Loan__c(Id = l.Id, Annual_Rate__c = rate, EMI_Amount__c = emi);
        syncWindow(l.Id);
        AuditService.log(ctx, 'LOAN_RATE_CHANGED', 'Loan__c', l.Id, l.Annual_Rate__c + '% -> ' + rate + '%, EMI ' + emi);
        return listOne(ctx, l.Id);
    }

    public static List<CommitmentDtos.RateChange> rateChanges(UserContext ctx, Id loanId) {
        AccessGuard.require(ctx, 'LOANS', 'READ');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        Loan__c l = visible(ctx, selector, loanId);
        List<CommitmentDtos.RateChange> result = new List<CommitmentDtos.RateChange>();
        for (Loan_Rate_Change__c c : selector.rateChanges(l.Id)) {
            result.add(CommitmentDtos.rateChange(c));
        }
        return result;
    }

    public static CommitmentDtos.Schedule schedule(UserContext ctx, Id loanId) {
        AccessGuard.require(ctx, 'LOANS', 'READ');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        Loan__c l = visible(ctx, selector, loanId);
        CommitmentDtos.Schedule s = new CommitmentDtos.Schedule();
        s.loan = listOne(ctx, l.Id);
        for (EMI_Installment__c i : selector.installments(new Set<Id>{ l.Id }, new Set<String>{ 'Paid' })) {
            s.rows.add(CommitmentDtos.installment(i));
        }
        if (s.loan.outstanding > 0 && l.Status__c == 'Active') {
            Integer no = s.loan.installmentsPaid + 1;
            for (EmiCalculator.Row r : EmiCalculator.schedule(s.loan.outstanding, l.Annual_Rate__c, l.EMI_Amount__c, no, l.Start_Date__c.addMonths(no - 1), 600)) {
                CommitmentDtos.Installment d = new CommitmentDtos.Installment();
                d.no = r.no;
                d.dueDate = r.dueDate;
                d.emi = r.emi;
                d.principal = r.principal;
                d.interest = r.interest;
                d.closing = r.closing;
                d.status = statusFor(r.dueDate, Date.today());
                s.rows.add(d);
                s.totalInterestRemaining += r.interest;
            }
        }
        return s;
    }

    /** Pays the next instalment. */
    public static CommitmentDtos.Loan payEmi(UserContext ctx, Id loanId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'LOANS', 'PAY');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        Loan__c l = visible(ctx, selector, loanId);
        if (l.Status__c != 'Active') {
            throw new PortalException('CONFLICT').withError('This loan is closed.');
        }
        List<EMI_Installment__c> open = selector.installments(new Set<Id>{ l.Id }, CommitmentSelector.OPEN_EMI);
        if (open.isEmpty()) {
            syncWindow(l.Id);
            open = selector.installments(new Set<Id>{ l.Id }, CommitmentSelector.OPEN_EMI);
        }
        if (open.isEmpty()) {
            throw new PortalException('CONFLICT').withError('There is no instalment left to pay.');
        }
        EMI_Installment__c next = open[0];
        Financial_Account__c bank = payingAccount(ctx, l, body);
        Date paidOn = LedgerUtil.txnDate(LedgerUtil.has(body, 'date') ? LedgerUtil.dateValue(body, 'date', 'Date') : Date.today());
        String source = LedgerUtil.bool(body, 'auto') ? 'Auto-pay' : 'Manual';

        CategorySelector categories = CategoryService.ensureSeeded(ctx);
        Id interestCategory;
        for (Category__c c : categories.all()) {
            if (c.Name == 'Loan Interest' && c.Kind__c == 'Expense') {
                interestCategory = c.Id;
            }
        }
        String groupId = TokenService.newToken().left(32);
        List<Transaction__c> rows = new List<Transaction__c>();
        if (LedgerUtil.zeroIfNull(next.Interest_Part__c) > 0) {
            rows.add(new Transaction__c(
                Family__c = ctx.familyId, Account__c = bank.Id, Type__c = 'Expense', Direction__c = 'Debit', Amount__c = next.Interest_Part__c,
                Txn_Date__c = paidOn, Category__c = interestCategory, Payee__c = (l.Lender__c != null ? l.Lender__c : l.Name).left(120),
                Notes__c = ('EMI ' + next.Installment_No__c.intValue() + ' interest · ' + l.Name).left(255), Member__c = ctx.userId,
                EMI_Installment__c = next.Id, Transfer_Group_Id__c = groupId, Status__c = 'Cleared', Source__c = source
            ));
        }
        List<Transaction__c> pair = principalLegs(ctx, l, bank, next.Principal_Part__c, paidOn, 'EMI ' + next.Installment_No__c.intValue() + ' principal', groupId, source);
        for (Transaction__c t : pair) {
            t.EMI_Installment__c = next.Id;
        }
        rows.addAll(pair);
        insert as system rows;
        link(pair);
        update as system new EMI_Installment__c(Id = next.Id, Status__c = 'Paid', Paid_On__c = paidOn);
        update as system new Loan__c(Id = l.Id, Installments_Paid__c = LedgerUtil.zeroIfNull(l.Installments_Paid__c) + 1);
        syncWindow(l.Id);
        AuditService.log(ctx, 'EMI_PAID', 'Loan__c', l.Id, 'EMI ' + next.Installment_No__c + ' ' + next.EMI_Amount__c);
        return listOne(ctx, l.Id);
    }

    /** A principal-only part-payment. The EMI stays the same, so the loan ends sooner. */
    public static CommitmentDtos.Loan prepay(UserContext ctx, Id loanId, Map<String, Object> body) {
        AccessGuard.require(ctx, 'LOANS', 'PAY');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        Loan__c l = visible(ctx, selector, loanId);
        if (l.Status__c != 'Active') {
            throw new PortalException('CONFLICT').withError('This loan is closed.');
        }
        Decimal amount = LedgerUtil.amount(LedgerUtil.dec(body, 'amount', 'Amount'), 'Amount');
        if (amount > outstanding(l)) {
            throw new PortalException('VALIDATION').withError('That is more than the outstanding amount.');
        }
        Financial_Account__c bank = payingAccount(ctx, l, body);
        Date paidOn = LedgerUtil.txnDate(LedgerUtil.has(body, 'date') ? LedgerUtil.dateValue(body, 'date', 'Date') : Date.today());
        List<Transaction__c> pair = principalLegs(ctx, l, bank, amount, paidOn, 'Prepayment', TokenService.newToken().left(32), 'Manual');
        insert as system pair;
        link(pair);
        syncWindow(l.Id);
        AuditService.log(ctx, 'LOAN_PREPAID', 'Loan__c', l.Id, String.valueOf(amount));
        return listOne(ctx, l.Id);
    }

    /** After an EMI or prepayment is voided, reopen the instalment and rebuild the window. */
    public static void afterVoid(Set<Id> installmentIds, Set<Id> accountIds) {
        Map<Id, Integer> reopenedPerLoan = new Map<Id, Integer>();
        List<EMI_Installment__c> reopened = [
            SELECT Id, Loan__c, Due_Date__c, Status__c FROM EMI_Installment__c WHERE Id IN :installmentIds AND Status__c = 'Paid' WITH SYSTEM_MODE
        ];
        for (EMI_Installment__c i : reopened) {
            i.Status__c = statusFor(i.Due_Date__c, Date.today());
            i.Paid_On__c = null;
            reopenedPerLoan.put(i.Loan__c, (reopenedPerLoan.containsKey(i.Loan__c) ? reopenedPerLoan.get(i.Loan__c) : 0) + 1);
        }
        update as system reopened;
        Set<Id> loanIds = new Set<Id>(reopenedPerLoan.keySet());
        List<Loan__c> loans = [
            SELECT Id, Installments_Paid__c FROM Loan__c WHERE Id IN :loanIds OR Loan_Account__c IN :accountIds WITH SYSTEM_MODE
        ];
        for (Loan__c l : loans) {
            if (reopenedPerLoan.containsKey(l.Id)) {
                l.Installments_Paid__c = Math.max(0, LedgerUtil.zeroIfNull(l.Installments_Paid__c) - reopenedPerLoan.get(l.Id));
            }
        }
        update as system loans;
        for (Loan__c l : loans) {
            syncWindow(l.Id);
        }
    }

    /** Rebuilds the stored upcoming instalments from the ledger's outstanding balance. */
    public static void syncWindow(Id loanId) {
        Loan__c l = [
            SELECT Id, Family__c, Annual_Rate__c, EMI_Amount__c, Start_Date__c, Installments_Paid__c, Status__c, Outstanding_Principal__c,
                Loan_Account__c, Loan_Account__r.Current_Balance__c
            FROM Loan__c WHERE Id = :loanId WITH SYSTEM_MODE FOR UPDATE
        ];
        delete as system [SELECT Id FROM EMI_Installment__c WHERE Loan__c = :loanId AND Status__c IN :CommitmentSelector.OPEN_EMI WITH SYSTEM_MODE];
        Decimal owed = Math.max(0, outstanding(l));
        if (owed == 0) {
            update as system new Loan__c(Id = l.Id, Outstanding_Principal__c = 0, Status__c = 'Closed');
            return;
        }
        Integer no = (l.Installments_Paid__c == null ? 0 : l.Installments_Paid__c.intValue()) + 1;
        List<EMI_Installment__c> upcoming = new List<EMI_Installment__c>();
        for (EmiCalculator.Row r : EmiCalculator.schedule(owed, l.Annual_Rate__c, l.EMI_Amount__c, no, l.Start_Date__c.addMonths(no - 1), WINDOW)) {
            upcoming.add(new EMI_Installment__c(
                Loan__c = l.Id, Family__c = l.Family__c, Installment_No__c = r.no, Due_Date__c = r.dueDate, EMI_Amount__c = r.emi,
                Principal_Part__c = r.principal, Interest_Part__c = r.interest, Opening_Balance__c = r.opening, Closing_Balance__c = r.closing,
                Status__c = statusFor(r.dueDate, Date.today()), Unique_Key__c = l.Id + '-' + r.no
            ));
        }
        Database.upsert(upcoming, EMI_Installment__c.Unique_Key__c, true, AccessLevel.SYSTEM_MODE);
        update as system new Loan__c(Id = l.Id, Outstanding_Principal__c = owed, Status__c = 'Active');
    }

    /** Daily: refresh statuses, and rebuild windows that have run short. */
    public static void refresh(Id familyId, Date today) {
        List<EMI_Installment__c> changed = new List<EMI_Installment__c>();
        Map<Id, Integer> openPerLoan = new Map<Id, Integer>();
        for (EMI_Installment__c i : [
            SELECT Id, Loan__c, Due_Date__c, Status__c FROM EMI_Installment__c
            WHERE Family__c = :familyId AND Status__c IN :CommitmentSelector.OPEN_EMI WITH SYSTEM_MODE
        ]) {
            openPerLoan.put(i.Loan__c, (openPerLoan.containsKey(i.Loan__c) ? openPerLoan.get(i.Loan__c) : 0) + 1);
            String status = statusFor(i.Due_Date__c, today);
            if (status != i.Status__c) {
                changed.add(new EMI_Installment__c(Id = i.Id, Status__c = status));
            }
        }
        update as system changed;
        for (Loan__c l : [SELECT Id FROM Loan__c WHERE Family__c = :familyId AND Status__c = 'Active' WITH SYSTEM_MODE]) {
            Integer open = openPerLoan.containsKey(l.Id) ? openPerLoan.get(l.Id) : 0;
            if (open < WINDOW / 2) {
                syncWindow(l.Id);
            }
        }
    }

    private static CommitmentDtos.Loan listOne(UserContext ctx, Id loanId) {
        CommitmentSelector selector = new CommitmentSelector(ctx);
        Loan__c l = selector.loanById(loanId);
        List<EMI_Installment__c> open = selector.installments(new Set<Id>{ l.Id }, CommitmentSelector.OPEN_EMI);
        CommitmentDtos.Loan d = dto(ctx, l, open.isEmpty() ? null : open[0]);
        markDeletable(new List<CommitmentDtos.Loan>{ d });
        return d;
    }

    private static Financial_Account__c payingAccount(UserContext ctx, Loan__c l, Map<String, Object> body) {
        Id accountId = LedgerUtil.has(body, 'accountId') ? VkfRest.toId(LedgerUtil.text(body, 'accountId')) : l.Debit_Account__c;
        if (accountId == null) {
            throw new PortalException('VALIDATION').withError('Choose the account the EMI is paid from.');
        }
        Financial_Account__c bank = TransactionService.usableAccount(ctx, accountId);
        if (LedgerUtil.isLiability(bank.Type__c)) {
            throw new PortalException('VALIDATION').withError('EMIs are paid from a bank, cash or wallet account.');
        }
        return bank;
    }

    private static List<Transaction__c> principalLegs(
        UserContext ctx, Loan__c l, Financial_Account__c bank, Decimal amount, Date paidOn, String note, String groupId, String source
    ) {
        Id category = CategoryService.ensureSeeded(ctx).systemCategory('LOAN_PRINCIPAL')?.Id;
        Transaction__c outLeg = new Transaction__c(
            Family__c = ctx.familyId, Account__c = bank.Id, Type__c = 'EMI Payment', Direction__c = 'Debit', Amount__c = amount,
            Txn_Date__c = paidOn, Category__c = category, Payee__c = l.Name.left(120), Notes__c = (note + ' · ' + l.Name).left(255),
            Member__c = ctx.userId, Transfer_Group_Id__c = groupId, Status__c = 'Cleared', Source__c = source
        );
        Transaction__c inLeg = outLeg.clone(false, true);
        inLeg.Account__c = l.Loan_Account__c;
        inLeg.Direction__c = 'Credit';
        inLeg.Payee__c = bank.Name.left(120);
        inLeg.Member__c = l.Borrower_Member__c == null ? ctx.userId : l.Borrower_Member__c;
        return new List<Transaction__c>{ outLeg, inLeg };
    }

    private static void link(List<Transaction__c> pair) {
        update as system new List<Transaction__c>{
            new Transaction__c(Id = pair[0].Id, Counter_Transaction__c = pair[1].Id),
            new Transaction__c(Id = pair[1].Id, Counter_Transaction__c = pair[0].Id)
        };
    }
}