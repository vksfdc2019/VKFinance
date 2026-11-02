/** Money position: what is available and what was spent, side by side for accounts, cards, bills and loans. */
public inherited sharing class PositionDtos {
    public class Position {
        public String month;
        public Date periodStart;
        public Date periodEnd;
        public Date asOf;
        public Boolean isCurrent;
        public String currencyCode;
        public Summary summary = new Summary();
        /** Null when the viewer cannot read that part (e.g. no BILLS:READ). */
        public BankSection bank;
        public CardSection cards;
        public BillSection bills;
        public LoanSection loans;
    }

    /** The headline: cash in hand, what this month still owes, and what is left after it. */
    public class Summary {
        public Decimal liquid = 0;
        public Decimal cardAvailable = 0;
        public Decimal owed = 0;
        public Decimal duesRemaining = 0;
        /** Liquid money less the dues still to pay this month; null for past months. */
        public Decimal leftAfterDues;
        public Decimal moneyIn = 0;
        public Decimal moneyOut = 0;
    }

    public class BankSection {
        /** Savings, current, cash and UPI wallets - money you can use today. */
        public Decimal available = 0;
        /** Fixed and recurring deposits and investments - yours, but not spendable today. */
        public Decimal locked = 0;
        public Decimal moneyIn = 0;
        public Decimal moneyOut = 0;
        public Decimal lowestBalance;
        public List<AccountLine> accounts = new List<AccountLine>();
    }

    public class AccountLine {
        public Id id;
        public String name;
        public String type;
        public String institution;
        public String last4;
        public String color;
        public String ownerName;
        public Boolean isShared;
        public Boolean liquid;
        public Decimal balance;
        public Decimal moneyIn = 0;
        public Decimal moneyOut = 0;
        public Date maturityDate;
        public Decimal maturityAmount;
    }

    public class CardSection {
        /** Shared limits count once, however many cards draw on them. */
        public Decimal totalLimit = 0;
        public Decimal used = 0;
        public Decimal available = 0;
        public Decimal utilisationPct;
        public Decimal spent = 0;
        public Decimal paid = 0;
        public Decimal dueNow = 0;
        public Decimal minimumDue = 0;
        public Date nextDueDate;
        public Integer overdueCount = 0;
        public List<CardLine> cards = new List<CardLine>();
    }

    public class CardLine {
        public Id id;
        public String name;
        public String institution;
        public String last4;
        public String network;
        public String color;
        public String ownerName;
        public Decimal creditLimit;
        public Decimal used;
        public Decimal available;
        public Decimal utilisationPct;
        public String sharedLimitName;
        public Decimal spent = 0;
        public Decimal paid = 0;
        public Decimal statementAmount;
        public Decimal minimumDue;
        public Decimal amountPaid;
        public Decimal dueRemaining = 0;
        public Date dueDate;
        public Date lateFeeAfter;
        public String statementStatus;
        public Date nextStatementDate;
    }

    public class BillSection {
        public Decimal due = 0;
        public Decimal paid = 0;
        public Decimal remaining = 0;
        /** Unpaid bills past their due date, from this month or earlier. */
        public Decimal overdue = 0;
        public Integer count = 0;
        public Integer paidCount = 0;
        public Integer overdueCount = 0;
        public List<CommitmentDtos.BillInstance> items = new List<CommitmentDtos.BillInstance>();
    }

    public class LoanSection {
        public Decimal borrowed = 0;
        public Decimal outstanding = 0;
        public Decimal repaid = 0;
        public Decimal repaidPct;
        public Decimal monthlyEmi = 0;
        public Decimal emiDue = 0;
        public Decimal emiPaid = 0;
        public Decimal emiRemaining = 0;
        public Decimal interestRemaining = 0;
        public Integer activeCount = 0;
        public Integer overdueCount = 0;
        public List<LoanLine> loans = new List<LoanLine>();
    }

    public class LoanLine {
        public CommitmentDtos.Loan loan;
        public Decimal emiThisMonth = 0;
        public Decimal paidThisMonth = 0;
        public Date dueThisMonth;
        /** Paid, Due, Overdue, or None when no EMI falls in the month. */
        public String monthStatus = 'None';
    }
}
