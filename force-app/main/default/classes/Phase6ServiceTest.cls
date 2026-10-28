@IsTest
private class Phase6ServiceTest {
    @TestSetup static void setup() {
        VkfTestData.twoFamilies();
        List<Family__c> families = [SELECT Id FROM Family__c WITH SYSTEM_MODE];
        for (Family__c f : families) f.Enhancements__c = 'IMPORTS,RECEIPTS,REQUESTS,GOALS,INSIGHTS,INSTALL';
        update as system families;
    }

    @IsTest static void switchesRequireFamilyAdminAndStepUp() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina'), member = VkfTestData.ctx('membera');
        Assert.isTrue(EnhancementService.enabledFor(admin).contains('GOALS'));
        try { EnhancementService.configure(member, new Map<String,Object>{ 'enabled' => new List<Object>() }); Assert.fail(); }
        catch (PortalException e) { Assert.areEqual('NOT_AUTHORIZED', e.code()); }
        EnhancementService.configure(admin, new Map<String,Object>{ 'enabled' => new List<Object>{ 'GOALS' }, 'currentPassword' => VkfTestData.PASSWORD });
        Assert.areEqual(1, EnhancementService.enabledFor(admin).size());
        try { SpendRequestService.listRequests(admin); Assert.fail(); }
        catch (PortalException e) { Assert.areEqual('NOT_AUTHORIZED', e.code()); }
        Assert.isTrue(EnhancementService.enabledFor(VkfTestData.ctx('adminb')).contains('REQUESTS'), 'Caches must be keyed by family.');
    }

    @IsTest static void childApprovalDoesNotPostAndRecordingIsIdempotent() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina'), child = VkfTestData.ctx('childa');
        FinanceDtos.Account account = AccountService.createAccount(admin, new Map<String,Object>{ 'name'=>'Pocket money','type'=>'Cash','openingBalance'=>1000,'ownerId'=>child.userId });
        Id category = LedgerTestData.categoryId(admin,'Groceries');
        Map<String,Object> request = SpendRequestService.create(child,new Map<String,Object>{ 'title'=>'School supplies','amount'=>100,'accountId'=>account.id,'categoryId'=>category });
        Id requestId = (Id) request.get('id');
        Assert.areEqual('Approved', SpendRequestService.act(admin,requestId,'approve',new Map<String,Object>()).get('status'));
        Assert.areEqual(1000,LedgerTestData.balance(account.id),'Approval must not move money.');
        Map<String,Object> recorded = SpendRequestService.act(child,requestId,'record',new Map<String,Object>());
        Assert.areEqual('Recorded',recorded.get('status'));
        SpendRequestService.act(child,requestId,'record',new Map<String,Object>());
        Assert.areEqual(900,LedgerTestData.balance(account.id),'Retry must not create another expense.');
        try { SpendRequestService.act(VkfTestData.ctx('adminb'),requestId,'approve',new Map<String,Object>()); Assert.fail(); }
        catch (PortalException e) { Assert.areEqual('NOT_FOUND',e.code()); }
    }

    @IsTest static void expiredDeclinedAndOtherMembersCannotRecord() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina'), child = VkfTestData.ctx('childa');
        FinanceDtos.Account account = AccountService.createAccount(admin,new Map<String,Object>{ 'name'=>'Child cash','type'=>'Cash','openingBalance'=>100,'ownerId'=>child.userId });
        Id id = (Id) SpendRequestService.create(child,new Map<String,Object>{ 'title'=>'Snack','amount'=>20,'accountId'=>account.id,'categoryId'=>LedgerTestData.categoryId(admin,'Groceries') }).get('id');
        SpendRequestService.act(admin,id,'decline',new Map<String,Object>{ 'note'=>'Next week' });
        try { SpendRequestService.act(child,id,'record',new Map<String,Object>()); Assert.fail(); }
        catch (PortalException e) { Assert.areEqual('CONFLICT',e.code()); }
        try { SpendRequestService.listRequests(VkfTestData.ctx('membera')); Assert.fail(); }
        catch (PortalException e) { Assert.areEqual('NOT_AUTHORIZED',e.code()); }
        Assert.areEqual(100,LedgerTestData.balance(account.id));
    }

    @IsTest static void goalsTrackLedgerAndPreventDoubleAllocation() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id account = LedgerTestData.account(admin,'Holiday savings','Savings',1000).id;
        Map<String,Object> body = new Map<String,Object>{ 'title'=>'Holiday','target'=>5000,'accountId'=>account,'includeExisting'=>false };
        Id goal = (Id) SavingsGoalService.save(admin,null,body).get('id');
        Assert.areEqual(0,SavingsGoalService.listGoals(admin)[0].get('progress'));
        LedgerTestData.entry(admin,'Income',500,account,LedgerTestData.categoryId(admin,'Salary'));
        Assert.areEqual(500,SavingsGoalService.listGoals(admin)[0].get('progress'));
        try { SavingsGoalService.save(admin,null,body); Assert.fail(); }
        catch (PortalException e) { Assert.areEqual('VALIDATION',e.code()); }
        Assert.areEqual(0,SavingsGoalService.listGoals(VkfTestData.ctx('memberb')).size());
        try { SavingsGoalService.archive(VkfTestData.ctx('adminb'),goal); Assert.fail(); }
        catch (PortalException e) { Assert.areEqual('NOT_FOUND',e.code()); }
        SavingsGoalService.archive(admin,goal);
        Assert.areEqual(0,SavingsGoalService.listGoals(admin).size());
        SavingsGoalService.save(admin,null,body);
    }

    @IsTest static void insightsNeverExposeAnotherFamilyAndDismissIsPersonal() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id account = LedgerTestData.account(admin,'Bank','Savings',1000).id;
        RecurringService.createRule(admin,new Map<String,Object>{ 'name'=>'Streaming','type'=>'Expense','amount'=>499,'accountId'=>account,
            'categoryId'=>LedgerTestData.categoryId(admin,'Groceries'),'frequency'=>'Monthly','nextRunDate'=>String.valueOf(Date.today()),'mode'=>'Suggest' });
        List<Map<String,Object>> items = SmartInsightService.insights(admin);
        Assert.areEqual(1,items.size());
        Assert.areEqual(0,SmartInsightService.insights(VkfTestData.ctx('membera')).size());
        Assert.areEqual(0,SmartInsightService.insights(VkfTestData.ctx('adminb')).size());
        SmartInsightService.dismiss(admin,new Map<String,Object>{ 'key'=>items[0].get('key'),'snooze'=>true });
        Assert.areEqual(0,SmartInsightService.insights(admin).size());
    }
}
