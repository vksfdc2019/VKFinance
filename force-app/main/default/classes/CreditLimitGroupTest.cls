@IsTest
private class CreditLimitGroupTest {
    @TestSetup static void setup() { VkfTestData.twoFamilies(); }
    private class Fixture {
        UserContext admin;
        Id first;
        Id second;
        Id bank;
        Fixture() {
            VkfTestData.fastPolicy(); admin = VkfTestData.ctx('admina');
            first = LedgerTestData.account(admin, 'Primary card', 'Credit Card', 30000).id;
            second = LedgerTestData.account(admin, 'Companion card', 'Credit Card', 20000).id;
            bank = LedgerTestData.account(admin, 'Bank', 'Savings', 100000).id;
        }
        Map<String,Object> input(Decimal version) {
            Map<String,Object> b = new Map<String,Object>{'name'=>'Bank shared facility','issuer'=>'Example Bank','creditLimit'=>300000,
                'cardIds'=>new List<Object>{first,second}};
            if(version!=null)b.put('expectedVersion',version); return b;
        }
        CreditLimitGroupService.GroupView create() { return CreditLimitGroupService.save(admin,null,input(null),false).groups[0]; }
    }
    @IsTest static void oneFacilityCountsOnceAndDoesNotMoveBalances() {
        Fixture f=new Fixture(); Test.startTest();
        CreditLimitGroupService.GroupView g=f.create();
        Assert.areEqual(50000,g.outstanding);Assert.areEqual(250000,g.available);Assert.areEqual(2,g.activeCardCount);
        CreditLimitGroupService.Overview result=CreditLimitGroupService.overview(f.admin);
        Assert.areEqual(300000,result.totals.creditLimit);Assert.areEqual(250000,result.totals.available);Assert.areEqual(1,result.totals.facilities);
        for(FinanceDtos.Account a:AccountService.listAccounts(f.admin,false)) if(a.type=='Credit Card') {
            Assert.areEqual(300000,a.creditLimit);Assert.areEqual(250000,a.card.available);Assert.areEqual(g.id,a.sharedCredit.id);
        }
        Assert.areEqual(30000,LedgerTestData.balance(f.first));Assert.areEqual(20000,LedgerTestData.balance(f.second));
        Test.stopTest();
    }
    @IsTest static void paymentsVoidsExpensesAndReconciliationUseLiveBalances() {
        Fixture f=new Fixture();f.create();Test.startTest();
        FinanceDtos.Transfer payment=LedgerTestData.transfer(f.admin,f.bank,f.first,10000);
        Assert.areEqual(260000,CreditLimitGroupService.overview(f.admin).groups[0].available);
        TransactionService.voidTransaction(f.admin,payment.inLeg.id);
        Assert.areEqual(250000,CreditLimitGroupService.overview(f.admin).groups[0].available);
        LedgerTestData.entry(f.admin,'Expense',5000,f.second,LedgerTestData.categoryId(f.admin,'Groceries'));
        Assert.areEqual(245000,CreditLimitGroupService.overview(f.admin).groups[0].available);
        AccountService.reconcile(f.admin,f.first,new Map<String,Object>{'actualBalance'=>0,'date'=>String.valueOf(Date.today())});
        Assert.areEqual(275000,CreditLimitGroupService.overview(f.admin).groups[0].available);
        Test.stopTest();
    }
    @IsTest static void negativeBalancesDoNotInflateSharedCreditAndOverLimitIsExplicit() {
        Fixture f=new Fixture();CreditLimitGroupService.GroupView g=f.create();Test.startTest();
        AccountService.reconcile(f.admin,f.first,new Map<String,Object>{'actualBalance'=>-5000,'date'=>String.valueOf(Date.today())});
        Assert.areEqual(280000,CreditLimitGroupService.overview(f.admin).groups[0].available);
        Map<String,Object> b=f.input(g.version);b.put('creditLimit',10000);
        CreditLimitGroupService.GroupView reduced=CreditLimitGroupService.save(f.admin,g.id,b,false).groups[0];
        Assert.areEqual(0,reduced.available);Assert.areEqual(10000,reduced.overLimit);Assert.areEqual(200,reduced.utilisationPct);
        Test.stopTest();
    }
    @IsTest static void membershipChangesArchiveAndStaleEditsAreSafe() {
        Fixture f=new Fixture();CreditLimitGroupService.GroupView g=f.create();Test.startTest();
        Map<String,Object> b=f.input(g.version);b.put('cardIds',new List<Object>{f.first});
        CreditLimitGroupService.GroupView changed=CreditLimitGroupService.save(f.admin,g.id,b,false).groups[0];
        Assert.areEqual(1,changed.cards.size());Assert.areEqual(270000,changed.available);
        Assert.isNull([SELECT Credit_Limit_Group__c FROM Financial_Account__c WHERE Id=:f.second WITH SYSTEM_MODE].Credit_Limit_Group__c);
        try {CreditLimitGroupService.save(f.admin,g.id,f.input(g.version),false);Assert.fail('stale edits must fail');}
        catch(PortalException e){Assert.areEqual('CONFLICT',e.code());}
        CreditLimitGroupService.Overview archived=CreditLimitGroupService.save(f.admin,g.id,new Map<String,Object>{'expectedVersion'=>changed.version},true);
        Assert.areEqual(0,archived.groups.size());Assert.areEqual(100000,archived.totals.creditLimit,'original independent limits return');
        Assert.areEqual(50000,archived.totals.available);Assert.areEqual(30000,LedgerTestData.balance(f.first));
        Test.stopTest();
    }
    @IsTest static void hiddenCardsCannotBeInferredFromGroupAvailability() {
        Fixture f=new Fixture();UserContext member=VkfTestData.ctx('membera');
        AccountService.updateAccount(f.admin,f.first,new Map<String,Object>{'ownerId'=>member.userId});
        f.create();Test.startTest();
        List<FinanceDtos.Account> own=AccountService.listAccounts(member,false);
        Assert.areEqual(1,own.size());Assert.isTrue(own[0].sharedCreditRestricted);
        Assert.isNull(own[0].sharedCredit);Assert.isNull(own[0].creditLimit);Assert.isNull(own[0].card.available);Assert.isNull(own[0].card.utilisationPct);
        CreditLimitGroupService.Overview view=CreditLimitGroupService.overview(member);
        Assert.areEqual(0,view.groups.size());Assert.isFalse(view.totals.complete);Assert.isNull(view.totals.creditLimit);Assert.isNull(view.totals.available);
        Assert.areEqual(30000,view.totals.outstanding);
        AccountService.updateAccount(f.admin,f.second,new Map<String,Object>{'isShared'=>true});
        CreditLimitGroupService.Overview allowed=CreditLimitGroupService.overview(member);
        Assert.areEqual(1,allowed.groups.size());Assert.areEqual(250000,allowed.totals.available);Assert.isFalse(allowed.canManage);
        Test.stopTest();
    }
    @IsTest static void crossFamilyAndNonAdminMutationsAreRejected() {
        Fixture f=new Fixture();CreditLimitGroupService.GroupView g=f.create();UserContext other=VkfTestData.ctx('adminb');
        Id foreign=LedgerTestData.account(other,'Other card','Credit Card',1000).id;
        Test.startTest();
        for(UserContext ctx:new List<UserContext>{VkfTestData.ctx('membera'),VkfTestData.ctx('childa')}) {
            try{CreditLimitGroupService.save(ctx,null,f.input(null),false);Assert.fail('only admins manage groups');}
            catch(PortalException e){Assert.areEqual('NOT_AUTHORIZED',e.code());}
        }
        try{CreditLimitGroupService.save(other,g.id,f.input(g.version),false);Assert.fail('other family');}
        catch(PortalException e){Assert.areEqual('NOT_FOUND',e.code());}
        Map<String,Object> b=f.input(g.version);b.put('cardIds',new List<Object>{foreign});
        try{CreditLimitGroupService.save(f.admin,g.id,b,false);Assert.fail('foreign card');}
        catch(PortalException e){Assert.areEqual('NOT_FOUND',e.code());}
        Assert.areEqual(0,CreditLimitGroupService.overview(other).groups.size());Test.stopTest();
    }
    @IsTest static void invalidMembershipLimitsAndDirectWritesAreRejected() {
        Fixture f=new Fixture();CreditLimitGroupService.GroupView g=f.create();Test.startTest();
        Map<String,Object> b=f.input(g.version);b.put('cardIds',new List<Object>{f.bank});
        try{CreditLimitGroupService.save(f.admin,g.id,b,false);Assert.fail('bank is not a card');}catch(PortalException e){Assert.areEqual('VALIDATION',e.code());}
        b=f.input(g.version);b.put('creditLimit',0.001);
        try{CreditLimitGroupService.save(f.admin,g.id,b,false);Assert.fail('rounded limit cannot be zero');}catch(PortalException e){Assert.areEqual('VALIDATION',e.code());}
        try{AccountService.updateAccount(f.admin,f.first,new Map<String,Object>{'creditLimit'=>999});Assert.fail('shared limit cannot be overridden on one card');}catch(PortalException e){Assert.areEqual('VALIDATION',e.code());}
        try{update as system new Financial_Account__c(Id=f.bank,Credit_Limit_Group__c=g.id);Assert.fail('direct membership must be guarded');}catch(DmlException e){Assert.isTrue(e.getMessage().contains('same family'));}
        UserContext other=VkfTestData.ctx('adminb');Id otherCard=LedgerTestData.account(other,'Other','Credit Card',0).id;
        try{update as system new Financial_Account__c(Id=otherCard,Credit_Limit_Group__c=g.id);Assert.fail('direct cross-family membership');}catch(DmlException e){Assert.isTrue(e.getMessage().contains('same family'));}
        Test.stopTest();
    }
    @IsTest static void duplicateGroupsAndClosedCardsCannotBeSilentlyAttached() {
        Fixture f=new Fixture();CreditLimitGroupService.GroupView g=f.create();Test.startTest();
        Map<String,Object> b=f.input(null);b.put('name','Different group');
        try{CreditLimitGroupService.save(f.admin,null,b,false);Assert.fail('one card cannot belong to two pools');}catch(PortalException e){Assert.areEqual('CONFLICT',e.code());}
        Id closed=LedgerTestData.account(f.admin,'Closed card','Credit Card',0).id;
        AccountService.updateAccount(f.admin,closed,new Map<String,Object>{'status'=>'Closed'});
        b=f.input(null);b.put('name','Closed group');b.put('cardIds',new List<Object>{closed});
        try{CreditLimitGroupService.save(f.admin,null,b,false);Assert.fail('closed card cannot join');}catch(PortalException e){Assert.areEqual('VALIDATION',e.code());}
        Test.stopTest();
    }
    @IsTest static void cardReportsCountSharedLimitOnce() {
        Fixture f=new Fixture();f.create();Test.startTest();
        ReportService.Report report=ReportService.run(f.admin,'cards',new Map<String,String>{'from'=>String.valueOf(Date.today().toStartOfMonth()),'to'=>String.valueOf(Date.today())});
        Decimal total;
        for(ReportService.Kpi k:report.kpis)if(k.label=='Total credit limit')total=k.value;
        Assert.areEqual(300000,total);Assert.areEqual(2,report.detail.rows.size());Test.stopTest();
    }
    @IsTest static void restCreateReadAndArchiveUseExistingSessionBoundary() {
        Fixture f=new Fixture();Portal_User__c user=IdentitySelector.byId(f.admin.userId);
        SessionService.NewSession session=SessionService.create(user,'FULL',VkfTestData.UA);
        Test.startTest();
        RestContext.request=new RestRequest();RestContext.response=new RestResponse();
        RestContext.request.requestURI='/services/apexrest/vkf/v1/accounts/credit-groups';RestContext.request.httpMethod='POST';
        RestContext.request.addHeader('X-VKF-Session',session.token);RestContext.request.addHeader('User-Agent',VkfTestData.UA);
        RestContext.request.requestBody=Blob.valueOf(JSON.serialize(f.input(null)));
        VkfAccountsResource.post();Assert.areEqual(201,RestContext.response.statusCode);
        CreditLimitGroupService.GroupView g=CreditLimitGroupService.overview(f.admin).groups[0];
        RestContext.response=new RestResponse();VkfAccountsResource.get();Assert.areEqual(200,RestContext.response.statusCode);
        RestContext.request.requestURI='/services/apexrest/vkf/v1/accounts/credit-groups/'+g.id+'/archive';
        RestContext.request.requestBody=Blob.valueOf(JSON.serialize(new Map<String,Object>{'expectedVersion'=>g.version}));
        RestContext.response=new RestResponse();VkfAccountsResource.post();Assert.areEqual(200,RestContext.response.statusCode);
        RestContext.request=new RestRequest();RestContext.request.requestURI='/services/apexrest/vkf/v1/accounts/credit-groups';RestContext.response=new RestResponse();
        VkfAccountsResource.get();Assert.areEqual(401,RestContext.response.statusCode);Test.stopTest();
    }
    @IsTest static void archivePreservesSharedAndIndependentLimits() {
        Fixture f=new Fixture(); CreditLimitGroupService.GroupView groupRow=f.create();
        Test.startTest();
        ArchiveService.Collected archived=ArchiveService.collect(f.admin.familyId,Date.today());
        Boolean hasGroup=false;Boolean hasCard=false;
        for(Archive_Record__b row:archived.rows) {
            if(row.Record_Type__c=='CreditLimitGroup' && row.Record_Id__c==String.valueOf(groupRow.id)) hasGroup=true;
            if(row.Record_Type__c==ArchiveService.ACCOUNT && row.Record_Id__c==String.valueOf(f.first)) {
                Map<String,Object> payload=(Map<String,Object>)JSON.deserializeUntyped(row.Payload__c);
                Assert.areEqual(300000,payload.get('creditLimit'));Assert.areEqual(50000,payload.get('independentCreditLimit'));
                Assert.areEqual(String.valueOf(groupRow.id),payload.get('creditLimitGroupId'));hasCard=true;
            }
        }
        Assert.isTrue(hasGroup);Assert.isTrue(hasCard);Test.stopTest();
    }
    @IsTest static void overviewUsesBoundedQueriesAndExactCurrencyForManyCards() {
        VkfTestData.fastPolicy();UserContext admin=VkfTestData.ctx('admina');
        List<Financial_Account__c> cards=new List<Financial_Account__c>();
        for(Integer n=0;n<20;n++) cards.add(new Financial_Account__c(Name='Scale card '+n,Family__c=admin.familyId,Owner_Member__c=admin.userId,
            Type__c='Credit Card',Status__c='Active',Credit_Limit__c=50000,Opening_Balance__c=3000.01,Current_Balance__c=3000.01));
        insert as system cards;List<Object> ids=new List<Object>();for(Financial_Account__c card:cards)ids.add(card.Id);
        CreditLimitGroupService.save(admin,null,new Map<String,Object>{'name'=>'Many cards','creditLimit'=>300000,'cardIds'=>ids},false);
        Test.startTest();Integer beforeQueries=Limits.getQueries();
        CreditLimitGroupService.Overview view=CreditLimitGroupService.overview(admin);
        Assert.isTrue(Limits.getQueries()-beforeQueries<=5,'Queries must be bounded, not one per card.');
        Assert.areEqual(60000.20,view.groups[0].outstanding);Assert.areEqual(239999.80,view.totals.available);
        Assert.areEqual(300000,view.totals.creditLimit);Test.stopTest();
    }
    @IsTest static void directGroupEditsPreserveInvariantsAndInvalidateStaleEditors() {
        Fixture f=new Fixture();CreditLimitGroupService.GroupView groupRow=f.create();
        Test.startTest();
        try { update as system new Credit_Limit_Group__c(Id=groupRow.id,Active__c=false); Assert.fail('linked facilities cannot be archived directly'); }
        catch(DmlException e) { Assert.isTrue(e.getMessage().contains('Unlink all cards')); }
        Decimal prior=CreditLimitGroupService.overview(f.admin).groups[0].version;
        update as system new Financial_Account__c(Id=f.second,Credit_Limit_Group__c=null);
        Decimal after=CreditLimitGroupService.overview(f.admin).groups[0].version;
        Assert.isTrue(after>prior,'direct membership changes must invalidate an open editor');
        try { CreditLimitGroupService.save(f.admin,groupRow.id,f.input(prior),false);Assert.fail('cannot overwrite a direct membership change'); }
        catch(PortalException e) { Assert.areEqual('CONFLICT',e.code()); }
        Test.stopTest();
    }
    @IsTest static void independentCardsRetainTheirOwnCreditBalances() {
        Fixture f=new Fixture();Test.startTest();
        AccountService.reconcile(f.admin,f.first,new Map<String,Object>{'actualBalance'=>-5000,'date'=>String.valueOf(Date.today())});
        CreditLimitGroupService.Overview view=CreditLimitGroupService.overview(f.admin);
        Assert.areEqual(100000,view.totals.creditLimit);Assert.areEqual(85000,view.totals.available);
        Test.stopTest();
    }
}