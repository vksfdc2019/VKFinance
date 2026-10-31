@IsTest
private class OwnerAlertTest {
  private static final Decimal OPENING = 50000;

  @TestSetup
  static void setup() {
    VkfTestData.twoFamilies();
  }

  /** Telegram stub: records the request and answers with the given status. */
  private class TelegramMock implements HttpCalloutMock {
    public Integer status;
    public String body;
    public HttpRequest seen;

    TelegramMock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest req) {
      seen = req;
      HttpResponse res = new HttpResponse();
      res.setStatusCode(status);
      res.setBody(body);
      return res;
    }
  }

  private static User owner(Boolean platformAdmin) {
    String profileName = platformAdmin
      ? 'System Administrator'
      : 'Standard User';
    User u = new User(
      Alias = 'vkfalrt',
      Email = 'vkf.alerts@example.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Alerts',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_IN',
      ProfileId = [
        SELECT Id
        FROM Profile
        WHERE Name = :profileName
        WITH SYSTEM_MODE
      ]
      .Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = 'vkf.alerts.' + Datetime.now().getTime() + '@example.test'
    );
    insert as system u;
    if (platformAdmin) {
      insert as system new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'VKF_Platform_Admin'
          WITH SYSTEM_MODE
        ]
        .Id
      );
    }
    return u;
  }

  private static void configure(
    Boolean enabled,
    Boolean telegram,
    String chatId
  ) {
    insert as system new VKF_Owner_Alerts__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Enabled__c = enabled,
      Push__c = true,
      Email__c = true,
      Telegram__c = telegram,
      Telegram_Chat_Id__c = chatId,
      Due_Within_Days__c = 3
    );
  }

  private static OwnerAlertService.ChannelResult resultFor(
    List<OwnerAlertService.ChannelResult> results,
    String channel
  ) {
    for (OwnerAlertService.ChannelResult r : results) {
      if (r.channel == channel) {
        return r;
      }
    }
    return null;
  }

  private static OwnerAlertService.Alert sample() {
    return new OwnerAlertService.Alert(
      'VK Finance: test',
      'Short body',
      'Full body'
    );
  }

  private static Family__c familyA() {
    return [
      SELECT Id, Name, Family_Code__c, Large_Txn_Threshold__c
      FROM Family__c
      WHERE Name = 'Family A'
      WITH SYSTEM_MODE
    ];
  }

  @IsTest
  static void shouldSendNothing_WhenTheDayIsQuiet() {
    Test.startTest();
    OwnerAlertService.Alert alert = OwnerAlertJob.compose(
      new List<OwnerAlertJob.FamilyBlock>(),
      0,
      0,
      Date.today()
    );
    Test.stopTest();
    Assert.isNull(
      alert,
      'No dues, large entries or job issues means no message'
    );
  }

  @IsTest
  static void shouldSummariseEveryFamily_WhenComposingTheDigest() {
    OwnerAlertJob.FamilyBlock b = new OwnerAlertJob.FamilyBlock();
    b.name = 'Sharma Family';
    b.code = 'FAM-0001';
    b.overdue = 1;
    b.dueSoon = 2;
    b.dues.add('OVERDUE 2d - BESCOM ₹1,500');
    b.large.add('₹75,000 Expense · Furniture World · HDFC');

    Test.startTest();
    OwnerAlertService.Alert alert = OwnerAlertJob.compose(
      new List<OwnerAlertJob.FamilyBlock>{ b },
      1,
      0,
      Date.today()
    );
    Test.stopTest();

    Assert.areEqual(
      'VK Finance: 1 overdue, 2 due soon, 1 large entry, 1 job issue',
      alert.title,
      'Headline counts every kind'
    );
    Assert.isTrue(alert.text.contains('Sharma Family (FAM-0001)'), alert.text);
    Assert.isTrue(alert.text.contains('BESCOM'), 'Dues are listed');
    Assert.isTrue(
      alert.text.contains('Furniture World'),
      'Large entries are listed'
    );
    Assert.isTrue(
      alert.text.contains('Setup > Apex Jobs'),
      'Job issues point to Setup'
    );
    Assert.isTrue(
      alert.pushBody.startsWith('Sharma Family: 1 overdue, 2 due soon'),
      alert.pushBody
    );
  }

  @IsTest
  static void shouldListDueBillAndLargeEntry_WhenBuildingAFamilyBlock() {
    Family__c fam = familyA();
    System.runAs(owner(true)) {
      update as system new Family__c(
        Id = fam.Id,
        Large_Txn_Threshold__c = 10000
      );
      UserContext ctx = OwnerContext.forFamily(fam.Id, true);
      Id savings = LedgerTestData.account(ctx, 'Savings', 'Savings', OPENING)
        .id;
      BillService.createBill(
        ctx,
        new Map<String, Object>{
          'name' => 'BESCOM',
          'categoryId' => LedgerTestData.categoryId(ctx, 'Electricity'),
          'frequency' => 'Monthly',
          'nextDueDate' => String.valueOf(Date.today().addDays(2)),
          'expectedAmount' => 1500,
          'payFromAccountId' => savings,
          'reminderDays' => 3
        }
      );
      LedgerTestData.entry(
        ctx,
        'Expense',
        25000,
        savings,
        LedgerTestData.categoryId(ctx, 'Groceries'),
        Date.today(),
        'Furniture World'
      );
      LedgerTestData.entry(
        ctx,
        'Expense',
        500,
        savings,
        LedgerTestData.categoryId(ctx, 'Groceries'),
        Date.today(),
        'Corner Shop'
      );

      Test.startTest();
      OwnerAlertJob.FamilyBlock b = OwnerAlertJob.buildBlock(
        familyA(),
        3,
        Datetime.now().addHours(-24)
      );
      Test.stopTest();

      Assert.areEqual(1, b.dueSoon, 'The bill due in 2 days is listed');
      Assert.isTrue(b.dues[0].startsWith('Due in 2d - BESCOM'), b.dues[0]);
      Assert.areEqual(
        1,
        b.large.size(),
        'Only the entry at or above the threshold'
      );
      Assert.isTrue(b.large[0].contains('Furniture World'), b.large[0]);
    }
  }

  @IsTest
  static void shouldNoteMissingAdmin_WhenFamilyHasNoAdmin() {
    Family__c fam = familyA();
    System.runAs(owner(true)) {
      update as system new Portal_User__c(
        Id = VkfTestData.userId('admina'),
        Status__c = 'Disabled'
      );
      Test.startTest();
      OwnerAlertJob.FamilyBlock b = OwnerAlertJob.buildBlock(
        fam,
        3,
        Datetime.now().addHours(-24)
      );
      Test.stopTest();
      Assert.isTrue(
        b.checks[0].contains('No active Family Admin'),
        String.valueOf(b.checks)
      );
    }
  }

  @IsTest
  static void shouldDeliverDigestOnAllChannels_WhenJobFindsDues() {
    Family__c fam = familyA();
    System.runAs(owner(true)) {
      configure(true, true, '424242');
      UserContext ctx = OwnerContext.forFamily(fam.Id, true);
      Id savings = LedgerTestData.account(ctx, 'Savings', 'Savings', OPENING)
        .id;
      BillService.createBill(
        ctx,
        new Map<String, Object>{
          'name' => 'BESCOM',
          'categoryId' => LedgerTestData.categoryId(ctx, 'Electricity'),
          'frequency' => 'Monthly',
          'nextDueDate' => String.valueOf(Date.today()),
          'expectedAmount' => 1500,
          'payFromAccountId' => savings,
          'reminderDays' => 3
        }
      );
      TelegramMock mock = new TelegramMock(200, '{"ok":true}');
      Test.setMock(HttpCalloutMock.class, mock);
      OwnerAlertJob job = new OwnerAlertJob();

      // Run the batch steps in this transaction (after startTest, so the callout is allowed).
      Test.startTest();
      job.execute(
        null,
        [
          SELECT Id, Name, Family_Code__c, Large_Txn_Threshold__c
          FROM Family__c
          WITH SYSTEM_MODE
          ORDER BY Name
        ]
      );
      job.finish(null);
      Test.stopTest();

      Assert.isNotNull(OwnerAlertJob.lastAlert, 'A due bill produces a digest');
      Assert.isTrue(
        OwnerAlertJob.lastAlert.title.contains('due soon'),
        OwnerAlertJob.lastAlert.title
      );
      Assert.isTrue(
        OwnerAlertJob.lastAlert.text.contains('Due TODAY - BESCOM'),
        OwnerAlertJob.lastAlert.text
      );
      Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
        mock.seen.getBody()
      );
      Assert.areEqual(
        '424242',
        sent.get('chat_id'),
        'Posted to the configured chat'
      );
      Assert.areEqual(
        OwnerAlertService.TELEGRAM_ENDPOINT,
        mock.seen.getEndpoint(),
        'Through the named credential'
      );
      List<OwnerAlertService.ChannelResult> results = OwnerAlertService.lastResults;
      Assert.areEqual(
        OwnerAlertService.STATUS_SENT,
        resultFor(results, 'Telegram').status,
        'Telegram sent'
      );
      Assert.areEqual(
        OwnerAlertService.STATUS_SENT,
        resultFor(results, 'Push').status,
        String.valueOf(resultFor(results, 'Push').detail)
      );
      Assert.areNotEqual(
        OwnerAlertService.STATUS_SKIPPED,
        resultFor(results, 'Email').status,
        'Email attempted'
      );
    }
  }

  @IsTest
  static void shouldExplainBadToken_WhenTelegramRejects() {
    System.runAs(owner(true)) {
      configure(true, true, '424242');
      Test.setMock(
        HttpCalloutMock.class,
        new TelegramMock(401, '{"ok":false,"description":"Unauthorized"}')
      );
      Test.startTest();
      OwnerAlertService.ChannelResult r = resultFor(
        OwnerAlertService.deliver(sample()),
        'Telegram'
      );
      Test.stopTest();
      Assert.areEqual(
        OwnerAlertService.STATUS_FAILED,
        r.status,
        'A rejected call fails'
      );
      Assert.isTrue(
        r.detail.contains('Unauthorized') && r.detail.contains('bot token'),
        r.detail
      );
    }
  }

  @IsTest
  static void shouldAskForChatId_WhenTelegramHasNone() {
    System.runAs(owner(true)) {
      configure(true, true, null);
      Test.startTest();
      OwnerAlertService.ChannelResult r = resultFor(
        OwnerAlertService.deliver(sample()),
        'Telegram'
      );
      Test.stopTest();
      Assert.areEqual(
        OwnerAlertService.STATUS_FAILED,
        r.status,
        'No chat, no message'
      );
      Assert.isTrue(r.detail.contains('chat ID'), r.detail);
    }
  }

  @IsTest
  static void shouldSkipEveryChannel_WhenAlertsAreOff() {
    System.runAs(owner(true)) {
      configure(false, true, '424242');
      // No mock: a Telegram callout here would throw.
      Test.startTest();
      List<OwnerAlertService.ChannelResult> results = OwnerAlertService.deliver(
        sample()
      );
      Integer emails = Limits.getEmailInvocations();
      Test.stopTest();
      for (OwnerAlertService.ChannelResult r : results) {
        Assert.areEqual(
          OwnerAlertService.STATUS_SKIPPED,
          r.status,
          r.channel + ' is skipped'
        );
      }
      Assert.areEqual(0, emails, 'No email when switched off');
    }
  }

  @IsTest
  static void shouldFailPushAndEmail_WhenNobodyToNotify() {
    Test.startTest();
    OwnerAlertService.ChannelResult push = OwnerAlertService.sendPush(
      new Set<Id>(),
      sample()
    );
    OwnerAlertService.ChannelResult mail = OwnerAlertService.sendEmail(
      new Set<Id>(),
      sample()
    );
    Test.stopTest();
    Assert.isTrue(push.detail.contains('VKF Platform Admin'), push.detail);
    Assert.isTrue(mail.detail.contains('VKF Platform Admin'), mail.detail);
  }

  @IsTest
  static void shouldUseDefaults_WhenNoSettingsRowExists() {
    Test.startTest();
    VKF_Owner_Alerts__c cfg = OwnerAlertService.settings();
    Integer days = OwnerAlertService.dueWithinDays();
    Test.stopTest();
    Assert.isTrue(cfg.Enabled__c, 'On by default');
    Assert.isTrue(cfg.Push__c && cfg.Email__c, 'Push and email by default');
    Assert.isFalse(cfg.Telegram__c, 'Telegram needs setting up first');
    Assert.areEqual(3, days, 'Three days ahead by default');
  }

  @IsTest
  static void shouldSendTest_WhenOwnerPressesTheButton() {
    System.runAs(owner(true)) {
      configure(true, false, null);
      Test.startTest();
      List<Object> results = (List<Object>) JSON.deserializeUntyped(
        VkfOwnerController.sendTestAlert()
      );
      Test.stopTest();
      Assert.areEqual(3, results.size(), 'One result per channel');
      Assert.areEqual(
        'skipped',
        ((Map<String, Object>) results[0]).get('status'),
        'Telegram is off'
      );
    }
  }

  @IsTest
  static void shouldRefuseTestAlert_WhenUserLacksPermission() {
    System.runAs(owner(false)) {
      Test.startTest();
      try {
        VkfOwnerController.sendTestAlert();
        Assert.fail('The permission is required');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('VKF Platform Admin'),
          e.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void shouldStartBatch_WhenScheduled() {
    Test.startTest();
    String jobId = System.schedule(
      'VKF Owner Alerts test',
      '0 30 7 * * ?',
      new OwnerAlertJob()
    );
    Test.stopTest();
    Assert.isNotNull(jobId, 'Schedules like the other VKF jobs');
  }
}
