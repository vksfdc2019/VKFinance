/**
 * Indian small savings and retirement schemes: how each one runs and how to estimate its value.
 *
 * Rules (Post Office / Ministry of Finance, as last notified - rates are reviewed every quarter,
 * so the rate on the passbook or certificate always wins):
 *   PPF   - 15 full financial years after the year it was opened; Rs 500 to Rs 1.5 lakh a year;
 *           interest compounds yearly; 80C, and the interest and maturity are tax-free (EEE).
 *   SSY   - for a girl child under 10; deposits for 15 years, matures 21 years after opening;
 *           Rs 250 to Rs 1.5 lakh a year; 80C and EEE.
 *   NSC   - 5 years, compounds yearly, paid at maturity; 80C; the interest is taxable.
 *   KVP   - doubles in 115 months; no tax deduction; the interest is taxable.
 *   SCSS  - 60 and over; 5 years, interest paid every quarter; up to Rs 30 lakh; 80C.
 *   POMIS - 5 years, interest paid monthly; up to Rs 9 lakh (Rs 15 lakh joint); no deduction.
 *   PO TD - 1, 2, 3 or 5 years; interest worked out quarterly and paid yearly; the 5-year TD is 80C.
 *   PO RD - 5 years of monthly instalments, compounded quarterly.
 *   NPS   - market-linked to age 60; up to Rs 50,000 a year extra under 80CCD(1B).
 *   EPF   - employee share counts for 80C; the rate is declared each year.
 *   SGB   - 8 years; 2.5% a year on the issue price, paid half-yearly; tax-free gains at maturity.
 */
