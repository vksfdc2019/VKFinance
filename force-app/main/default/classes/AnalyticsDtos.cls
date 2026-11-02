/** Analytics: where each month's money went, the month's spending by day, and its top payees. */
public inherited sharing class AnalyticsDtos {
    public class Analytics {
        public String month;
        public Date periodStart;
        public Date periodEnd;
        public String currencyCode;
        public Id memberId;
        public List<FinanceDtos.MemberOption> members = new List<FinanceDtos.MemberOption>();
        /** Oldest first, ending with the selected month. */
        public List<MonthFlow> series = new List<MonthFlow>();
        public MonthFlow current;
        public List<DayAmount> days = new List<DayAmount>();
        public List<NamedAmount> payees = new List<NamedAmount>();
    }

    public class MonthFlow {
        public String month;
        public Date periodStart;
        public Date periodEnd;
        public Decimal income = 0;
        /** Everyday spending: expenses less refunds, without bills or loan interest. */
        public Decimal spending = 0;
        public Decimal bills = 0;
        /** Principal and interest. */
        public Decimal emis = 0;
        public Decimal saved = 0;
        public Decimal savingsRate;
    }

    public class DayAmount {
        public Date day;
        public Decimal amount = 0;
    }

    public class NamedAmount {
        public String name;
        public Decimal amount;
        public Integer count;
    }
}
