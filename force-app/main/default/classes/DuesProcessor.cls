/**
 * One family's daily automation: refresh bills and EMI windows, close card cycles, post
 * recurring entries, auto-pay what is set to auto-pay, and send reminders. Every alert has a
 * dedupe key, so running twice in a day changes nothing.
 *
 * Overdue reminders repeat every VKF_Owner_Alerts__c.Overdue_Repeat_Days__c days (default daily)
 * until paid, each replacing the previous one, and the admins get one daily dues summary.
 */
public without sharing class DuesProcessor {
  private static final Date EPOCH = Date.newInstance(2000, 1, 1);
  private static final Set<String> OVERDUE_TYPES = new Set<String>{
    'BILL_OVERDUE',
    'EMI_OVERDUE',
    'CARD_OVERDUE'
  };
  private static final String SUMMARY_TYPE = 'DUES_SUMMARY';
  private static final Integer SUMMARY_ITEMS = 3;

  public class Summary {
    public Integer billsAutoPaid = 0;
    public Integer emisAutoPaid = 0;
    public Integer statements = 0;
    public Integer recurringPosted = 0;
    public Integer notifications = 0;
    /** Item id -> current overdue key, for reminders re-posted this run; other copies get replaced. */
    public Map<String, String> repeated = new Map<String, String>();
  }

  public static String money(Decimal amount) {
    return '₹' +
      (amount == null ? 0 : amount.setScale(0, RoundingMode.HALF_UP)).format();
  }

  /** "Car loan EMI", but not "Laptop EMI EMI". */
  public static String emiLabel(String loanName) {
    return loanName.endsWithIgnoreCase('EMI') ? loanName : loanName + ' EMI';
  }

  private static String dueText(Integer days) {
    return days == 0
      ? 'today'
      : days == 1 ? 'tomorrow' : 'in ' + days + ' days';
  }

  /** Reminder buckets so each one fires once: 7, 3, 1 and 0 days before. */
  private static String bucket(Integer days) {
    return days <= 0 ? '0' : days <= 1 ? '1' : days <= 3 ? '3' : '7';
  }

  /**
   * Overdue dedupe key: the same within one repeat period, new in the next, so the reminder
   * comes back every N days until paid. With repeats off (0) it is the original once-only key.
   */
  @TestVisible
  private static String overdueKey(String prefix, Id itemId, Date today) {
    Integer every = OwnerAlertService.overdueRepeatDays();
    if (every <= 0) {
      return prefix + itemId;
    }
    return prefix + itemId + ':P' + (EPOCH.daysBetween(today) / every);
  }

  private static void notifyOverdue(
    Id familyId,
    Set<Id> recipients,
    NotificationService.Message m,
    Id itemId,
    Summary s
  ) {
    Integer created = NotificationService.notify(familyId, recipients, m);
    s.notifications += created;
    if (created > 0) {
      s.repeated.put(String.valueOf(itemId), m.dedupeKey);
    }
  }

  /**
   * For items re-posted this run, removes every other reminder copy (earlier periods, or the
   * old once-only key), so the bell keeps one current reminder per overdue item. Matching is by
   * key, not creation time, so the new copy is never caught.
   */
  private static void replaceOlderReminders(
    Id familyId,
    Map<String, String> repeated
  ) {
    if (repeated.isEmpty()) {
      return;
    }
    List<Notification__c> older = new List<Notification__c>();
    for (Notification__c n : [
      SELECT Id, Dedupe_Key__c
      FROM Notification__c
      WHERE
        Family__c = :familyId
        AND Type__c IN :OVERDUE_TYPES
        AND Dedupe_Key__c != NULL
      WITH SYSTEM_MODE
      LIMIT 2000
    ]) {
      // Key: <familyId>:<PREFIX>:<itemId>[:P<period>]:<recipient>
      List<String> parts = n.Dedupe_Key__c.split(':');
      if (
        parts.size() > 2 &&
        repeated.containsKey(parts[2]) &&
        !n.Dedupe_Key__c.contains(':' + repeated.get(parts[2]) + ':')
      ) {
        older.add(n);
      }
    }
    delete as system older;
  }

  /** One bell entry per day for the admins: how many dues are overdue or coming up. */
  private static void dailySummary(
    Id familyId,
    Date today,
    UserContext admin,
    Set<Id> admins,
    Summary s
  ) {
    if (
      admin == null ||
      admins.isEmpty() ||
      !OwnerAlertService.portalSummaryOn()
    ) {
      return;
    }
    Integer days = OwnerAlertService.dueWithinDays();
    Integer overdue = 0;
    Integer soon = 0;
    List<String> top = new List<String>();
    for (CommitmentDtos.DueItem d : DuesService.upcoming(admin, days)) {
      if (d.daysLeft == null || d.daysLeft > days) {
        continue;
      }
      if (d.daysLeft < 0) {
        overdue++;
      } else {
        soon++;
      }
      if (top.size() < SUMMARY_ITEMS) {
        top.add(
          d.title +
            ' ' +
            money(d.amount) +
            (d.daysLeft < 0 ? ' (overdue)' : ' (' + dueText(d.daysLeft) + ')')
        );
      }
    }
    if (overdue + soon > 0) {
      List<String> parts = new List<String>();
      if (overdue > 0) {
        parts.add(overdue + ' overdue');
      }
      if (soon > 0) {
        parts.add(
          soon + ' due in the next ' + days + (days == 1 ? ' day' : ' days')
        );
      }
      Integer more = overdue + soon - top.size();
      s.notifications += NotificationService.notify(
        familyId,
        admins,
        new NotificationService.Message(
          SUMMARY_TYPE,
          overdue > 0 ? 'critical' : 'warning',
          'Today: ' + String.join(parts, ', '),
          String.join(top, ' · ') +
          (more > 0 ? ' · and ' + more + ' more' : ''),
          '/bills',
          'DUESUM:' + String.valueOf(today)
        )
      );
    }
    // Every earlier summary is out of date; keep only today's (matched by key, not time).
    String todayKey = '%:DUESUM:' + String.valueOf(today) + ':%';
    delete as system [
      SELECT Id
      FROM Notification__c
      WHERE
        Family__c = :familyId
        AND Type__c = :SUMMARY_TYPE
        AND (NOT Dedupe_Key__c LIKE :todayKey)
      WITH SYSTEM_MODE
      LIMIT 500
    ];
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
    s.notifications += DepositService.notifyMaturities(familyId, today, admins);
    if (admin != null) {
      budgets(familyId, today, admin, admins, s);
    }
    replaceOlderReminders(familyId, s.repeated);
    dailySummary(familyId, today, admin, admins, s);
    return s;
  }

  private static void bills(
    Id familyId,
    Date today,
    UserContext admin,
    Set<Id> admins,
    Summary s
  ) {
    Date horizon = today.addDays(15);
    for (Bill_Instance__c i : [
      SELECT
        Id,
        Due_Date__c,
        Amount_Due__c,
        Amount_Paid__c,
        Status__c,
        Bill__r.Name,
        Bill__r.Auto_Pay__c,
        Bill__r.Pay_From_Account__c,
        Bill__r.Reminder_Days__c,
        Bill__r.Responsible_Member__c
      FROM Bill_Instance__c
      WHERE
        Family__c = :familyId
        AND Status__c IN :CommitmentSelector.OPEN_BILL
        AND Due_Date__c <= :horizon
      WITH SYSTEM_MODE
      ORDER BY Due_Date__c
      LIMIT 500
    ]) {
      Integer days = today.daysBetween(i.Due_Date__c);
      Set<Id> who = i.Bill__r.Responsible_Member__c == null
        ? admins
        : new Set<Id>{ i.Bill__r.Responsible_Member__c };
      Decimal left =
        LedgerUtil.zeroIfNull(i.Amount_Due__c) -
        LedgerUtil.zeroIfNull(i.Amount_Paid__c);
      if (
        i.Bill__r.Auto_Pay__c &&
        days <= 0 &&
        admin != null &&
        LedgerUtil.zeroIfNull(i.Amount_Paid__c) == 0
      ) {
        Savepoint sp = Database.setSavepoint();
        try {
          BillService.payInstance(
            admin,
            i.Id,
            new Map<String, Object>{
              'auto' => true,
              'date' => String.valueOf(today)
            }
          );
          s.billsAutoPaid++;
          s.notifications += NotificationService.notify(
            familyId,
            who,
            new NotificationService.Message(
              'BILL_AUTOPAID',
              'success',
              i.Bill__r.Name + ' paid automatically',
              money(left) + ' was paid on its due date.',
              '/bills',
              'BILLAUTO:' + i.Id
            )
          );
          continue;
        } catch (Exception e) {
          Database.rollback(sp);
          s.notifications += NotificationService.notify(
            familyId,
            admins,
            new NotificationService.Message(
              'BILL_AUTOPAY_FAILED',
              'critical',
              'Auto-pay failed: ' + i.Bill__r.Name,
              String.valueOf(e.getMessage()).left(200),
              '/bills',
              'BILLAUTOFAIL:' + i.Id
            )
          );
        }
      }
      Integer remind = i.Bill__r.Reminder_Days__c == null
        ? 3
        : i.Bill__r.Reminder_Days__c.intValue();
      if (days < 0) {
        Set<Id> everyone = new Set<Id>(admins);
        everyone.addAll(who);
        notifyOverdue(
          familyId,
          everyone,
          new NotificationService.Message(
            'BILL_OVERDUE',
            'critical',
            i.Bill__r.Name + ' is overdue',
            money(left) + ' was due on ' + i.Due_Date__c.format() + '.',
            '/bills',
            overdueKey('BILLOD:', i.Id, today)
          ),
          i.Id,
          s
        );
      } else if (days <= remind) {
        s.notifications += NotificationService.notify(
          familyId,
          who,
          new NotificationService.Message(
            'BILL_DUE',
            'warning',
            i.Bill__r.Name + ' is due ' + dueText(days),
            money(left) + ' due on ' + i.Due_Date__c.format() + '.',
            '/bills',
            'BILLDUE:' + i.Id + ':' + bucket(days)
          )
        );
      }
    }
  }

  private static void emis(
    Id familyId,
    Date today,
    UserContext admin,
    Set<Id> admins,
    Summary s
  ) {
    Date horizon = today.addDays(3);
    for (EMI_Installment__c i : [
      SELECT
        Id,
        Loan__c,
        Installment_No__c,
        Due_Date__c,
        EMI_Amount__c,
        Loan__r.Name,
        Loan__r.Auto_Debit__c,
        Loan__r.Debit_Account__c,
        Loan__r.Borrower_Member__c
      FROM EMI_Installment__c
      WHERE
        Family__c = :familyId
        AND Status__c IN :CommitmentSelector.OPEN_EMI
        AND Due_Date__c <= :horizon
        AND Loan__r.Status__c = 'Active'
      WITH SYSTEM_MODE
      ORDER BY Loan__c, Installment_No__c
      LIMIT 500
    ]) {
      Integer days = today.daysBetween(i.Due_Date__c);
      Set<Id> who = i.Loan__r.Borrower_Member__c == null
        ? admins
        : new Set<Id>{ i.Loan__r.Borrower_Member__c };
      if (i.Loan__r.Auto_Debit__c && days <= 0 && admin != null) {
        Savepoint sp = Database.setSavepoint();
        try {
          LoanService.payEmi(
            admin,
            i.Loan__c,
            new Map<String, Object>{
              'auto' => true,
              'date' => String.valueOf(today)
            }
          );
          s.emisAutoPaid++;
          s.notifications += NotificationService.notify(
            familyId,
            who,
            new NotificationService.Message(
              'EMI_AUTOPAID',
              'success',
              emiLabel(i.Loan__r.Name) + ' debited',
              money(i.EMI_Amount__c) +
                ' for EMI ' +
                i.Installment_No__c.intValue() +
                '.',
              '/loans',
              'EMIAUTO:' + i.Id
            )
          );
          continue;
        } catch (Exception e) {
          Database.rollback(sp);
        }
      }
      Set<Id> recipients = new Set<Id>(who);
      if (days < 0) {
        recipients.addAll(admins);
      }
      NotificationService.Message m = new NotificationService.Message(
        days < 0 ? 'EMI_OVERDUE' : 'EMI_DUE',
        days < 0 ? 'critical' : 'warning',
        emiLabel(i.Loan__r.Name) +
        (days < 0 ? ' is overdue' : ' due ' + dueText(days)),
        money(i.EMI_Amount__c) +
          ' · instalment ' +
          i.Installment_No__c.intValue() +
          ', due ' +
          i.Due_Date__c.format() +
          '.',
        '/loans',
        days < 0
          ? overdueKey('EMIOD:', i.Id, today)
          : 'EMIDUE:' + bucket(days) + ':' + i.Id
      );
      if (days < 0) {
        notifyOverdue(familyId, recipients, m, i.Id, s);
      } else {
        s.notifications += NotificationService.notify(familyId, recipients, m);
      }
    }
  }

  private static void cards(
    Id familyId,
    Date today,
    Set<Id> admins,
    Summary s
  ) {
    Date since = today.addDays(-40);
    Map<Id, Card_Statement__c> latest = new Map<Id, Card_Statement__c>();
    for (Card_Statement__c st : [
      SELECT
        Id,
        Account__c,
        Account__r.Name,
        Account__r.Owner_Member__c,
        Cycle_Start__c,
        Cycle_End__c,
        Statement_Amount__c,
        Minimum_Due__c,
        Due_Date__c,
        Unique_Key__c
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
      CommitmentDtos.Statement d = CardStatementService.toDtos(
        new List<Card_Statement__c>{ st },
        st.Account__c
      )[0];
      if (d.status == 'Paid' || d.dueDate == null) {
        continue;
      }
      Integer days = today.daysBetween(d.dueDate);
      if (days > 5) {
        continue;
      }
      Set<Id> who = st.Account__r.Owner_Member__c == null
        ? admins
        : new Set<Id>{ st.Account__r.Owner_Member__c };
      Decimal left = d.amount - d.amountPaid;
      NotificationService.Message m = new NotificationService.Message(
        days < 0 ? 'CARD_OVERDUE' : 'CARD_DUE',
        days < 0 ? 'critical' : 'warning',
        st.Account__r.Name +
        (days < 0 ? ' bill is overdue' : ' bill due ' + dueText(days)),
        money(left) +
          ' to pay (minimum ' +
          money(d.minimumDue) +
          ') by ' +
          d.dueDate.format() +
          '.',
        '/accounts',
        days < 0
          ? overdueKey('CARDOD:', st.Id, today)
          : 'CARDDUE:' + (days <= 2 ? '2' : '5') + ':' + st.Id
      );
      if (days < 0) {
        notifyOverdue(familyId, who, m, st.Id, s);
      } else {
        s.notifications += NotificationService.notify(familyId, who, m);
      }
    }
  }

  private static void budgets(
    Id familyId,
    Date today,
    UserContext admin,
    Set<Id> admins,
    Summary s
  ) {
    Date start = today.toStartOfMonth();
    Budget__c budget = new BudgetSelector(admin).forMonth(start);
    if (budget == null || budget.Lines__r.isEmpty()) {
      return;
    }
    CategorySelector categories = new CategorySelector(admin);
    Map<Id, Decimal> spent = BudgetService.spentByTopCategory(
      admin,
      categories,
      start,
      LedgerUtil.monthEnd(start)
    );
    Map<Id, Category__c> all = categories.byIdMap();
    for (Budget_Line__c line : budget.Lines__r) {
      Decimal planned = LedgerUtil.zeroIfNull(line.Planned__c);
      Decimal used = spent.containsKey(line.Category__c)
        ? spent.get(line.Category__c)
        : 0;
      if (planned <= 0 || used < planned * 0.8) {
        continue;
      }
      Boolean over = used >= planned;
      String name = all.containsKey(line.Category__c)
        ? all.get(line.Category__c).Name
        : 'A category';
      s.notifications += NotificationService.notify(
        familyId,
        admins,
        new NotificationService.Message(
          over ? 'BUDGET_100' : 'BUDGET_80',
          over ? 'critical' : 'warning',
          name + (over ? ' is over budget' : ' has used 80% of its budget'),
          money(used) + ' of ' + money(planned) + ' spent this month.',
          '/budgets',
          'BUDGET:' +
            budget.Id +
            ':' +
            line.Category__c +
            ':' +
            (over ? '100' : '80')
        )
      );
    }
  }
}