public inherited sharing class SchemeRules {
    public static final Decimal YEARLY_CAP = 150000;

    public class Rule {
        public String code;
        public String label;
        /** lump: one deposit; yearly: deposits through the year; monthly: fixed instalments; market: value tracked. */
        public String kind;
        public Decimal rate;
        public Integer months;
        public Decimal minAmount;
        public Decimal maxAmount;
        public String payout;
        public String taxSection;
        public String taxNote;

        Rule(String code, String label, String kind, Decimal rate, Integer months, Decimal minAmount, Decimal maxAmount, String payout, String taxSection, String taxNote) {
            this.code = code;
            this.label = label;
            this.kind = kind;
            this.rate = rate;
            this.months = months;
            this.minAmount = minAmount;
            this.maxAmount = maxAmount;
            this.payout = payout;
            this.taxSection = taxSection;
            this.taxNote = taxNote;
        }
    }

    public static final Map<String, Rule> RULES = new Map<String, Rule>{
        'PPF' => new Rule('PPF', 'Public Provident Fund', 'yearly', 7.1, 180, 500, YEARLY_CAP, 'On maturity', '80C', 'Tax-free interest and maturity (EEE)'),
        'SSY' => new Rule('SSY', 'Sukanya Samriddhi Yojana', 'yearly', 8.2, 252, 250, YEARLY_CAP, 'On maturity', '80C', 'Tax-free interest and maturity (EEE)'),
        'NSC' => new Rule('NSC', 'National Savings Certificate', 'lump', 7.7, 60, 1000, null, 'On maturity', '80C', 'Interest is taxable'),
        'KVP' => new Rule('KVP', 'Kisan Vikas Patra', 'lump', 7.5, 115, 1000, null, 'On maturity', null, 'No deduction; interest is taxable'),
        'SCSS' => new Rule('SCSS', 'Senior Citizens Savings Scheme', 'lump', 8.2, 60, 1000, 3000000, 'Quarterly', '80C', 'Interest is taxable'),
        'POMIS' => new Rule('POMIS', 'Post Office Monthly Income Scheme', 'lump', 7.4, 60, 1000, 900000, 'Monthly', null, 'No deduction; interest is taxable'),
        'PO_TD' => new Rule('PO_TD', 'Post Office Time Deposit', 'lump', 7.5, 60, 1000, null, 'Yearly', '80C', '80C for the 5-year deposit only; interest is taxable'),
        'PO_RD' => new Rule('PO_RD', 'Post Office Recurring Deposit', 'monthly', 6.7, 60, 100, null, 'On maturity', null, 'No deduction; interest is taxable'),
        'NPS' => new Rule('NPS', 'National Pension System', 'market', null, null, 1000, null, 'On maturity', '80CCD(1B)', 'Up to Rs 50,000 a year over and above 80C'),
        'EPF' => new Rule('EPF', 'Employees\' Provident Fund / VPF', 'yearly', 8.25, null, null, null, 'On maturity', '80C', 'Employee share counts for 80C'),
        'SGB' => new Rule('SGB', 'Sovereign Gold Bond', 'market', 2.5, 96, null, null, 'Half-yearly', null, 'Gains tax-free if held to maturity; the 2.5% interest is taxable'),
        'OTHER' => new Rule('OTHER', 'Other scheme', 'market', null, null, null, null, 'On maturity', null, null)
    };

    public static Rule of(String code) {
        return code == null ? null : RULES.get(code);
    }

    /** When the scheme matures; null when it runs until the holder says (NPS, EPF, other). */
    public static Date maturityDate(String code, Date start, Integer months) {
        if (start == null) {
            return null;
        }
        if (code == 'PPF') {
            // 15 complete financial years after the one it was opened in.
            return Date.newInstance(DepositCalculator.financialYearStart(start).year() + 16, 4, 1);
        }
        if (code == 'SSY') {
            return start.addYears(21);
        }
        return months == null || months <= 0 ? null : start.addMonths(months);
    }

    /** The last day deposits are accepted. */
    public static Date depositsCloseOn(String code, Date start, Date maturity) {
        if (start == null) {
            return null;
        }
        if (code == 'SSY') {
            return start.addYears(15).addDays(-1);
        }
        Rule r = of(code);
        if (r != null && r.kind == 'lump') {
            return start;
        }
        return maturity;
    }

    /** Interest paid out each period by an income scheme, so its maturity value is just the deposit. */
    public static Decimal payoutAmount(String code, Decimal principal, Decimal rate) {
        if (principal == null || rate == null) {
            return null;
        }
        Double r = rate.doubleValue() / 100;
        Double p = principal.doubleValue();
        if (code == 'SCSS') {
            return money(p * r / 4);
        }
        if (code == 'POMIS') {
            return money(p * r / 12);
        }
        if (code == 'PO_TD') {
            return money(p * (Math.pow(1 + r / 4, 4) - 1));
        }
        if (code == 'SGB') {
            return money(p * r / 2);
        }
        return null;
    }

    /**
     * Estimated value at maturity at the scheme's rate. Lump sums compound yearly (NSC, KVP) or are
     * paid back as invested (income schemes); PO RD uses the quarterly RD formula; PPF, SSY and EPF
     * grow today's balance and add the planned yearly deposit while deposits are open.
     */
    public static Decimal maturityValue(Savings_Scheme__c x, Decimal balance, Decimal contributedThisYear, Date today) {
        Rule rule = of(x.Scheme__c);
        if (rule == null || x.Rate__c == null || x.Maturity_Date__c == null) {
            return null;
        }
        Double r = x.Rate__c.doubleValue() / 100;
        if (x.Scheme__c == 'NSC' || x.Scheme__c == 'KVP') {
            Decimal principal = x.Principal__c == null ? balance : x.Principal__c;
            Integer months = x.Start_Date__c.monthsBetween(x.Maturity_Date__c);
            return principal == null ? null : money(principal.doubleValue() * Math.pow(1 + r, months / (Double) 12));
        }
        if (rule.kind == 'lump') {
            return x.Principal__c == null ? balance : x.Principal__c;
        }
        if (x.Scheme__c == 'PO_RD') {
            if (x.Planned_Contribution__c == null) {
                return null;
            }
            return DepositCalculator.rdMaturity(x.Planned_Contribution__c, x.Rate__c, x.Start_Date__c.monthsBetween(x.Maturity_Date__c), x.Start_Date__c);
        }
        if (rule.kind == 'yearly' || (rule.kind == 'market' && x.Scheme__c == 'NPS')) {
            Date asOf = today > x.Maturity_Date__c ? x.Maturity_Date__c : today;
            Double years = asOf.daysBetween(x.Maturity_Date__c) / (Double) 365.25;
            Double value = (balance == null ? 0 : balance.doubleValue()) * Math.pow(1 + r, years);
            Decimal yearly = x.Planned_Contribution__c == null ? 0 : x.Planned_Contribution__c;
            Date closes = depositsCloseOn(x.Scheme__c, x.Start_Date__c, x.Maturity_Date__c);
            Integer first = contributedThisYear != null && yearly > 0 && contributedThisYear >= yearly ? 1 : 0;
            for (Integer k = first; yearly > 0 && k < 60; k++) {
                Date deposit = today.addYears(k);
                if (deposit > closes || deposit >= x.Maturity_Date__c) {
                    break;
                }
                value += yearly.doubleValue() * Math.pow(1 + r, deposit.daysBetween(x.Maturity_Date__c) / (Double) 365.25);
            }
            return money(value);
        }
        return null;
    }

    private static Decimal money(Double value) {
        return Decimal.valueOf(value).setScale(2, RoundingMode.HALF_UP);
    }
}
