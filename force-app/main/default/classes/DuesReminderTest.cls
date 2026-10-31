/** Portal bell: repeating overdue reminders and the admins' daily dues summary (DuesProcessor). */
@IsTest
private class DuesReminderTest {
  @TestSetup
  static void setup() {
    VkfTestData.twoFamilies();
  }

  private static void settings(Integer repeatDays, Boolean summaryOff) {
    insert as system new VKF_Owner_Alerts__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Enabled__c = true,
      Due_Within_Days__c = 3,
      Overdue_Repeat_Days__c = repeatDays,
      Portal_Summary_Off__c = summaryOff
    );
  }

  /** A Family A bill due tomorrow; returns the family id. */
  private static Id billDueTomorrow() {
    UserContext admin = VkfTestData.ctx('admina');
    Id savings = LedgerTestData.account(admin, 'Savings', 'Savings', 10000).id;
    BillService.createBill(
      admin,
      new Map<String, Object>{
        'name' => 'BESCOM',
        'categoryId' => LedgerTestData.categoryId(admin, 'Electricity'),
        'frequency' => 'Monthly',
        'nextDueDate' => String.valueOf(Date.today().addDays(1)),
        'expectedAmount' => 1500,
        'payFromAccountId' => savings,
        'reminderDays' => 3
      }
    );
    return admin.familyId;
  }

  private static List<Notification__c> notes(String type) {
    return [
      SELECT Dedupe_Key__c, Title__c, Recipient__c
      FROM Notification__c
      WHERE Type__c = :type
      WITH SYSTEM_MODE
    ];
  }

  @IsTest
  static void shouldRepeatAndReplaceOverdueReminder_WhenNextDayStillUnpaid() {
    VkfTestData.fastPolicy();
    settings(1, true);
    Id familyId = billDueTomorrow();
    Date dayOne = Date.today().addDays(3);

    Test.startTest();
    DuesProcessor.run(familyId, dayOne);
    List<Notification__c> first = notes('BILL_OVERDUE');
    DuesProcessor.run(familyId, dayOne.addDays(1));
    List<Notification__c> second = notes('BILL_OVERDUE');
    DuesProcessor.Summary again = DuesProcessor.run(
      familyId,
      dayOne.addDays(1)
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      first.size(),
      'Both admins are told on the first overdue day'
    );
    Assert.areEqual(2, second.size(), 'The next day replaces, not piles up');
    Assert.areNotEqual(
      first[0].Dedupe_Key__c.substringBeforeLast(':'),
      second[0].Dedupe_Key__c.substringBeforeLast(':'),
      'A fresh reminder for the new day'
    );
    Assert.areEqual(
      0,
      again.notifications,
      'Running twice in a day still changes nothing'
    );
  }

  @IsTest
  static void shouldRemindOnce_WhenRepeatsAreOff() {
    VkfTestData.fastPolicy();
    settings(0, true);
    Id familyId = billDueTomorrow();
    Date dayOne = Date.today().addDays(3);

    Test.startTest();
    DuesProcessor.run(familyId, dayOne);
    DuesProcessor.run(familyId, dayOne.addDays(1));
    Test.stopTest();

    List<Notification__c> overdue = notes('BILL_OVERDUE');
    Assert.areEqual(
      2,
      overdue.size(),
      'One reminder per admin, never repeated'
    );
    Assert.isFalse(
      overdue[0].Dedupe_Key__c.contains(':P'),
      'Original once-only key'
    );
  }

  @IsTest
  static void shouldPostOneDailySummaryPerAdmin_WhenDuesAreComingUp() {
    VkfTestData.fastPolicy();
    settings(1, false);
    Id familyId = billDueTomorrow();

    Test.startTest();
    DuesProcessor.run(familyId, Date.today());
    List<Notification__c> today = notes('DUES_SUMMARY');
    DuesProcessor.run(familyId, Date.today().addDays(1));
    List<Notification__c> tomorrow = notes('DUES_SUMMARY');
    Test.stopTest();

    Assert.areEqual(2, today.size(), 'Admin and co-admin each get one');
    Assert.areEqual(
      'Today: 1 due in the next 3 days',
      today[0].Title__c,
      'Counts in the title'
    );
    Assert.areEqual(2, tomorrow.size(), 'Yesterday\'s summary is replaced');
    Assert.isTrue(
      tomorrow[0]
        .Dedupe_Key__c.contains(String.valueOf(Date.today().addDays(1))),
      'Dated for the new day'
    );
  }

  @IsTest
  static void shouldSkipSummary_WhenSwitchedOff() {
    VkfTestData.fastPolicy();
    settings(1, true);
    Id familyId = billDueTomorrow();

    Test.startTest();
    DuesProcessor.run(familyId, Date.today());
    Test.stopTest();

    Assert.areEqual(
      0,
      notes('DUES_SUMMARY').size(),
      'Portal Daily Summary Off stops it'
    );
  }

  private static CommitmentDtos.Statement statement(
    Decimal amount,
    Decimal paid
  ) {
    CommitmentDtos.Statement s = new CommitmentDtos.Statement();
    s.amount = amount;
    s.amountPaid = paid;
    s.dueDate = Date.today().addDays(-5);
    return s;
  }

  @IsTest
  static void shouldTreatPaiseAsSettled_WhenCardBillIsUnderOneRupee() {
    Test.startTest();
    String paise = CardStatementService.statusFor(
      statement(0.18, 0),
      Date.today()
    );
    String leftover = CardStatementService.statusFor(
      statement(25712.16, 25711.50),
      Date.today()
    );
    String real = CardStatementService.statusFor(
      statement(100.10, 0),
      Date.today()
    );
    String empty = CardStatementService.statusFor(
      statement(null, null),
      Date.today()
    );
    Test.stopTest();

    Assert.areEqual('Paid', paise, 'A ₹0.18 statement is not a bill to chase');
    Assert.areEqual('Paid', leftover, 'Paise left after paying is settled');
    Assert.areEqual(
      'Overdue',
      real,
      'A real amount past its due date stays overdue'
    );
    Assert.areEqual('Paid', empty, 'No statement amount means nothing to pay');
  }

  @IsTest
  static void shouldKeyByPeriod_WhenRepeatingEveryFewDays() {
    settings(3, true);
    Id itemId = VkfTestData.userId('admina');
    Date d = Date.newInstance(2026, 1, 1);

    Test.startTest();
    String a = DuesProcessor.overdueKey('BILLOD:', itemId, d);
    String b = DuesProcessor.overdueKey('BILLOD:', itemId, d.addDays(1));
    String c = DuesProcessor.overdueKey('BILLOD:', itemId, d.addDays(3));
    Test.stopTest();

    Assert.isTrue(a.startsWith('BILLOD:' + itemId + ':P'), a);
    Assert.isTrue(
      a == b || b == c,
      'Days in the same 3-day period share a key'
    );
    Assert.areNotEqual(a, c, 'A new period gets a new key');
  }
}
