@IsTest
private class Phase6ImportTest {
    @TestSetup static void setup() {
        VkfTestData.twoFamilies();
        List<Family__c> families=[SELECT Id FROM Family__c WITH SYSTEM_MODE];
        for(Family__c f:families) f.Enhancements__c='IMPORTS';
        update as system families;
    }

    private static Map<String,Object> row(Id category) {
        return new Map<String,Object>{ 'type'=>'Expense','date'=>String.valueOf(Date.today()),'amount'=>125,'categoryId'=>category,'payee'=>'Grocer','referenceNo'=>'BANK-001' };
    }

    @IsTest static void reviewedImportPostsOnceAndKeepsItsSource() {
        VkfTestData.fastPolicy();
        UserContext admin=VkfTestData.ctx('admina');
        Id account=LedgerTestData.account(admin,'Bank','Savings',1000).id;
        Map<String,Object> entry=row(LedgerTestData.categoryId(admin,'Groceries'));
        Id batch=(Id) StatementImportService.stage(admin,new Map<String,Object>{ 'accountId'=>account,'fileName'=>'bank.csv','rows'=>new List<Object>{entry,entry} }).get('id');
        Assert.areEqual(1000,LedgerTestData.balance(account));
        try { StatementImportService.detail(VkfTestData.ctx('adminb'),batch); Assert.fail(); }
        catch(PortalException e) { Assert.areEqual('NOT_FOUND',e.code()); }
        Test.startTest();
        StatementImportService.startImport(admin,batch,false);
        Test.stopTest();
        Assert.areEqual(875,LedgerTestData.balance(account));
        Statement_Import__c imported=[SELECT Status__c, Imported__c, Duplicates__c FROM Statement_Import__c WHERE Id=:batch WITH SYSTEM_MODE];
        Assert.areEqual('Completed',imported.Status__c);
        Assert.areEqual(1,imported.Imported__c); Assert.areEqual(1,imported.Duplicates__c);
        Assert.areEqual('Import',[SELECT Source__c FROM Transaction__c WHERE Account__c=:account WITH SYSTEM_MODE LIMIT 1].Source__c);
        StatementImportService.startImport(admin,batch,false);
        Assert.areEqual(875,LedgerTestData.balance(account));
    }

    @IsTest static void transferRowsAreRejectedAndDraftCanBeCancelled() {
        VkfTestData.fastPolicy(); UserContext admin=VkfTestData.ctx('admina');
        Id account=LedgerTestData.account(admin,'Bank','Savings',1000).id;
        Map<String,Object> entry=row(LedgerTestData.categoryId(admin,'Groceries'));
        entry.put('type','Transfer');
        Savepoint sp=Database.setSavepoint();
        try { StatementImportService.stage(admin,new Map<String,Object>{'accountId'=>account,'fileName'=>'bank.csv','rows'=>new List<Object>{entry}}); Assert.fail(); }
        catch(PortalException e) { Assert.areEqual('VALIDATION',e.code()); }
        Database.rollback(sp);
        entry.put('type','Expense');
        Id batch=(Id) StatementImportService.stage(admin,new Map<String,Object>{'accountId'=>account,'fileName'=>'bank.csv','rows'=>new List<Object>{entry}}).get('id');
        Assert.areEqual('Cancelled',StatementImportService.startImport(admin,batch,true).get('status'));
        try { StatementImportService.startImport(admin,batch,false); Assert.fail(); } catch(PortalException e) { Assert.areEqual('CONFLICT',e.code()); }
        Assert.areEqual(1000,LedgerTestData.balance(account));
    }

    @IsTest static void permissionChangeBeforeWorkerPreventsPosting() {
        VkfTestData.fastPolicy(); UserContext admin=VkfTestData.ctx('admina');
        Id account=LedgerTestData.account(admin,'Bank','Savings',1000).id;
        Id batch=(Id) StatementImportService.stage(admin,new Map<String,Object>{'accountId'=>account,'fileName'=>'bank.csv',
            'rows'=>new List<Object>{row(LedgerTestData.categoryId(admin,'Groceries'))}}).get('id');
        Test.startTest();
        StatementImportService.startImport(admin,batch,false);
        update as system new Portal_User__c(Id=admin.userId,Role__c='Viewer');
        Test.stopTest();
        Assert.areEqual(1000,LedgerTestData.balance(account));
        Assert.areEqual('Partial',[SELECT Status__c FROM Statement_Import__c WHERE Id=:batch WITH SYSTEM_MODE].Status__c);
    }

    @IsTest static void maintenanceArchivesStagingWithoutDeletingFinancialHistory() {
        VkfTestData.fastPolicy(); UserContext admin=VkfTestData.ctx('admina');
        Id account=LedgerTestData.account(admin,'Bank','Savings',1000).id;
        Id txn=LedgerTestData.entry(admin,'Expense',25,account,LedgerTestData.categoryId(admin,'Groceries')).id;
        Id batch=(Id) StatementImportService.stage(admin,new Map<String,Object>{'accountId'=>account,'fileName'=>'old.csv',
            'rows'=>new List<Object>{row(LedgerTestData.categoryId(admin,'Groceries'))}}).get('id');
        Test.setCreatedDate(batch,Datetime.now().addDays(-35));
        insert as system new Insight_Preference__c(Family__c=admin.familyId,Member__c=admin.userId,Insight_Key__c='old',Hidden_Until__c=Date.today().addDays(-40));
        Test.startTest();
        new EnhancementMaintenanceJob().execute((SchedulableContext)null);
        Test.stopTest();
        Assert.areEqual('Archived',[SELECT Status__c FROM Statement_Import__c WHERE Id=:batch WITH SYSTEM_MODE].Status__c);
        Assert.areEqual(0,[SELECT COUNT() FROM Statement_Row__c WHERE Import__c=:batch WITH SYSTEM_MODE]);
        Assert.areEqual(1,[SELECT COUNT() FROM Transaction__c WHERE Id=:txn WITH SYSTEM_MODE]);
        Assert.areEqual(975,LedgerTestData.balance(account));
        Assert.areEqual(0,[SELECT COUNT() FROM Insight_Preference__c WITH SYSTEM_MODE]);
    }

    @IsTest static void matchingManuallyRecordedBankReferenceIsNotPostedAgain() {
        VkfTestData.fastPolicy(); UserContext admin=VkfTestData.ctx('admina');
        Id account=LedgerTestData.account(admin,'Bank','Savings',1000).id;
        Map<String,Object> entry=row(LedgerTestData.categoryId(admin,'Groceries'));
        entry.put('accountId',account);
        TransactionService.createTransaction(admin,entry);
        Id batch=(Id) StatementImportService.stage(admin,new Map<String,Object>{'accountId'=>account,'fileName'=>'bank.csv','rows'=>new List<Object>{entry}}).get('id');
        Test.startTest(); StatementImportService.startImport(admin,batch,false); Test.stopTest();
        Assert.areEqual(875,LedgerTestData.balance(account));
        Assert.areEqual(1,[SELECT Duplicates__c FROM Statement_Import__c WHERE Id=:batch WITH SYSTEM_MODE].Duplicates__c);
    }
}