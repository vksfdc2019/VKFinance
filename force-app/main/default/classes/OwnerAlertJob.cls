/**
 * 07:30 daily ("VKF Owner Alerts"): one digest to the platform owner across every active
 * family, sent by OwnerAlertService on the channels set in VKF_Owner_Alerts__c:
 *  - bills, EMIs and card bills overdue or due within N days (DuesService, the family's admin view)
 *  - transactions at or above the family's Large Transaction Threshold in the last 24 hours
 *  - balance fixes and failed nightly runs from the audit trail, plus failed Apex jobs
 * One family per batch execution (own limits; one family's error can't hide the others).
 * A quiet day sends nothing.
 */
public without sharing class OwnerAlertJob implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts, Schedulable {
  private static final Integer MAX_ITEMS = 8;
  private static final Set<String> CHECK_EVENTS = new Set<String>{
    'BALANCE_DRIFT_FIXED',
    'BALANCE_RECONCILE_FAILED',
    'DAILY_DUES_FAILED',
    'OWNER_ALERT_FAILED'
  };
  private static final Set<String> SKIPPED_TYPES = new Set<String>{
    'Transfer In'
  };

  @TestVisible
  private static OwnerAlertService.Alert lastAlert;

  /** What one family contributes to the digest. */
  public class FamilyBlock {
    public String name;
    public String code;
    public Integer overdue = 0;
    public Integer dueSoon = 0;
    public List<String> dues = new List<String>();
    public List<String> large = new List<String>();
    public List<String> checks = new List<String>();

    public Boolean isEmpty() {
      return dues.isEmpty() && large.isEmpty() && checks.isEmpty();
    }
  }

  private List<FamilyBlock> blocks = new List<FamilyBlock>();
  private Integer familyErrors = 0;
  private Datetime since = Datetime.now().addHours(-24);

  public void execute(SchedulableContext sc) {
    // One family per execution in production; tests may run only one execution in total.
    Database.executeBatch(new OwnerAlertJob(), Test.isRunningTest() ? 200 : 1);
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT Id, Name, Family_Code__c, Large_Txn_Threshold__c
        FROM Family__c
        WHERE Status__c = 'Active'
        WITH SYSTEM_MODE
        ORDER BY Name
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<Family__c> scope) {
    Integer days = OwnerAlertService.dueWithinDays();
    for (Family__c f : scope) {
      try {
        FamilyBlock b = buildBlock(f, days, since);
        if (!b.isEmpty()) {
          blocks.add(b);
        }
      } catch (Exception e) {
        familyErrors++;
        System.debug(
          LoggingLevel.ERROR,
          'Owner alerts failed for ' + f.Id + ': ' + e.getMessage()
        );
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    Integer failedJobs = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE
        CreatedDate >= :since
        AND JobType IN ('BatchApex', 'ScheduledApex', 'Queueable', 'Future')
        AND (Status = 'Failed'
        OR NumberOfErrors > 0)
      WITH SYSTEM_MODE
    ];
    OwnerAlertService.Alert alert = compose(
      blocks,
      failedJobs,
      familyErrors,
      Date.today()
    );
    if (alert != null) {
      lastAlert = alert;
      OwnerAlertService.deliver(alert);
    }
  }

  /**
   * Reads the audit trail first: big-object reads fail after DML in the same transaction,
   * and DuesService may write card statements.
   */
  @TestVisible
  private static FamilyBlock buildBlock(
    Family__c f,
    Integer days,
    Datetime since
  ) {
    FamilyBlock b = new FamilyBlock();
    b.name = f.Name;
    b.code = f.Family_Code__c;
    addChecks(b, f.Id, since);
    addLarge(b, f, since);
    addDues(b, f.Id, days);
    return b;
  }

  private static void addChecks(FamilyBlock b, Id familyId, Datetime since) {
    Map<String, Integer> counts = new Map<String, Integer>();
    try {
      for (
        SObject row : Database.queryWithBinds(
          'SELECT Event_Type__c FROM Audit_Log__b WHERE Family_Id__c = :fid AND Event_Time__c >= :since LIMIT 2000',
          new Map<String, Object>{
            'fid' => String.valueOf(familyId),
            'since' => since
          },
          AccessLevel.SYSTEM_MODE
        )
      ) {
        String type = (String) row.get('Event_Type__c');
        if (CHECK_EVENTS.contains(type)) {
          counts.put(
            type,
            (counts.containsKey(type) ? counts.get(type) : 0) + 1
          );
        }
      }
    } catch (Exception e) {
      // The audit store can be unavailable (e.g. in tests); dues and large entries still go out.
      return;
    }
    if (counts.containsKey('BALANCE_DRIFT_FIXED')) {
      b.checks.add(
        counts.get('BALANCE_DRIFT_FIXED') +
        ' account balance(s) were corrected overnight'
      );
    }
    if (
      counts.containsKey('BALANCE_RECONCILE_FAILED') ||
      counts.containsKey('DAILY_DUES_FAILED')
    ) {
      b.checks.add(
        'A nightly job failed for this family - check the audit trail'
      );
    }
  }

  private static void addLarge(FamilyBlock b, Family__c f, Datetime since) {
    if (f.Large_Txn_Threshold__c == null || f.Large_Txn_Threshold__c <= 0) {
      return;
    }
    Decimal threshold = f.Large_Txn_Threshold__c;
    for (Transaction__c t : [
      SELECT
        Type__c,
        Amount__c,
        Payee__c,
        Txn_Date__c,
        Account__r.Name,
        Category__r.Name
      FROM Transaction__c
      WHERE
        Family__c = :f.Id
        AND CreatedDate >= :since
        AND Amount__c >= :threshold
        AND Status__c != 'Void'
        AND Type__c NOT IN :SKIPPED_TYPES
      WITH SYSTEM_MODE
      ORDER BY Amount__c DESC
      LIMIT :MAX_ITEMS
    ]) {
      String what = String.isNotBlank(t.Payee__c)
        ? t.Payee__c
        : t.Category__r?.Name;
      b.large.add(
        DuesProcessor.money(t.Amount__c) +
          ' ' +
          t.Type__c +
          (String.isBlank(what) ? '' : ' · ' + what) +
          ' · ' +
          t.Account__r?.Name
      );
    }
  }

  private static void addDues(FamilyBlock b, Id familyId, Integer days) {
    UserContext ctx;
    try {
      ctx = OwnerContext.forAlerts(familyId);
    } catch (PortalException e) {
      b.checks.add('No active Family Admin, so dues could not be checked');
      return;
    }
    for (CommitmentDtos.DueItem d : DuesService.upcoming(ctx, days)) {
      if (d.daysLeft == null || d.daysLeft > days) {
        continue;
      }
      if (d.daysLeft < 0) {
        b.overdue++;
      } else {
        b.dueSoon++;
      }
      if (b.dues.size() < MAX_ITEMS) {
        b.dues.add(
          whenText(d.daysLeft) +
            ' - ' +
            d.title +
            ' ' +
            DuesProcessor.money(d.amount) +
            ' (' +
            d.dueDate.format() +
            ')'
        );
      }
    }
  }

  private static String whenText(Integer daysLeft) {
    if (daysLeft < 0) {
      return 'OVERDUE ' + Math.abs(daysLeft) + 'd';
    }
    return daysLeft == 0
      ? 'Due TODAY'
      : daysLeft == 1 ? 'Due tomorrow' : 'Due in ' + daysLeft + 'd';
  }

  /** @return the digest, or null on a quiet day */
  @TestVisible
  private static OwnerAlertService.Alert compose(
    List<FamilyBlock> blocks,
    Integer failedJobs,
    Integer familyErrors,
    Date today
  ) {
    Integer overdue = 0;
    Integer dueSoon = 0;
    Integer large = 0;
    for (FamilyBlock b : blocks) {
      overdue += b.overdue;
      dueSoon += b.dueSoon;
      large += b.large.size();
    }
    Integer systemIssues =
      (failedJobs == null ? 0 : failedJobs) +
      (familyErrors == null ? 0 : familyErrors);
    if (blocks.isEmpty() && systemIssues == 0) {
      return null;
    }

    List<String> headline = new List<String>();
    if (overdue > 0) {
      headline.add(overdue + ' overdue');
    }
    if (dueSoon > 0) {
      headline.add(dueSoon + ' due soon');
    }
    if (large > 0) {
      headline.add(large + ' large ' + (large == 1 ? 'entry' : 'entries'));
    }
    if (systemIssues > 0) {
      headline.add(
        systemIssues + ' job issue' + (systemIssues == 1 ? '' : 's')
      );
    }
    String title =
      'VK Finance: ' +
      (headline.isEmpty() ? 'daily check' : String.join(headline, ', '));

    List<String> lines = new List<String>{
      'VK Finance - daily owner alerts - ' + today.format(),
      ''
    };
    List<String> pushParts = new List<String>();
    for (FamilyBlock b : blocks) {
      lines.add(b.name + (String.isBlank(b.code) ? '' : ' (' + b.code + ')'));
      appendSection(lines, 'Bills and EMIs', b.dues);
      appendSection(lines, 'Large transactions (last 24h)', b.large);
      appendSection(lines, 'Checks', b.checks);
      lines.add('');
      if (b.overdue + b.dueSoon > 0) {
        pushParts.add(
          b.name +
            ': ' +
            (b.overdue > 0 ? b.overdue + ' overdue' : '') +
            (b.overdue > 0 && b.dueSoon > 0 ? ', ' : '') +
            (b.dueSoon > 0 ? b.dueSoon + ' due soon' : '')
        );
      }
    }
    if (systemIssues > 0) {
      lines.add(
        'System: ' +
          systemIssues +
          ' background job issue(s) in the last 24 hours - check Setup > Apex Jobs.'
      );
      lines.add('');
    }
    lines.add(
      'Open the Owner Workspace in the Salesforce app to pay or review.'
    );

    String pushBody = pushParts.isEmpty()
      ? String.join(headline, ', ')
      : String.join(pushParts, ' · ');
    return new OwnerAlertService.Alert(
      title,
      pushBody + '. Tap to open the Owner Workspace.',
      String.join(lines, '\n')
    );
  }

  private static void appendSection(
    List<String> lines,
    String heading,
    List<String> items
  ) {
    if (items.isEmpty()) {
      return;
    }
    lines.add('  ' + heading + ':');
    for (String item : items) {
      lines.add('   • ' + item);
    }
  }
}
