/** JSON shapes returned by the ledger endpoints. Builders keep field mapping in one place. */
public inherited sharing class FinanceDtos {
    public class Account {
        public Id id;
        public String name;
        public String type;
        public String institution;
        public String last4;
        public Decimal openingBalance;
        public Date openingDate;
        public Decimal balance;
        public Boolean isLiability;
        public Decimal creditLimit;
        public Decimal independentCreditLimit;
        public Id creditLimitGroupId;
        public CreditLimitGroupService.GroupSummary sharedCredit;
        public Boolean sharedCreditRestricted = false;
        public Integer statementDay;
        public Integer paymentDueDays;
        public Decimal minDuePct;
        public Boolean isShared;
        public String status;
        public String color;
        public Id ownerId;
        public String ownerName;
        public Boolean canManage;
        public Boolean canUse;
        public CardCycle card;
    }

    public class CardCycle {
        public Date lastStatementDate;
        public Date nextStatementDate;
        public Date dueDate;
        public Decimal cycleSpend;
        public Decimal available;
        public Decimal utilisationPct;
        /** The bill: the statement for the last closed cycle, or null until the daily job writes it. */
        public CommitmentDtos.Statement statement;
        public CardBill bill;
    }

    public class CardBill {
        public Id billId;
        public Id instanceId;
        public Decimal amount;
        public Decimal amountPaid;
        public Date dueDate;
        public String status;
    }

    public class AccountRef {
        public Id id;
        public String name;
        public String type;
        public String ownerName;
        public Boolean isLiability;
        public String color;
    }

    public class Category {
        public Id id;
        public String name;
        public String kind;
        public Id parentId;
        public Boolean essential;
        public Boolean taxRelevant;
        public String icon;
        public String color;
        public Integer sortOrder;
        public Boolean active;
        public String systemKey;
    }

    public class Txn {
        public Id id;
        public String name;
        public String type;
        public String direction;
        public Decimal amount;
        public Date txnDate;
        public Id accountId;
        public String accountName;
        public String accountType;
        public Id categoryId;
        public String categoryName;
        public String parentCategoryName;
        public String icon;
        public String color;
        public Id memberId;
        public String memberName;
        public String payee;
        public String notes;
        public String paymentMode;
        public String referenceNo;
        public String status;
        public String transferGroupId;
        public String counterAccountName;
        public String source;
        public Boolean canEdit;
        public Boolean isPayment;
        public Datetime createdAt;
    }

    public class TxnPage {
        public List<Txn> items = new List<Txn>();
        public String nextCursor;
        public Totals totals;
    }

    public class Totals {
        public Decimal income = 0;
        public Decimal expenses = 0;
        public Decimal transfers = 0;
        public Integer count = 0;
    }

    public class Transfer {
        public String groupId;
        public Txn outLeg;
        public Txn inLeg;
    }

    public class BudgetView {
        public String month;
        public Boolean exists = false;
        public Boolean canEdit = false;
        public Decimal totalPlanned = 0;
        public Decimal totalSpent = 0;
        public Integer daysInMonth;
        public Integer daysElapsed;
        public List<BudgetLine> lines = new List<BudgetLine>();
        public List<BudgetLine> unbudgeted = new List<BudgetLine>();
    }

    public class BudgetLine {
        public Id categoryId;
        public String name;
        public String icon;
        public String color;
        public Boolean essential;
        public Decimal planned = 0;
        public Decimal spent = 0;
    }

    public class Dashboard {
        public String month;
        public String currencyCode;
        public Id memberId;
        public Boolean wholeFamily;
        public Kpis kpis = new Kpis();
        public NetWorth netWorth = new NetWorth();
        public List<CategorySpend> byCategory = new List<CategorySpend>();
        public List<MonthPoint> trend = new List<MonthPoint>();
        public BudgetSummary budget;
        public List<Account> accounts = new List<Account>();
        public List<Txn> recent = new List<Txn>();
        public List<MemberOption> members = new List<MemberOption>();
        public List<CommitmentDtos.DueItem> upcoming = new List<CommitmentDtos.DueItem>();
    }

    public class Kpis {
        public Decimal income = 0;
        public Decimal expenses = 0;
        public Decimal net = 0;
        public Decimal savingsRate;
        public Decimal prevIncome = 0;
        public Decimal prevExpenses = 0;
        public Decimal essential = 0;
        public Decimal discretionary = 0;
    }

    public class NetWorth {
        public Decimal assets = 0;
        public Decimal liabilities = 0;
        public Decimal net = 0;
    }

    public class CategorySpend {
        public Id categoryId;
        public String name;
        public String icon;
        public String color;
        public Decimal amount = 0;
    }

    public class MonthPoint {
        public String month;
        public Decimal income = 0;
        public Decimal expenses = 0;
    }

    public class BudgetSummary {
        public Decimal planned = 0;
        public Decimal spent = 0;
        public Integer overCount = 0;
    }

    public class MemberOption {
        public Id id;
        public String name;
    }

    public static String personName(String first, String last) {
        return String.join(new List<String>{ first == null ? '' : first, last == null ? '' : last }, ' ').trim();
    }

    public static Account account(Financial_Account__c a, LedgerScope scope) {
        Account d = new Account();
        d.id = a.Id;
        d.name = a.Name;
        d.type = a.Type__c;
        d.institution = a.Institution__c;
        d.last4 = a.Last4__c;
        d.openingBalance = a.Opening_Balance__c;
        d.openingDate = a.Opening_Date__c;
        d.balance = a.Current_Balance__c == null ? LedgerUtil.zeroIfNull(a.Opening_Balance__c) : a.Current_Balance__c;
        d.isLiability = LedgerUtil.isLiability(a.Type__c);
        d.creditLimit = a.Credit_Limit__c;
        d.independentCreditLimit = scope.canManageAccount(a) ? a.Credit_Limit__c : null;
        d.creditLimitGroupId = a.Credit_Limit_Group__c;
        d.statementDay = a.Statement_Day__c == null ? null : a.Statement_Day__c.intValue();
        d.paymentDueDays = a.Payment_Due_Days__c == null ? null : a.Payment_Due_Days__c.intValue();
        d.minDuePct = a.Min_Due_Pct__c;
        d.isShared = a.Is_Shared__c;
        d.status = a.Status__c;
        d.color = a.Color__c;
        d.ownerId = a.Owner_Member__c;
        d.ownerName = a.Owner_Member__c == null ? null : personName(a.Owner_Member__r?.First_Name__c, a.Owner_Member__r?.Last_Name__c);
        d.canManage = scope.canManageAccount(a);
        d.canUse = scope.canUseAccount(a);
        return d;
    }

    public static AccountRef accountRef(Financial_Account__c a) {
        AccountRef r = new AccountRef();
        r.id = a.Id;
        r.name = a.Name;
        r.type = a.Type__c;
        r.ownerName = a.Owner_Member__c == null ? null : personName(a.Owner_Member__r?.First_Name__c, a.Owner_Member__r?.Last_Name__c);
        r.isLiability = LedgerUtil.isLiability(a.Type__c);
        r.color = a.Color__c;
        return r;
    }

    /** Sub-categories inherit their parent's icon and colour unless they set their own. */
    public static Category category(Category__c c, Map<Id, Category__c> all) {
        Category__c parent = c.Parent_Category__c == null ? null : all.get(c.Parent_Category__c);
        Category d = new Category();
        d.id = c.Id;
        d.name = c.Name;
        d.kind = c.Kind__c;
        d.parentId = c.Parent_Category__c;
        d.essential = c.Is_Essential__c;
        d.taxRelevant = c.Tax_Relevant__c;
        d.icon = String.isNotBlank(c.Icon__c) ? c.Icon__c : parent?.Icon__c;
        d.color = String.isNotBlank(c.Color__c) ? c.Color__c : parent?.Color__c;
        d.sortOrder = c.Sort_Order__c == null ? null : c.Sort_Order__c.intValue();
        d.active = c.Active__c;
        d.systemKey = c.System_Key__c;
        return d;
    }

    public static Txn txn(Transaction__c t, Map<Id, Category__c> categories, LedgerScope scope) {
        Txn d = new Txn();
        d.id = t.Id;
        d.name = t.Name;
        d.type = t.Type__c;
        d.direction = t.Direction__c;
        d.amount = t.Amount__c;
        d.txnDate = t.Txn_Date__c;
        d.accountId = t.Account__c;
        d.accountName = t.Account__r?.Name;
        d.accountType = t.Account__r?.Type__c;
        d.categoryId = t.Category__c;
        Category__c c = t.Category__c == null ? null : categories.get(t.Category__c);
        if (c != null) {
            Category view = category(c, categories);
            d.categoryName = c.Name;
            d.parentCategoryName = c.Parent_Category__c == null ? null : categories.get(c.Parent_Category__c)?.Name;
            d.icon = view.icon;
            d.color = view.color;
        }
        d.memberId = t.Member__c;
        d.memberName = t.Member__c == null ? null : personName(t.Member__r?.First_Name__c, t.Member__r?.Last_Name__c);
        d.payee = t.Payee__c;
        d.notes = t.Notes__c;
        d.paymentMode = t.Payment_Mode__c;
        d.referenceNo = t.Reference_No__c;
        d.status = t.Status__c;
        d.transferGroupId = t.Transfer_Group_Id__c;
        d.counterAccountName = t.Counter_Transaction__r?.Account__r?.Name;
        d.source = t.Source__c;
        d.canEdit = scope.canEditTransaction(t);
        d.isPayment = TransactionService.isPayment(t);
        d.createdAt = t.CreatedDate;
        return d;
    }
}