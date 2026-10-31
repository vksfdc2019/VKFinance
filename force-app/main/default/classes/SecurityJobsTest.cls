@IsTest
private class SecurityJobsTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void reconcileFixesOnlyDriftedBalances() {
        VkfTestData.fastPolicy();
        UserContext ctx = VkfTestData.ctx('admina');
        Id savings = LedgerTestData.account(ctx, 'Savings', 'Savings', 1000).id;
        FinanceDtos.Account createdCard = LedgerTestData.account(ctx, 'Card', 'Credit Card', 0);
        Assert.isNotNull(createdCard.id, 'A new standalone card must return its persisted account ID.');
        Id card = createdCard.id;
        LedgerTestData.entry(ctx, 'Expense', 250, card, LedgerTestData.categoryId(ctx, 'Electronics'));
        update as system new Financial_Account__c(Id = savings, Current_Balance__c = 5);

        Test.startTest();
        new BalanceReconcileJob().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.areEqual(1000, LedgerTestData.balance(savings));
        Assert.areEqual(250, LedgerTestData.balance(card), 'Untouched');
        Assert.areEqual(0, BalanceReconcileJob.reconcileFamily(ctx.familyId), 'Nothing left to fix');
    }

    @IsTest
    static void purgeRemovesWhatIsNoLongerNeeded() {
        VkfTestData.fastPolicy();
        Id memberId = VkfTestData.userId('membera');
        Id familyId = [SELECT Family__c FROM Portal_User__c WHERE Id = :memberId WITH SYSTEM_MODE].Family__c;
        Datetime old = Datetime.now().addDays(-2);
        insert as system new List<Auth_Token__c>{
            new Auth_Token__c(Portal_User__c = memberId, Family__c = familyId, Type__c = 'Reset', Token_Hash__c = 'spent', Used_At__c = old),
            new Auth_Token__c(Portal_User__c = memberId, Family__c = familyId, Type__c = 'Reset', Token_Hash__c = 'live', Expires_At__c = Datetime.now().addMinutes(30))
        };
        insert as system new List<Rate_Limit__c>{
            new Rate_Limit__c(Key__c = 'auth:old', Window_Start__c = old, Hits__c = 4),
            new Rate_Limit__c(Key__c = 'auth:new', Window_Start__c = Datetime.now(), Hits__c = 1)
        };
        List<Password_History__c> history = new List<Password_History__c>();
        for (Integer i = 0; i < 7; i++) {
            history.add(new Password_History__c(Portal_User__c = memberId, Password_Hash__c = 'h' + i, Password_Salt__c = 's', Hash_Iterations__c = 2));
        }
        insert as system history;

        Map<String, Integer> counts = RetentionPurgeJob.run();

        Assert.areEqual(1, counts.get('tokens'));
        Assert.areEqual(1, counts.get('rateLimits'));
        Assert.areEqual(2, counts.get('passwordHistory'));
        Assert.areEqual(5, [SELECT COUNT() FROM Password_History__c WHERE Portal_User__c = :memberId WITH SYSTEM_MODE]);
        Assert.areEqual(1, [SELECT COUNT() FROM Auth_Token__c WHERE Token_Hash__c = 'live' WITH SYSTEM_MODE]);
    }

    @IsTest
    static void removedMembersLoseTheirSecrets() {
        VkfTestData.fastPolicy();
        MfaService.clockSeconds = 1700000000L;
        UserContext member = VkfTestData.ctx('membera');
        MfaService.beginSetup(member, VkfTestData.PASSWORD);
        String secret = [SELECT MFA_Secret__c FROM Portal_User__c WHERE Id = :member.userId WITH SYSTEM_MODE].MFA_Secret__c;
        MfaService.confirmSetup(member, MfaService.codeAt(secret, MfaService.currentStep()));
        insert as system new Password_History__c(Portal_User__c = member.userId, Password_Hash__c = 'h', Password_Salt__c = 's', Hash_Iterations__c = 2);

        UserContext admin = VkfTestData.ctx('admina');
        MemberService.updateMember(admin, member.userId, new Map<String, Object>{ 'status' => 'Removed', 'currentPassword' => VkfTestData.PASSWORD });
        Portal_User__c removed = [SELECT MFA_Method__c, MFA_Secret__c, Password_Hash__c FROM Portal_User__c WHERE Id = :member.userId WITH SYSTEM_MODE];
        Assert.areEqual('None', removed.MFA_Method__c);
        Assert.isNull(removed.MFA_Secret__c);
        Assert.isNull(removed.Password_Hash__c);

        RetentionPurgeJob.run();
        Assert.areEqual(0, [SELECT COUNT() FROM Password_History__c WHERE Portal_User__c = :member.userId WITH SYSTEM_MODE]);
    }

    @IsTest
    static void digestListsWhatNeedsAttentionAndSends() {
        VkfTestData.fastPolicy();
        SecurityDigestJob.Digest d = SecurityDigestJob.build(Datetime.now().addDays(-7));
        Assert.areEqual(2, d.families.size());
        Assert.isTrue(d.families[0].adminsWithoutTwoStep.size() > 0);
        Boolean flagged = false;
        for (String item : d.attention) {
            flagged = flagged || item.contains('without two-step');
        }
        Assert.isTrue(flagged, String.valueOf(d.attention));

        Test.startTest();
        System.schedule('VKF Digest Test', '0 0 7 ? * MON', new SecurityDigestJob());
        System.schedule('VKF Purge Test', '0 0 4 ? * SUN', new RetentionPurgeJob());
        Assert.isTrue(SecurityDigestJob.send());
        Test.stopTest();
        Assert.isTrue(SecurityDigestJob.lastText.contains('Family A'), SecurityDigestJob.lastText);
    }
}