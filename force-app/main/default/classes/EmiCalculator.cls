/**
 * Loan maths. EMI = P × r × (1 + r)^n ÷ ((1 + r)^n − 1), r = annual rate ÷ 12 ÷ 100.
 * ₹10,00,000 at 9% for 60 months -> EMI ₹20,758; first instalment ₹7,500 interest + ₹13,258 principal.
 */
public inherited sharing class EmiCalculator {
    public class Row {
        public Integer no;
        public Date dueDate;
        public Decimal emi;
        public Decimal principal;
        public Decimal interest;
        public Decimal opening;
        public Decimal closing;
    }

    public static Decimal emi(Decimal principal, Decimal annualRate, Integer months) {
        if (principal == null || principal <= 0 || months == null || months <= 0) {
            throw new PortalException('VALIDATION').withError('Principal and tenure must be more than zero.');
        }
        if (annualRate == null || annualRate == 0) {
            return (principal / months).setScale(2, RoundingMode.HALF_UP);
        }
        Double r = annualRate.doubleValue() / 1200;
        Double factor = Math.pow(1 + r, months);
        return Decimal.valueOf(principal.doubleValue() * r * factor / (factor - 1)).setScale(2, RoundingMode.HALF_UP);
    }

    /** Monthly schedule from an outstanding balance until it is repaid (or maxRows). The last EMI absorbs rounding. */
    public static List<Row> schedule(Decimal outstanding, Decimal annualRate, Decimal emi, Integer firstNo, Date firstDue, Integer maxRows) {
        List<Row> rows = new List<Row>();
        Decimal balance = outstanding;
        Decimal r = annualRate == null ? 0 : annualRate / 1200;
        Integer i = 0;
        while (balance > 0 && i < maxRows) {
            Row row = new Row();
            row.no = firstNo + i;
            row.dueDate = firstDue.addMonths(i);
            row.opening = balance;
            row.interest = (balance * r).setScale(2, RoundingMode.HALF_UP);
            row.principal = emi - row.interest;
            if (row.principal <= 0) {
                throw new PortalException('VALIDATION').withError('The EMI is too small to ever repay this loan.');
            }
            if (row.principal >= balance) {
                row.principal = balance;
            }
            row.emi = row.principal + row.interest;
            row.closing = balance - row.principal;
            balance = row.closing;
            rows.add(row);
            i++;
        }
        return rows;
    }

    /** Outstanding principal after the first `paid` instalments of a fresh loan. */
    public static Decimal outstandingAfter(Decimal principal, Decimal annualRate, Decimal emi, Integer paid) {
        if (paid <= 0) {
            return principal;
        }
        List<Row> rows = schedule(principal, annualRate, emi, 1, Date.today(), paid);
        return rows.isEmpty() ? 0 : rows[rows.size() - 1].closing;
    }
}