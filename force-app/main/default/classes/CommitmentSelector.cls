/** Family-scoped queries for bills, loans, card statements, recurring rules and notifications. */
public without sharing class CommitmentSelector extends FamilyScopedSelector {
    public static final Set<String> OPEN_BILL = new Set<String>{ 'Upcoming', 'Due', 'Overdue', 'Partially Paid' };
    public static final Set<String> OPEN_EMI = new Set<String>{ 'Upcoming', 'Due', 'Overdue' };

    public CommitmentSelector(UserContext ctx) {
        super(ctx);
    }

    // ------------------------------------------------------------------ bills
    public List<Bill__c> bills(Id responsibleId) {
        Id fid = familyId;
        List<Bill__c> rows = [
            SELECT
                Id, Name, Family__c, Category__c, Consumer_No__c, Frequency__c, Next_Due_Date__c, Expected_Amount__c, Pay_From_Account__c,
                Pay_From_Account__r.Name, Credit_Card_Account__c, Credit_Card_Account__r.Name, Auto_Pay__c, Reminder_Days__c, Responsible_Member__c, Responsible_Member__r.First_Name__c,
                Responsible_Member__r.Last_Name__c, Active__c
            FROM Bill__c
            WHERE Family__c = :fid
            WITH SYSTEM_MODE
            ORDER BY Active__c DESC, Next_Due_Date__c NULLS LAST, Name
            LIMIT 500
        ];
        if (responsibleId == null) {
            return rows;
        }
        List<Bill__c> mine = new List<Bill__c>();
        for (Bill__c b : rows) {
            if (b.Responsible_Member__c == responsibleId) {
                mine.add(b);
            }
        }
        return mine;
    }

    public Bill__c billById(Id billId) {
        for (Bill__c b : bills(null)) {
            if (b.Id == billId) {
                return b;
            }
        }
        throw notFound('Bill__c', billId, elsewhere('Bill__c', billId));
    }

    public List<Bill_Instance__c> instances(Set<Id> billIds, Set<String> statuses, Date until) {
        Id fid = familyId;
        Date limitDate = until == null ? Date.today().addYears(5) : until;
        return [
            SELECT Id, Bill__c, Due_Date__c, Amount_Due__c, Amount_Paid__c, Status__c, Paid_On__c, Unique_Key__c
            FROM Bill_Instance__c
            WHERE Family__c = :fid AND Bill__c IN :billIds AND Status__c IN :statuses AND Due_Date__c <= :limitDate
            WITH SYSTEM_MODE
            ORDER BY Due_Date__c
            LIMIT 2000
        ];
    }

    public Bill_Instance__c instanceById(Id instanceId) {
        Id fid = familyId;
        for (Bill_Instance__c i : [
            SELECT Id, Bill__c, Due_Date__c, Amount_Due__c, Amount_Paid__c, Status__c, Paid_On__c, Unique_Key__c
            FROM Bill_Instance__c
            WHERE Id = :instanceId AND Family__c = :fid
            WITH SYSTEM_MODE
        ]) {
            return i;
        }
        throw notFound('Bill_Instance__c', instanceId, elsewhere('Bill_Instance__c', instanceId));
    }

    // ------------------------------------------------------------------ loans
    public List<Loan__c> loans(Id borrowerId) {
        Id fid = familyId;
        List<Loan__c> rows = [
            SELECT
                Id, Name, Borrower_Member__c, Borrower_Member__r.First_Name__c, Borrower_Member__r.Last_Name__c, Lender__c, Loan_Type__c,
                Principal__c, Annual_Rate__c, Rate_Type__c, Tenure_Months__c, Start_Date__c, EMI_Amount__c, Outstanding_Principal__c, Installments_Paid__c,
                Debit_Account__c, Debit_Account__r.Name, Loan_Account__c, Loan_Account__r.Current_Balance__c, Auto_Debit__c, Status__c, Loan_Account_No__c
            FROM Loan__c
            WHERE Family__c = :fid
            WITH SYSTEM_MODE
            ORDER BY Status__c, Name
            LIMIT 200
        ];
        if (borrowerId == null) {
            return rows;
        }
        List<Loan__c> mine = new List<Loan__c>();
        for (Loan__c l : rows) {
            if (l.Borrower_Member__c == borrowerId) {
                mine.add(l);
            }
        }
        return mine;
    }

    public Loan__c loanById(Id loanId) {
        for (Loan__c l : loans(null)) {
            if (l.Id == loanId) {
                return l;
            }
        }
        throw notFound('Loan__c', loanId, elsewhere('Loan__c', loanId));
    }

    public List<EMI_Installment__c> installments(Set<Id> loanIds, Set<String> statuses) {
        Id fid = familyId;
        return [
            SELECT
                Id, Loan__c, Installment_No__c, Due_Date__c, EMI_Amount__c, Principal_Part__c, Interest_Part__c, Opening_Balance__c,
                Closing_Balance__c, Status__c, Paid_On__c
            FROM EMI_Installment__c
            WHERE Family__c = :fid AND Loan__c IN :loanIds AND Status__c IN :statuses
            WITH SYSTEM_MODE
            ORDER BY Loan__c, Installment_No__c
            LIMIT 5000
        ];
    }

    /** Newest first. */
    public List<Loan_Rate_Change__c> rateChanges(Id loanId) {
        Id fid = familyId;
        return [
            SELECT
                Id, Loan__c, Effective_Date__c, Old_Rate__c, New_Rate__c, Old_EMI__c, New_EMI__c, Old_EMIs_Left__c, New_EMIs_Left__c,
                Outstanding__c, Adjusted__c, Note__c, CreatedDate
            FROM Loan_Rate_Change__c
            WHERE Family__c = :fid AND Loan__c = :loanId
            WITH SYSTEM_MODE
            ORDER BY Effective_Date__c DESC, CreatedDate DESC
            LIMIT 200
        ];
    }

    // ------------------------------------------------------------------ card statements
    public List<Card_Statement__c> statements(Set<Id> accountIds, Integer max) {
        Id fid = familyId;
        return [
            SELECT Id, Account__c, Cycle_Start__c, Cycle_End__c, Statement_Amount__c, Minimum_Due__c, Due_Date__c, Unique_Key__c
            FROM Card_Statement__c
            WHERE Family__c = :fid AND Account__c IN :accountIds
            WITH SYSTEM_MODE
            ORDER BY Cycle_End__c DESC
            LIMIT :max
        ];
    }

    // ------------------------------------------------------------------ recurring rules
    public List<Recurring_Rule__c> rules(Id memberId) {
        Id fid = familyId;
        List<Recurring_Rule__c> rows = [
            SELECT
                Id, Name, Member__c, Member__r.First_Name__c, Member__r.Last_Name__c, Type__c, Amount__c, Account__c, Account__r.Name,
                To_Account__c, To_Account__r.Name, Category__c, Payee__c, Payment_Mode__c, Frequency__c, Next_Run_Date__c, End_Date__c,
                Mode__c, Active__c, Last_Run_Date__c
            FROM Recurring_Rule__c
            WHERE Family__c = :fid
            WITH SYSTEM_MODE
            ORDER BY Active__c DESC, Next_Run_Date__c NULLS LAST, Name
            LIMIT 500
        ];
        if (memberId == null) {
            return rows;
        }
        List<Recurring_Rule__c> mine = new List<Recurring_Rule__c>();
        for (Recurring_Rule__c r : rows) {
            if (r.Member__c == memberId) {
                mine.add(r);
            }
        }
        return mine;
    }

    public Recurring_Rule__c ruleById(Id ruleId) {
        for (Recurring_Rule__c r : rules(null)) {
            if (r.Id == ruleId) {
                return r;
            }
        }
        throw notFound('Recurring_Rule__c', ruleId, elsewhere('Recurring_Rule__c', ruleId));
    }

    // ------------------------------------------------------------------ notifications
    public List<Notification__c> notifications(Id recipientId, Integer max) {
        Id fid = familyId;
        return [
            SELECT Id, Type__c, Severity__c, Title__c, Message__c, Link__c, Is_Read__c, CreatedDate
            FROM Notification__c
            WHERE Family__c = :fid AND Recipient__c = :recipientId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT :max
        ];
    }

    public Integer unreadCount(Id recipientId) {
        Id fid = familyId;
        return [SELECT COUNT() FROM Notification__c WHERE Family__c = :fid AND Recipient__c = :recipientId AND Is_Read__c = FALSE WITH SYSTEM_MODE];
    }

    private Boolean elsewhere(String objectName, Id recordId) {
        if (recordId == null || recordId.getSobjectType().getDescribe().getName() != objectName) {
            return false;
        }
        return Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' + objectName + ' WHERE Id = :rid AND Family__c != :fid',
                new Map<String, Object>{ 'rid' => recordId, 'fid' => familyId },
                AccessLevel.SYSTEM_MODE
            ) > 0;
    }
}