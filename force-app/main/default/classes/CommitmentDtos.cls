/** JSON shapes for bills, loans, card statements, recurring rules, dues and notifications. */
public inherited sharing class CommitmentDtos {
    public class Bill {
        public Id id;
        public String name;
        public Id categoryId;
        public String categoryName;
        public String icon;
        public String color;
        public String consumerNo;
        public String frequency;
        public Date nextDueDate;
        public Decimal expectedAmount;
        public Id payFromAccountId;
        public String payFromAccountName;
        public Id creditCardAccountId;
        public String creditCardAccountName;
        public Boolean autoPay;
        public Integer reminderDays;
        public Id responsibleId;
        public String responsibleName;
        public Boolean active;
        public Decimal paidLast12Months = 0;
    }

    public class BillInstance {
        public Id id;
        public Id billId;
        public String billName;
        public String categoryName;
        public String icon;
        public String color;
        public Date dueDate;
        public Decimal amountDue;
        public Decimal amountPaid;
        public String status;
        public Boolean autoPay;
        public Id payFromAccountId;
        public String responsibleName;
        public Id creditCardAccountId;
        public Integer daysLeft;
        public Boolean canPay;
    }

    public class BillsView {
        public List<Bill> bills = new List<Bill>();
        public List<BillInstance> open = new List<BillInstance>();
        public List<BillInstance> recentlyPaid = new List<BillInstance>();
        public Decimal dueNext30 = 0;
        public Decimal overdue = 0;
        public Boolean canEdit = false;
    }

    public class Loan {
        public Id id;
        public String name;
        public String lender;
        public String loanType;
        public Decimal principal;
        public Decimal annualRate;
        public Integer tenureMonths;
        public Date firstEmiDate;
        public Decimal emi;
        public Decimal outstanding;
        public Integer installmentsPaid;
        public Integer installmentsLeft;
        public Decimal repaidPct;
        public Decimal interestRemaining;
        public Date payoffDate;
        public Id debitAccountId;
        public String debitAccountName;
        public Id loanAccountId;
        public Boolean autoDebit;
        public String status;
        public Id borrowerId;
        public String borrowerName;
        public Installment next;
        public Boolean canPay;
    }

    public class Installment {
        public Id id;
        public Integer no;
        public Date dueDate;
        public Decimal emi;
        public Decimal principal;
        public Decimal interest;
        public Decimal closing;
        public String status;
        public Date paidOn;
    }

    public class Schedule {
        public Loan loan;
        public List<Installment> rows = new List<Installment>();
        public Decimal totalInterestRemaining = 0;
    }

    public class Statement {
        public Id id;
        public Id accountId;
        public Date cycleStart;
        public Date cycleEnd;
        public Decimal amount;
        public Decimal minimumDue;
        public Date dueDate;
        public Decimal amountPaid = 0;
        public String status;
    }

    public class Rule {
        public Id id;
        public String name;
        public String type;
        public Decimal amount;
        public Id accountId;
        public String accountName;
        public Id toAccountId;
        public String toAccountName;
        public Id categoryId;
        public String categoryName;
        public String icon;
        public String color;
        public String payee;
        public String paymentMode;
        public String frequency;
        public Date nextRunDate;
        public Date endDate;
        public String mode;
        public Boolean active;
        public Date lastRunDate;
        public Id memberId;
        public String memberName;
        public Boolean canEdit;
    }

    public class DueItem {
        public String kind;
        public Id id;
        public Id parentId;
        public String title;
        public String subtitle;
        public Decimal amount;
        public Date dueDate;
        public Integer daysLeft;
        public String status;
        public String icon;
        public String color;
        public String link;
    }

    public class Notification {
        public Id id;
        public String type;
        public String severity;
        public String title;
        public String message;
        public String link;
        public Boolean read;
        public Datetime createdAt;
    }

    public class NotificationFeed {
        public List<Notification> items = new List<Notification>();
        public Integer unread = 0;
    }

    public static Installment installment(EMI_Installment__c i) {
        Installment d = new Installment();
        d.id = i.Id;
        d.no = i.Installment_No__c == null ? null : i.Installment_No__c.intValue();
        d.dueDate = i.Due_Date__c;
        d.emi = i.EMI_Amount__c;
        d.principal = i.Principal_Part__c;
        d.interest = i.Interest_Part__c;
        d.closing = i.Closing_Balance__c;
        d.status = i.Status__c;
        d.paidOn = i.Paid_On__c;
        return d;
    }

    public static Integer daysUntil(Date d) {
        return d == null ? null : Date.today().daysBetween(d);
    }
}