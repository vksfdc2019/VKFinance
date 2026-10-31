/**
 * One family's daily automation: refresh bills and EMI windows, close card cycles, post
 * recurring entries, auto-pay what is set to auto-pay, and send reminders. Every alert has a
 * dedupe key, so running twice in a day changes nothing.
 */
public without sharing class DuesProcessor {
    public class Summary {
        public Integer billsAutoPaid = 0;
        public Integer emisAutoPaid = 0;
        public Integer statements = 0;
        public Integer recurringPosted = 0;
        public Integer notifications = 0;
    }

    public static String money(Decimal amount) {
        return '₹' + (amount == null ? 0 : amount.setScale(0, RoundingMode.HALF_UP)).format();
    }

    /** "Car loan EMI", but not "Laptop EMI EMI". */
    public static String emiLabel(String loanName) {
        return loanName.endsWithIgnoreCase('EMI') ? loanName : loanName + ' EMI';
    }

    private static String dueText(Integer days) {
        return days == 0 ? 'today' : days == 1 ? 'tomorrow' : 'in ' + days + ' days';
    }

    /** Reminder buckets so each one fires once: 7, 3, 1 and 0 days before. */
    private static String bucket(Integer days) {
        return days <= 0 ? '0' : days <= 1 ? '1' : days <= 3 ? '3' : '7';
    }

    public static Summary run(Id familyId, Date today) {
        Summary s = new Summary();
        InsightService.ensurePreviousMonth(familyId, today);
        BillService.refresh(familyId, today);
        LoanService.refresh(familyId, today);
        s.statements = CardStatementService.generate(familyId, today);
        s.recurringPosted = RecurringService.runDue(familyId, today);
        UserContext admin = SystemContext.familyAdmin(familyId);
        Set<Id> admins = SystemContext.adminIds(familyId);
        bills(familyId, today, admin, admins, s);
        emis(familyId, today, admin, admins, s);
        cards(familyId, today, admins, s);
        if (admin != null) {
            budgets(familyId, today, admin, admins, s);
        }
        return s;
    }

    private static void bills(Id familyId, Date today, UserContext admin, Set<Id> admins, Summary s) {
        Date horizon = today.addDays(15);
        for (Bill_Instance__c i : [
            SELECT Id, Due_Date__c, Amount_Due__c, Amount_Paid__c, Status__c, Bill__r.Name, Bill__r.Auto_Pay__c, Bill__r.Pay_From_Account__c,
                Bill__r.Reminder_Days__c, Bill__r.Responsible_Member__c
            FROM Bill_Instance__c
            WHERE Family__c = :familyId AND Status__c IN :CommitmentSelector.OPEN_BILL AND Due_Date__c <= :horizon
            WITH SYSTEM_MODE
            ORDER BY Due_Date__c
            LIMIT 500
        ]) {
            Integer days = today.daysBetween(i.Due_Date__c);
            Set<Id> who = i.Bill__r.Responsible_Member__c == null ? admins : new Set<Id>{ i.Bill__r.Responsible_Member__c };
            Decimal left = LedgerUtil.zeroIfNull(i.Amount_Due__c) - LedgerUtil.zeroIfNull(i.Amount_Paid__c);
            if (i.Bill__r.Auto_Pay__c && days <= 0 && admin != null && LedgerUtil.zeroIfNull(i.Amount_Paid__c) == 0) {
                Savepoint sp = Database.setSavepoint();
                try {
                    BillService.payInstance(admin, i.Id, new Map<String, Object>{ 'auto' => true, 'date' => String.valueOf(today) });
                    s.billsAutoPaid++;
                    s.notifications += NotificationService.notify(familyId, who, new NotificationService.Message(
                        'BILL_AUTOPAID', 'success', i.Bill__r.Name + ' paid automatically', money(left) + ' was paid on its due date.', '/bills', 'BILLAUTO:' + i.Id
                    ));
                    continue;
                } catch (Exception e) {
                    Database.rollback(sp);
                    s.notifications += NotificationService.notify(familyId, admins, new NotificationService.Message(
                        'BILL_AUTOPAY_FAILED', 'critical', 'Auto-pay failed: ' + i.Bill__r.Name, String.valueOf(e.getMessage()).left(200), '/bills', 'BILLAUTOFAIL:' + i.Id
                    ));
                }
            }
            Integer remind = i.Bill__r.Reminder_Days__c == null ? 3 : i.Bill__r.Reminder_Days__c.intValue();
            if (days < 0) {
                Set<Id> everyone = new Set<Id>(admins);
                everyone.addAll(who);
                s.notifications += NotificationService.notify(familyId, everyone, new NotificationService.Message(
                    'BILL_OVERDUE', 'critical', i.Bill__r.Name + ' is overdue', money(left) + ' was due on ' + i.Due_Date__c.format() + '.', '/bills', 'BILLOD:' + i.Id
                ));
            } else if (days <= remind) {
                s.notifications += NotificationService.notify(familyId, who, new NotificationService.Message(
                    'BILL_DUE', 'warning', i.Bill__r.Name + ' is due ' + dueText(days), money(left) + ' due on ' + i.Due_Date__c.format() + '.', '/bills',
                    'BILLDUE:' + i.Id + ':' + bucket(days)
                ));
            }
        }
    }

    private static void emis(Id familyId, Date today, UserContext admin, Set<Id> admins, Summary s) {
        Date horizon = today.addDays(3);
        for (EMI_Installment__c i : [
            SELECT Id, Loan__c, Installment_No__c, Due_Date__c, EMI_Amount__c, Loan__r.Name, Loan__r.Auto_Debit__c, Loan__r.Debit_Account__c,
                Loan__r.Borrower_Member__c
            FROM EMI_Installment__c
            WHERE Family__c = :familyId AND Status__c IN :CommitmentSelector.OPEN_EMI AND Due_Date__c <= :horizon AND Loan__r.Status__c = 'Active'
            WITH SYSTEM_MODE
            ORDER BY Loan__c, Installment_No__c
            LIMIT 500
        ]) {
            Integer days = today.daysBetween(i.Due_Date__c);
            Set<Id> who = i.Loan__r.Borrower_Member__c == null ? admins : new Set<Id>{ i.Loan__r.Borrower_Member__c };
            if (i.Loan__r.Auto_Debit__c && days <= 0 && admin != null) {
                Savepoint sp = Database.setSavepoint();
                try {
                    LoanService.payEmi(admin, i.Loan__c, new Map<String, Object>{ 'auto' => true, 'date' => String.valueOf(today) });
                    s.emisAutoPaid++;
                    s.notifications += NotificationService.notify(familyId, who, new NotificationService.Message(
                        'EMI_AUTOPAID', 'success', emiLabel(i.Loan__r.Name) + ' debited', money(i.EMI_Amount__c) + ' for EMI ' + i.Installment_No__c.intValue() + '.', '/loans', 'EMIAUTO:' + i.Id
                    ));
                    continue;
                } catch (Exception e) {
                    Database.rollback(sp);
                }
            }
            Set<Id> recipients = new Set<Id>(who);
            if (days < 0) {
                recipients.addAll(admins);
            }
            s.notifications += NotificationService.notify(familyId, recipients, new NotificationService.Message(
                days < 0 ? 'EMI_OVERDUE' : 'EMI_DUE', days < 0 ? 'critical' : 'warning',
                emiLabel(i.Loan__r.Name) + (days < 0 ? ' is overdue' : ' due ' + dueText(days)),
                money(i.EMI_Amount__c) + ' · instalment ' + i.Installment_No__c.intValue() + ', due ' + i.Due_Date__c.format() + '.', '/loans',
                (days < 0 ? 'EMIOD:' : 'EMIDUE:' + bucket(days) + ':') + i.Id
            ));
        }
    }

    private static void cards(Id familyId, Date today, Set<Id> admins, Summary s) {
        Date since = today.addDays(-40);
        Map<Id, Card_Statement__c> latest = new Map<Id, Card_Statement__c>();
        for (Card_Statement__c st : [
            SELECT Id, Account__c, Account__r.Name, Account__r.Owner_Member__c, Cycle_Start__c, Cycle_End__c, Statement_Amount__c, Minimum_Due__c,
                Due_Date__c, Unique_Key__c
            FROM Card_Statement__c
            WHERE Family__c = :familyId AND Cycle_End__c >= :since
            WITH SYSTEM_MODE
            ORDER BY Cycle_End__c DESC
        ]) {
            if (!latest.containsKey(st.Account__c)) {
                latest.put(st.Account__c, st);
            }
        }
        for (Card_Statement__c st : latest.values()) {
            CommitmentDtos.Statement d = CardStatementService.toDtos(new List<Card_Statement__c>{ st }, st.Account__c)[0];
            if (d.status == 'Paid' || d.dueDate == null) {
                continue;
            }
            Integer days = today.daysBetween(d.dueDate);
            if (days > 5) {
                continue;
            }
            Set<Id> who = st.Account__r.Owner_Member__c == null ? admins : new Set<Id>{ st.Account__r.Owner_Member__c };
            Decimal left = d.amount - d.amountPaid;
            s.notifications += NotificationService.notify(familyId, who, new NotificationService.Message(
                days < 0 ? 'CARD_OVERDUE' : 'CARD_DUE', days < 0 ? 'critical' : 'warning',
                st.Account__r.Name + (days < 0 ? ' bill is overdue' : ' bill due ' + dueText(days)),
                money(left) + ' to pay (minimum ' + money(d.minimumDue) + ') by ' + d.dueDate.format() + '.', '/accounts',
                (days < 0 ? 'CARDOD:' : 'CARDDUE:' + (days <= 2 ? '2' : '5') + ':') + st.Id
            ));
        }
    }

    private static void budgets(Id familyId, Date today, UserContext admin, Set<Id> admins, Summary s) {
        Date start = today.toStartOfMonth();
        Budget__c budget = new BudgetSelector(admin).forMonth(start);
        if (budget == null || budget.Lines__r.isEmpty()) {
            return;
        }
        CategorySelector categories = new CategorySelector(admin);
        Map<Id, Decimal> spent = BudgetService.spentByTopCategory(admin, categories, start, LedgerUtil.monthEnd(start));
        Map<Id, Category__c> all = categories.byIdMap();
        for (Budget_Line__c line : budget.Lines__r) {
            Decimal planned = LedgerUtil.zeroIfNull(line.Planned__c);
            Decimal used = spent.containsKey(line.Category__c) ? spent.get(line.Category__c) : 0;
            if (planned <= 0 || used < planned * 0.8) {
                continue;
            }
            Boolean over = used >= planned;
            String name = all.containsKey(line.Category__c) ? all.get(line.Category__c).Name : 'A category';
            s.notifications += NotificationService.notify(familyId, admins, new NotificationService.Message(
                over ? 'BUDGET_100' : 'BUDGET_80', over ? 'critical' : 'warning',
                name + (over ? ' is over budget' : ' has used 80% of its budget'),
                money(used) + ' of ' + money(planned) + ' spent this month.', '/budgets',
                'BUDGET:' + budget.Id + ':' + line.Category__c + ':' + (over ? '100' : '80')
            ));
        }
    }
}