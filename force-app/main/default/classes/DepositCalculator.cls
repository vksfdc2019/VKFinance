/**
 * Deposit maths the way Indian banks quote it.
 *
 * FD, cumulative: interest compounds every period (quarterly unless the bank says otherwise) for
 * the whole periods in the term; the broken period after the last one earns simple interest.
 * Deposits for less than 6 months earn simple interest only.
 *
 * FD, interest payout: interest is paid out each period, so the deposit returns its principal
 * plus any broken-period interest. Monthly payout is the quarter's interest discounted for the
 * months it arrives early.
 *
 * RD: instalments are paid at the start of each month and compound quarterly until maturity,
 * so with n instalments of R at r% the maturity is R × Σ (1 + r/400)^(k/3) for k = 1..n.
 */
public inherited sharing class DepositCalculator {
    public static final Integer SIMPLE_BELOW_MONTHS = 6;

    public static Integer periodMonths(String compounding) {
        return compounding == 'Monthly' ? 1 : compounding == 'Half-yearly' ? 6 : compounding == 'Yearly' ? 12 : 3;
    }

    /** Months between payouts, or null for a cumulative deposit. */
    public static Integer payoutMonths(String payout) {
        return payout == 'Monthly' ? 1 : payout == 'Quarterly' ? 3 : payout == 'Half-yearly' ? 6 : payout == 'Yearly' ? 12 : null;
    }

    public static Date maturityDate(Date start, Integer months, Integer days) {
        return start.addMonths(months == null ? 0 : months).addDays(days == null ? 0 : days);
    }

    /** True when the whole term is short enough for simple interest. */
    public static Boolean simpleOnly(Date start, Date maturity) {
        return start.addMonths(SIMPLE_BELOW_MONTHS) > maturity;
    }

    /** What a cumulative FD is worth on `asOf`, which is capped at maturity. */
    public static Decimal fdValue(Decimal principal, Decimal rate, String compounding, Date start, Date maturity, Date asOf) {
        Date upTo = asOf > maturity ? maturity : asOf;
        if (upTo <= start) {
            return principal;
        }
        Double r = rate.doubleValue() / 100;
        if (simpleOnly(start, maturity)) {
            return money(principal.doubleValue() * (1 + r * start.daysBetween(upTo) / 365));
        }
        Integer step = periodMonths(compounding);
        Integer periods = 0;
        while (start.addMonths(step * (periods + 1)) <= upTo) {
            periods++;
        }
        Date compounded = start.addMonths(step * periods);
        Double grown = principal.doubleValue() * Math.pow(1 + r * step / 12, periods);
        return money(grown * (1 + r * compounded.daysBetween(upTo) / 365));
    }

    /** Interest a payout FD pays each period. */
    public static Decimal payoutPerPeriod(Decimal principal, Decimal rate, String payout) {
        Double p = principal.doubleValue();
        Double r = rate.doubleValue() / 100;
        if (payout == 'Monthly') {
            // m paid at the end of months 1, 2 and 3, reinvested monthly, equals the quarter's interest.
            Double month = 1 + r / 12;
            return money(p * r / 4 / (1 + month + month * month));
        }
        return money(p * r * payoutMonths(payout) / 12);
    }

    /** Whole payout periods in the term. */
    public static Integer payoutCount(Date start, Date maturity, String payout) {
        Integer step = payoutMonths(payout);
        Integer n = 0;
        while (start.addMonths(step * (n + 1)) <= maturity) {
            n++;
        }
        return n;
    }

    /** Simple interest for the days after the last whole payout period, paid with the principal. */
    public static Decimal brokenPeriodInterest(Decimal principal, Decimal rate, Date start, Date maturity, String payout) {
        Date last = start.addMonths(payoutMonths(payout) * payoutCount(start, maturity, payout));
        return money(principal.doubleValue() * rate.doubleValue() / 100 * last.daysBetween(maturity) / 365);
    }

    /**
     * What an RD is worth on `asOf`: each instalment paid so far, grown for the whole months it has
     * been in. At maturity this is the bank's maturity amount.
     */
    public static Decimal rdValue(Decimal instalment, Decimal rate, Date start, Integer months, Date asOf) {
        Date maturity = start.addMonths(months);
        Date upTo = asOf > maturity ? maturity : asOf;
        Double quarter = 1 + rate.doubleValue() / 400;
        Double units = 0;
        for (Integer i = 0; i < months; i++) {
            Date paid = start.addMonths(i);
            if (paid > upTo) {
                break;
            }
            Double quarters = wholeMonths(paid, upTo) / (Double) 3;
            units += Math.pow(quarter, quarters);
        }
        return money(instalment.doubleValue() * units);
    }

    public static Decimal rdMaturity(Decimal instalment, Decimal rate, Integer months, Date start) {
        return rdValue(instalment, rate, start, months, start.addMonths(months));
    }

    /** RD instalments due on or before `asOf`. */
    public static Integer rdInstalmentsDue(Date start, Integer months, Date asOf) {
        if (asOf < start) {
            return 0;
        }
        return Math.min(months, wholeMonths(start, asOf) + 1);
    }

    /** Annualised yield of a cumulative deposit, so terms of different lengths compare fairly. */
    public static Decimal effectiveYield(Decimal invested, Decimal maturity, Date start, Date maturityDate) {
        Integer days = start.daysBetween(maturityDate);
        if (invested == null || invested <= 0 || maturity == null || days <= 0) {
            return null;
        }
        Double years = days / (Double) 365;
        return Decimal.valueOf((Math.pow(maturity.doubleValue() / invested.doubleValue(), 1 / years) - 1) * 100).setScale(2, RoundingMode.HALF_UP);
    }

    /** 1 April of the financial year `d` falls in. */
    public static Date financialYearStart(Date d) {
        return Date.newInstance(d.month() >= 4 ? d.year() : d.year() - 1, 4, 1);
    }

    public static String financialYearLabel(Date d) {
        Integer y = financialYearStart(d).year();
        return 'FY ' + y + '-' + String.valueOf(y + 1).right(2);
    }

    private static Integer wholeMonths(Date fromDate, Date toDate) {
        Integer m = fromDate.monthsBetween(toDate);
        return fromDate.addMonths(m) > toDate ? m - 1 : m;
    }

    private static Decimal money(Double value) {
        return Decimal.valueOf(value).setScale(2, RoundingMode.HALF_UP);
    }
}
