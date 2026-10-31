@IsTest
private class VkfOwnerControllerTest {
  private static final Decimal OPENING = 10000;

  @TestSetup
  static void setup() {
    VkfTestData.twoFamilies();
  }

  private static User owner(Boolean platformAdmin) {
    String profileName = platformAdmin
      ? 'System Administrator'
      : 'Standard User';
    User u = new User(
      Alias = 'vkfown',
      Email = 'vkf.owner@example.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Owner',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [
        SELECT Id
        FROM Profile
        WHERE Name = :profileName
        WITH SYSTEM_MODE
      ]
      .Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = 'vkf.owner.' + Datetime.now().getTime() + '@example.test'
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

  private static Id familyId(String name) {
    return [SELECT Id FROM Family__c WHERE Name = :name WITH SYSTEM_MODE].Id;
  }

  /** A savings account in the family, created through the owner context itself. */
  private static Id savings(Id familyId) {
    return LedgerTestData.account(
        OwnerContext.forFamily(familyId, true),
        'Savings',
        'Savings',
        OPENING
      )
      .id;
  }

  private static String expense(Id accountId, Id categoryId, Decimal amount) {
    return JSON.serialize(
      new Map<String, Object>{
        'type' => 'Expense',
        'amount' => amount,
        'accountId' => accountId,
        'categoryId' => categoryId,
        'date' => String.valueOf(Date.today()),
        'payee' => 'Fresh Mart',
        'paymentMode' => 'UPI'
      }
    );
  }

  @IsTest
  static void shouldRefuseEveryMethod_WhenUserLacksPermission() {
    Id famA = familyId('Family A');
    Integer refused = 0;
    System.runAs(owner(false)) {
      Test.startTest();
      for (Integer i = 0; i < 5; i++) {
        try {
          switch on i {
            when 0 {
              VkfOwnerController.getFamilies();
            }
            when 1 {
              VkfOwnerController.getOverview(famA, null);
            }
            when 2 {
              VkfOwnerController.saveEntry(famA, '{}');
            }
            when 3 {
              VkfOwnerController.voidTransaction(famA, null);
            }
            when else {
              VkfOwnerController.getMembers(famA);
            }
          }
          Assert.fail('Method ' + i + ' should require the permission');
        } catch (AuraHandledException e) {
          Assert.isTrue(
            e.getMessage().contains('VKF Platform Admin'),
            e.getMessage()
          );
          refused++;
        }
      }
      Test.stopTest();
    }
    Assert.areEqual(5, refused, 'Every entry point is gated');
  }

  @IsTest
  static void shouldListFamiliesWithCountsAndAdmin_WhenOwner() {
    System.runAs(owner(true)) {
      Test.startTest();
      List<Object> families = (List<Object>) JSON.deserializeUntyped(
        VkfOwnerController.getFamilies()
      );
      Test.stopTest();

      Assert.areEqual(2, families.size(), 'Both families are listed');
      Map<String, Object> a = (Map<String, Object>) families[0];
      Assert.areEqual(
        'Family A',
        a.get('name'),
        'Sorted by name within the same status'
      );
      Assert.areEqual(4, a.get('memberCount'), 'Family A has four members');
      Assert.areEqual(
        'Admina Tester',
        a.get('adminName'),
        'The Family Admin is named'
      );
      Assert.areEqual(
        'INR',
        a.get('currencyCode'),
        'Blank currency defaults to INR'
      );
    }
  }

  @IsTest
  static void shouldPostExpenseThroughLedgerAndTagAudit_WhenOwnerSavesEntry() {
    Id famA = familyId('Family A');
    User ownerUser = owner(true);
    System.runAs(ownerUser) {
      Id accountId = savings(famA);
      Id groceries = LedgerTestData.categoryId(
        OwnerContext.forFamily(famA, false),
        'Groceries'
      );

      Test.startTest();
      Map<String, Object> saved = (Map<String, Object>) JSON.deserializeUntyped(
        VkfOwnerController.saveEntry(famA, expense(accountId, groceries, 1250))
      );
      Test.stopTest();

      Assert.areEqual('Expense', saved.get('type'), 'An expense is recorded');
      Assert.areEqual(
        OPENING - 1250,
        LedgerTestData.balance(accountId),
        'The trigger moves the balance'
      );
      Id savedId = (Id) saved.get('id');
      Transaction__c t = [
        SELECT Family__c, Payee__c
        FROM Transaction__c
        WHERE Id = :savedId
        WITH SYSTEM_MODE
      ];
      Assert.areEqual(famA, t.Family__c, 'Written to the chosen family');
      Assert.areEqual('Fresh Mart', t.Payee__c, 'Details are applied');
      Assert.areEqual(
        ownerUser.Id,
        AuditService.actingOwnerId,
        'Audit events carry the owner'
      );
    }
  }

  @IsTest
  static void shouldCreateBothLegs_WhenOwnerSavesTransfer() {
    Id famA = familyId('Family A');
    System.runAs(owner(true)) {
      Id fromId = savings(famA);
      Id toId = LedgerTestData.account(
          OwnerContext.forFamily(famA, true),
          'Wallet',
          'Cash',
          0
        )
        .id;

      Test.startTest();
      VkfOwnerController.saveEntry(
        famA,
        JSON.serialize(
          new Map<String, Object>{
            'type' => 'Transfer',
            'fromAccountId' => fromId,
            'toAccountId' => toId,
            'amount' => 500,
            'date' => String.valueOf(Date.today())
          }
        )
      );
      Test.stopTest();

      Assert.areEqual(
        OPENING - 500,
        LedgerTestData.balance(fromId),
        'Money leaves the source'
      );
      Assert.areEqual(
        500,
        LedgerTestData.balance(toId),
        'Money arrives in the target'
      );
    }
  }

  @IsTest
  static void shouldRestoreBalance_WhenOwnerVoidsTransaction() {
    Id famA = familyId('Family A');
    System.runAs(owner(true)) {
      Id accountId = savings(famA);
      Id groceries = LedgerTestData.categoryId(
        OwnerContext.forFamily(famA, false),
        'Groceries'
      );
      Id txnId = (Id) ((Map<String, Object>) JSON.deserializeUntyped(
          VkfOwnerController.saveEntry(famA, expense(accountId, groceries, 800))
        ))
        .get('id');

      Test.startTest();
      VkfOwnerController.voidTransaction(famA, txnId);
      Test.stopTest();

      Assert.areEqual(
        OPENING,
        LedgerTestData.balance(accountId),
        'Voiding gives the money back'
      );
      Assert.areEqual(
        'Void',
        [
          SELECT Status__c
          FROM Transaction__c
          WHERE Id = :txnId
          WITH SYSTEM_MODE
        ]
        .Status__c,
        'Marked void'
      );
    }
  }

  @IsTest
  static void shouldNotSeeOtherFamilyEntries_WhenReadingOneFamily() {
    Id famA = familyId('Family A');
    Id famB = familyId('Family B');
    System.runAs(owner(true)) {
      Id accountB = savings(famB);
      Id groceriesB = LedgerTestData.categoryId(
        OwnerContext.forFamily(famB, false),
        'Groceries'
      );
      VkfOwnerController.saveEntry(famB, expense(accountB, groceriesB, 300));

      Test.startTest();
      Map<String, Object> pageA = (Map<String, Object>) JSON.deserializeUntyped(
        VkfOwnerController.getTransactions(famA, '{"limit":50}')
      );
      Map<String, Object> pageB = (Map<String, Object>) JSON.deserializeUntyped(
        VkfOwnerController.getTransactions(famB, null)
      );
      Test.stopTest();

      Assert.areEqual(
        0,
        ((List<Object>) pageA.get('items')).size(),
        'Family A sees none of Family B'
      );
      Assert.areEqual(
        1,
        ((List<Object>) pageB.get('items')).size(),
        'Family B sees its own entry'
      );
    }
  }

  @IsTest
  static void shouldReturnScreens_WhenOwnerOpensFamily() {
    Id famA = familyId('Family A');
    System.runAs(owner(true)) {
      savings(famA);

      Test.startTest();
      Map<String, Object> overview = (Map<String, Object>) JSON.deserializeUntyped(
        VkfOwnerController.getOverview(famA, null)
      );
      Map<String, Object> options = (Map<String, Object>) JSON.deserializeUntyped(
        VkfOwnerController.getEntryOptions(famA)
      );
      Map<String, Object> budget = (Map<String, Object>) JSON.deserializeUntyped(
        VkfOwnerController.getBudget(famA, null)
      );
      List<Object> members = (List<Object>) JSON.deserializeUntyped(
        VkfOwnerController.getMembers(famA)
      );
      List<Object> dues = (List<Object>) JSON.deserializeUntyped(
        VkfOwnerController.getDues(famA, 500)
      );
      Test.stopTest();

      Assert.areEqual(
        true,
        overview.get('wholeFamily'),
        'The owner sees the whole family'
      );
      Assert.areEqual(
        1,
        ((List<Object>) options.get('accounts')).size(),
        'The new account is offered'
      );
      Assert.areEqual(
        4,
        ((List<Object>) options.get('members')).size(),
        'All active members are offered'
      );
      Assert.isFalse(
        ((List<Object>) options.get('paymentModes')).isEmpty(),
        'Payment modes are offered'
      );
      Assert.areEqual(
        LedgerUtil.monthKey(Date.today()),
        budget.get('month'),
        'Current month budget'
      );
      Assert.areEqual(4, members.size(), 'Family A members only');
      Assert.areEqual(0, dues.size(), 'Nothing is due yet');
    }
  }

  @IsTest
  static void shouldPayBill_WhenOwnerPaysDue() {
    Id famA = familyId('Family A');
    System.runAs(owner(true)) {
      UserContext ctx = OwnerContext.forFamily(famA, true);
      Id accountId = savings(famA);
      BillService.createBill(
        ctx,
        new Map<String, Object>{
          'name' => 'Power',
          'categoryId' => LedgerTestData.categoryId(ctx, 'Electricity'),
          'frequency' => 'Monthly',
          'nextDueDate' => String.valueOf(Date.today().addDays(3)),
          'expectedAmount' => 1500,
          'payFromAccountId' => accountId,
          'reminderDays' => 3
        }
      );
      Map<String, Object> due = (Map<String, Object>) ((List<Object>) JSON.deserializeUntyped(
        VkfOwnerController.getDues(famA, 30)
      ))[0];

      Test.startTest();
      Map<String, Object> paid = (Map<String, Object>) JSON.deserializeUntyped(
        VkfOwnerController.payDue(
          famA,
          'bill',
          (Id) due.get('id'),
          (Id) due.get('parentId'),
          null
        )
      );
      Test.stopTest();

      Assert.areEqual('Paid', paid.get('status'), 'Paid in full by default');
      Assert.areEqual(
        OPENING - 1500,
        LedgerTestData.balance(accountId),
        'Paid from the bill account'
      );
    }
  }

  @IsTest
  static void shouldRejectCardKind_WhenPayingDue() {
    Id famA = familyId('Family A');
    System.runAs(owner(true)) {
      Test.startTest();
      try {
        VkfOwnerController.payDue(famA, 'card', null, null, null);
        Assert.fail('Card bills are paid as transfers');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('transfer'), e.getMessage());
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void shouldAllowReadButRefuseWrite_WhenFamilySuspended() {
    Id famA = familyId('Family A');
    System.runAs(owner(true)) {
      // Inside runAs: a User insert after non-setup DML would be a mixed-DML error.
      update as system new Family__c(Id = famA, Status__c = 'Suspended');
      Test.startTest();
      String members = VkfOwnerController.getMembers(famA);
      try {
        VkfOwnerController.saveEntry(famA, '{}');
        Assert.fail('Suspended families are read-only');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('suspended'), e.getMessage());
      }
      Test.stopTest();
      Assert.areEqual(
        4,
        ((List<Object>) JSON.deserializeUntyped(members)).size(),
        'Reads still work'
      );
    }
  }

  @IsTest
  static void shouldReportNoAdmin_WhenFamilyHasNoAdmin() {
    Id famA = familyId('Family A');
    System.runAs(owner(true)) {
      update as system new Portal_User__c(
        Id = VkfTestData.userId('admina'),
        Status__c = 'Disabled'
      );
      Test.startTest();
      try {
        VkfOwnerController.getOverview(famA, null);
        Assert.fail('There is no admin to act as');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('no Family Admin'),
          e.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void shouldRejectMalformedJson_WhenSavingEntry() {
    Id famA = familyId('Family A');
    System.runAs(owner(true)) {
      Test.startTest();
      try {
        VkfOwnerController.saveEntry(famA, '[1,2]');
        Assert.fail('A JSON array is not an entry');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('JSON object'), e.getMessage());
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void shouldHideInternals_WhenUnexpectedErrorOccurs() {
    Test.startTest();
    AuraHandledException e = VkfOwnerController.auraError(
      new NullPointerException()
    );
    AuraHandledException coded = VkfOwnerController.auraError(
      new PortalException('NOT_FOUND')
    );
    Test.stopTest();
    Assert.areEqual(
      'Something went wrong. Please try again.',
      e.getMessage(),
      'No stack trace or type leaks'
    );
    Assert.areEqual(
      'That record no longer exists.',
      coded.getMessage(),
      'Codes without details get a friendly message'
    );
  }
}
