/**
 * Small parsing and money helpers shared by the ledger services. Request values arrive
 * as untyped JSON, so every reader here validates and throws VALIDATION with a clear message.
 */
public inherited sharing class LedgerUtil {
    public static final Decimal MAX_AMOUNT = 9999999999.99;
    public static final Set<String> ASSET_TYPES = new Set<String>{ 'Savings', 'Current', 'Cash', 'UPI Wallet', 'Fixed Deposit', 'Recurring Deposit', 'Investment' };
    public static final Set<String> LIABILITY_TYPES = new Set<String>{ 'Credit Card', 'Loan' };
    public static final Set<String> PAYMENT_MODES = new Set<String>{
        'UPI', 'Cash', 'Debit Card', 'Credit Card', 'NEFT/IMPS', 'Net Banking', 'Cheque', 'Auto-debit', 'Other'
    };

    public static Boolean isLiability(String accountType) {
        return LIABILITY_TYPES.contains(accountType);
    }

    public static Boolean has(Map<String, Object> body, String key) {
        return body != null && body.containsKey(key);
    }

    public static String text(Map<String, Object> body, String key) {
        Object value = body == null ? null : body.get(key);
        if (value == null) {
            return null;
        }
        String s = String.valueOf(value).trim();
        return s.length() == 0 ? null : s;
    }

    public static Decimal dec(Map<String, Object> body, String key, String label) {
        Object value = body == null ? null : body.get(key);
        if (value == null || (value instanceof String && String.isBlank((String) value))) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value).trim());
        } catch (Exception e) {
            throw new PortalException('VALIDATION').withError(label + ' must be a number.');
        }
    }

    public static Boolean bool(Map<String, Object> body, String key) {
        Object value = body == null ? null : body.get(key);
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return value != null && String.valueOf(value).equalsIgnoreCase('true');
    }

    public static Date dateValue(String value, String label) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Date.valueOf(value.trim().left(10));
        } catch (Exception e) {
            throw new PortalException('VALIDATION').withError(label + ' must be a date like 2026-10-27.');
        }
    }

    public static Date dateValue(Map<String, Object> body, String key, String label) {
        return dateValue(text(body, key), label);
    }

    /** 'yyyy-MM' -> first day of that month; blank -> first day of the current month. */
    public static Date monthStart(String month) {
        if (String.isBlank(month)) {
            Date today = Date.today();
            return Date.newInstance(today.year(), today.month(), 1);
        }
        Matcher m = Pattern.compile('^(\\d{4})-(\\d{2})$').matcher(month.trim());
        if (!m.matches() || Integer.valueOf(m.group(2)) < 1 || Integer.valueOf(m.group(2)) > 12) {
            throw new PortalException('VALIDATION').withError('Month must look like 2026-10.');
        }
        return Date.newInstance(Integer.valueOf(m.group(1)), Integer.valueOf(m.group(2)), 1);
    }

    public static Date monthEnd(Date start) {
        return start.addMonths(1).addDays(-1);
    }

    public static String monthKey(Date d) {
        return d.year() + '-' + (d.month() < 10 ? '0' : '') + d.month();
    }

    /** Validates a positive money amount and rounds it to paise. */
    public static Decimal amount(Decimal value, String label) {
        if (value == null || value <= 0) {
            throw new PortalException('VALIDATION').withError(label + ' must be more than zero.');
        }
        if (value > MAX_AMOUNT) {
            throw new PortalException('VALIDATION').withError(label + ' is too large.');
        }
        return value.setScale(2, RoundingMode.HALF_UP);
    }

    /** A transaction date: not before 2000 and at most a year ahead. */
    public static Date txnDate(Date value) {
        if (value == null) {
            throw new PortalException('VALIDATION').withError('Date is required.');
        }
        if (value < Date.newInstance(2000, 1, 1) || value > Date.today().addDays(366)) {
            throw new PortalException('VALIDATION').withError('Date must be between 2000 and a year from today.');
        }
        return value;
    }

    public static String limited(String value, Integer max, String label) {
        if (value != null && value.length() > max) {
            throw new PortalException('VALIDATION').withError(label + ' can be up to ' + max + ' characters.');
        }
        return value;
    }

    public static Decimal zeroIfNull(Object value) {
        return value == null ? 0 : (Decimal) value;
    }
}