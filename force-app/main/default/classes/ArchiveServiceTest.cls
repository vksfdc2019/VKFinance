@IsTest
private class ArchiveServiceTest {
    /** Fake Google: a folder, one spreadsheet, and honest row counts. Status 401 when failing. */
    private class GoogleMock implements HttpCalloutMock {
        final Boolean failing;
        Integer calls = 0;
        GoogleMock(Boolean failing) {
            this.failing = failing;
        }
        public HttpResponse respond(HttpRequest req) {
            calls++;
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (failing) {
                res.setStatusCode(401);
                res.setBody('{"error":"invalid_grant"}');
                return res;
            }
            res.setStatusCode(200);
            String url = req.getEndpoint();
            String body = req.getBody();
            if (url.contains('/drive/v3/files?fields=files')) {
                res.setBody('{"files":[]}');
            } else if (url.contains('/drive/v3/files')) {
                res.setBody(body.contains('spreadsheet') ? '{"id":"sheet-1"}' : '{"id":"folder-1"}');
            } else if (url.contains('/values:batchUpdate')) {
                Integer rows = 0;
                for (Object d : (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(body)).get('data')) {
                    rows += ((List<Object>) ((Map<String, Object>) d).get('values')).size();
                }
                res.setBody('{"totalUpdatedRows":' + rows + '}');
            } else if (req.getMethod() == 'GET') {
                res.setBody('{"sheets":[{"properties":{"sheetId":0,"title":"Sheet1"}}]}');
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    private static Date oldDate() {
        return ArchiveService.cutoff(Date.today()).addMonths(-1).addDays(4);
    }

    private static String oldMonth() {
        return ArchiveService.monthKey(oldDate());
    }

    private static Archive_Log__c ageLog(Id familyId) {
        Archive_Log__c log = [SELECT Id FROM Archive_Log__c WHERE Family__c = :familyId WITH SYSTEM_MODE LIMIT 1];
        Datetime past = Datetime.now().addDays(-(ArchiveService.graceDays() + 1));
        log.Copied_At__c = past;
        log.Exported_At__c = past;
        update as system log;
        return log;
    }

    @IsTest
    static void oldEntriesAreArchivedExportedAndRemovedWithoutMovingBalances() {
        UserContext admin = VkfTestData.ctx('admina');
        Id account = LedgerTestData.account(admin, 'Bank', 'Savings', 10000).id;
        Id groceries = LedgerTestData.categoryId(admin, 'Groceries');
        LedgerTestData.entry(admin, 'Expense', 500, account, groceries, oldDate(), 'Old shop');
        LedgerTestData.entry(admin, 'Income', 2000, account, LedgerTestData.categoryId(admin, 'Salary'), oldDate().addDays(1), 'Salary');
        LedgerTestData.entry(admin, 'Expense', 100, account, groceries);
        Assert.areEqual(11400, LedgerTestData.balance(account));

        ArchiveService.Collected c = ArchiveService.collect(admin.familyId, Date.today());
        Integer txns = 0;
        for (Archive_Record__b r : c.rows) {
            if (r.Record_Type__c == ArchiveService.TXN) {
                txns++;
                Assert.areEqual(oldMonth(), r.Archive_Month__c);
            }
            if (r.Record_Type__c == ArchiveService.MEMBER) {
                Assert.isFalse(r.Payload__c.containsIgnoreCase('hash'), 'Secrets must never be archived.');
                Assert.isFalse(r.Payload__c.containsIgnoreCase('salt'));
            }
        }
        Assert.areEqual(2, txns, 'Only entries older than the live window are archived.');
        Assert.isTrue(c.touched.contains(oldMonth()));
        ArchiveStore.save(c.rows);
        ArchiveService.Collected again = ArchiveService.collect(admin.familyId, Date.today());
        Assert.areEqual(0, again.rows.size(), 'Unchanged records are not copied twice.');
        Assert.isTrue(again.touched.contains(oldMonth()), 'A copied month without a log still gets its sheet.');

        GoogleMock google = new GoogleMock(false);
        Test.setMock(HttpCalloutMock.class, google);
        Test.startTest();
        ArchiveExporter.export(admin.familyId, new List<String>(c.touched), c.touched);
        Archive_Log__c log = [SELECT Status__c, Sheet_Id__c, Exported_At__c, Records__c, Error__c FROM Archive_Log__c WHERE Family__c = :admin.familyId WITH SYSTEM_MODE];
        Assert.areEqual('Copied', log.Status__c);
        Assert.areEqual('sheet-1', log.Sheet_Id__c, 'Error: ' + log.Error__c);
        Assert.isNotNull(log.Exported_At__c);
        Assert.isTrue(google.calls > 0);
        Date through = [SELECT Archived_Through__c FROM Family__c WHERE Id = :admin.familyId WITH SYSTEM_MODE].Archived_Through__c;
        Assert.areEqual(LedgerUtil.monthEnd(oldDate().toStartOfMonth()), through);

        try {
            LedgerTestData.entry(admin, 'Expense', 10, account, groceries, oldDate(), 'Late');
            Assert.fail('Archived months are closed.');
        } catch (DmlException e) {
            Assert.isTrue(e.getDmlMessage(0).contains('archived'), e.getDmlMessage(0));
        }
        RestResponse res = VkfTestData.call('POST', '/services/apexrest/vkf/v1/transactions', JSON.serialize(new Map<String, Object>{
            'type' => 'Expense', 'amount' => 10, 'accountId' => account, 'categoryId' => groceries, 'date' => String.valueOf(oldDate())
        }), VkfTestData.login('admina'));
        VkfTransactionsResource.post();
        Assert.areEqual(400, res.statusCode);
        Assert.areEqual('VALIDATION', VkfTestData.code(res));

        Assert.isTrue(ArchiveService.purgeable(admin.familyId, Date.today(), 5).isEmpty(), 'Nothing is removed during the grace period.');
        Archive_Log__c aged = ageLog(admin.familyId);
        List<Archive_Log__c> due = ArchiveService.purgeable(admin.familyId, Date.today(), 5);
        Assert.areEqual(1, due.size());
        ArchiveService.PurgeResult r = ArchiveService.purgeMonth(due[0]);
        Test.stopTest();

        Assert.areEqual(2, r.removed);
        Assert.areEqual(0, r.kept);
        Date cut = ArchiveService.cutoff(Date.today());
        Assert.areEqual(0, [SELECT COUNT() FROM Transaction__c WHERE Family__c = :admin.familyId AND Txn_Date__c < :cut WITH SYSTEM_MODE]);
        Assert.areEqual(11400, LedgerTestData.balance(account), 'Removing archived entries never moves a balance.');
        Assert.areEqual(1500, [SELECT Archived_Net__c FROM Financial_Account__c WHERE Id = :account WITH SYSTEM_MODE].Archived_Net__c);
        Assert.areEqual(0, BalanceReconcileJob.reconcileFamily(admin.familyId), 'The nightly check counts archived entries.');
        Monthly_Summary__c summary = [
            SELECT Income__c, Expense__c FROM Monthly_Summary__c
            WHERE Family__c = :admin.familyId AND Member__c = NULL AND Month__c = :oldDate().toStartOfMonth() WITH SYSTEM_MODE
        ];
        Assert.areEqual(2000, summary.Income__c);
        Assert.areEqual(500, summary.Expense__c);
        Assert.areEqual(aged.Id, due[0].Id);
    }

    @IsTest
    static void entriesWithReceiptsOrLaterChangesStayLive() {
        ArchiveService.policy = new Archive_Policy__mdt(Live_Months__c = 3, Grace_Days__c = 7, Google_Copy__c = false);
        UserContext admin = VkfTestData.ctx('admina');
        Id account = LedgerTestData.account(admin, 'Bank', 'Savings', 1000).id;
        Id groceries = LedgerTestData.categoryId(admin, 'Groceries');
        Id withReceipt = LedgerTestData.entry(admin, 'Expense', 40, account, groceries, oldDate(), 'Receipt shop').id;
        Id plain = LedgerTestData.entry(admin, 'Expense', 60, account, groceries, oldDate(), 'Plain shop').id;
        insert as system new Transaction_Receipt__c(Family__c = admin.familyId, Member__c = admin.userId, Transaction__c = withReceipt);

        ArchiveService.Collected c = ArchiveService.collect(admin.familyId, Date.today());
        ArchiveStore.save(c.rows);
        Test.startTest();
        ArchiveExporter.export(admin.familyId, new List<String>(c.touched), c.touched);
        ageLog(admin.familyId);
        ArchiveService.PurgeResult r = ArchiveService.purgeMonth(ArchiveService.purgeable(admin.familyId, Date.today(), 5)[0]);
        Test.stopTest();

        Assert.areEqual(1, r.removed);
        Assert.areEqual(1, r.kept);
        Assert.areEqual(1, [SELECT COUNT() FROM Transaction__c WHERE Id = :withReceipt WITH SYSTEM_MODE], 'Receipt photos keep their entry live.');
        Assert.areEqual(0, [SELECT COUNT() FROM Transaction__c WHERE Id = :plain WITH SYSTEM_MODE]);
        Assert.areEqual(900, LedgerTestData.balance(account));
        Assert.areEqual(0, BalanceReconcileJob.reconcileFamily(admin.familyId));
    }

    @IsTest
    static void aFailedGoogleCopyBlocksRemoval() {
        UserContext admin = VkfTestData.ctx('admina');
        Id account = LedgerTestData.account(admin, 'Bank', 'Savings', 1000).id;
        LedgerTestData.entry(admin, 'Expense', 60, account, LedgerTestData.categoryId(admin, 'Groceries'), oldDate(), 'Shop');
        ArchiveService.Collected c = ArchiveService.collect(admin.familyId, Date.today());
        ArchiveStore.save(c.rows);
        Test.setMock(HttpCalloutMock.class, new GoogleMock(true));
        Test.startTest();
        ArchiveExporter.export(admin.familyId, new List<String>(c.touched), c.touched);
        Test.stopTest();

        Archive_Log__c log = [SELECT Exported_At__c, Error__c FROM Archive_Log__c WHERE Family__c = :admin.familyId WITH SYSTEM_MODE];
        Assert.isNull(log.Exported_At__c);
        Assert.isTrue(log.Error__c != null && log.Error__c.contains('401'), 'Error: ' + log.Error__c);
        log.Copied_At__c = Datetime.now().addDays(-30);
        update as system log;
        Assert.isTrue(ArchiveService.purgeable(admin.familyId, Date.today(), 5).isEmpty(), 'No removal until Google has the copy.');
        Assert.isTrue(ArchiveExporter.pendingExport(admin.familyId).contains(oldMonth()), 'The next run retries the copy.');
    }

    @IsTest
    static void archivedMonthsFollowTheSameVisibilityRules() {
        ArchiveService.policy = new Archive_Policy__mdt(Live_Months__c = 3, Grace_Days__c = 7, Google_Copy__c = false);
        UserContext admin = VkfTestData.ctx('admina');
        UserContext member = VkfTestData.ctx('membera');
        Id adminAccount = LedgerTestData.account(admin, 'Admin bank', 'Savings', 1000).id;
        Id memberAccount = LedgerTestData.account(member, 'Member wallet', 'Cash', 500).id;
        Id groceries = LedgerTestData.categoryId(admin, 'Groceries');
        LedgerTestData.entry(admin, 'Expense', 70, adminAccount, groceries, oldDate(), 'Admin shop');
        LedgerTestData.entry(member, 'Expense', 30, memberAccount, groceries, oldDate(), 'Member shop');
        ArchiveService.Collected c = ArchiveService.collect(admin.familyId, Date.today());
        ArchiveStore.save(c.rows);
        ArchiveExporter.export(admin.familyId, new List<String>(c.touched), c.touched);

        Test.startTest();
        ArchiveViewService.Summary s = ArchiveViewService.summary(admin);
        Assert.areEqual(1, s.months.size());
        Assert.areEqual(oldMonth(), s.months[0].month);
        ArchiveViewService.MonthView all = ArchiveViewService.month(admin, oldMonth());
        Assert.areEqual(2, all.entries.size());
        Assert.areEqual(100, all.spending);
        ArchiveViewService.MonthView own = ArchiveViewService.month(member, oldMonth());
        Assert.areEqual(1, own.entries.size());
        Assert.areEqual('Member shop', own.entries[0].payee);
        Assert.areEqual(0, ArchiveViewService.month(VkfTestData.ctx('childa'), oldMonth()).entries.size());
        UserContext other = VkfTestData.ctx('adminb');
        Assert.areEqual(0, ArchiveViewService.summary(other).months.size());
        Assert.areEqual(0, ArchiveViewService.month(other, oldMonth()).entries.size(), 'Another family never sees these.');

        String token = VkfTestData.login('admina');
        RestResponse ok = VkfTestData.call('GET', '/services/apexrest/vkf/v1/archive/' + oldMonth(), null, token);
        VkfArchiveResource.get();
        Assert.areEqual(200, ok.statusCode);
        Assert.areEqual(2, ((List<Object>) VkfTestData.json(ok).get('entries')).size());
        RestResponse bad = VkfTestData.call('GET', '/services/apexrest/vkf/v1/archive/July', null, token);
        VkfArchiveResource.get();
        Assert.areEqual('VALIDATION', VkfTestData.code(bad));
        RestResponse anonymous = VkfTestData.call('GET', '/services/apexrest/vkf/v1/archive', null, null);
        VkfArchiveResource.get();
        Assert.areEqual(401, anonymous.statusCode);
        Test.stopTest();
    }

    @IsTest
    static void endedSessionsAreCopiedButActiveOnesAreNot() {
        UserContext admin = VkfTestData.ctx('admina');
        VkfTestData.ctx('admina');
        List<Portal_Session__c> sessions = [SELECT Id FROM Portal_Session__c WHERE Family__c = :admin.familyId WITH SYSTEM_MODE];
        sessions[0].Status__c = 'Logged Out';
        sessions[0].Ended_At__c = Datetime.now();
        update as system sessions[0];
        Integer ended = [SELECT COUNT() FROM Portal_Session__c WHERE Family__c = :admin.familyId AND Status__c != 'Active' WITH SYSTEM_MODE];
        Integer copied = 0;
        for (Archive_Record__b r : ArchiveService.collect(admin.familyId, Date.today()).rows) {
            if (r.Record_Type__c == ArchiveService.SESSION) {
                copied++;
                Assert.isFalse(r.Payload__c.containsIgnoreCase('token'), 'Session tokens are never archived.');
            }
        }
        Assert.isTrue(ended >= 1);
        Assert.areEqual(ended, copied, 'Every ended session is copied; active ones are not.');
    }

    @IsTest
    static void theDailyJobRunsEachStep() {
        ArchiveService.policy = new Archive_Policy__mdt(Live_Months__c = 3, Grace_Days__c = 7, Google_Copy__c = false);
        UserContext admin = VkfTestData.ctx('admina');
        Id account = LedgerTestData.account(admin, 'Bank', 'Savings', 1000).id;
        LedgerTestData.entry(admin, 'Expense', 60, account, LedgerTestData.categoryId(admin, 'Groceries'), oldDate(), 'Shop');
        List<Family__c> families = [SELECT Id FROM Family__c WHERE Id = :admin.familyId WITH SYSTEM_MODE];
        Test.startTest();
        new ArchiveWorker(ArchiveWorker.Step.COPY_RECORDS, null).execute(null, families);
        new ArchiveWorker(ArchiveWorker.Step.WRITE_SHEETS, new Map<Id, Set<String>>{ admin.familyId => new Set<String>{ oldMonth() } })
            .execute(null, families);
        ageLog(admin.familyId);
        ArchiveWorker remover = new ArchiveWorker(ArchiveWorker.Step.REMOVE_ARCHIVED, null);
        List<SObject> due = new List<SObject>();
        Database.QueryLocatorIterator it = remover.start(null).iterator();
        while (it.hasNext()) {
            due.add(it.next());
        }
        Assert.areEqual(1, due.size(), 'The remove pass finds the aged month.');
        remover.execute(null, due);
        remover.finish(null);
        Test.stopTest();
        Archive_Log__c log = [SELECT Status__c, Purged__c FROM Archive_Log__c WHERE Family__c = :admin.familyId WITH SYSTEM_MODE];
        Assert.areEqual('Purged', log.Status__c);
        Assert.areEqual(1, log.Purged__c);
        Assert.areEqual(940, LedgerTestData.balance(account));
    }

    @IsTest
    static void scheduleQueuesTheFirstFamily() {
        Test.startTest();
        new ArchiveJob().execute((SchedulableContext) null);
        Test.stopTest();
        Assert.isTrue([SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'ArchiveWorker'] > 0);
    }

    @IsTest
    static void reportsMentionArchivedMonths() {
        UserContext admin = VkfTestData.ctx('admina');
        update as system new Family__c(Id = admin.familyId, Archived_Through__c = oldDate());
        ReportService.Report r = ReportService.run(admin, 'summary', LedgerTestData.params('from=' + String.valueOf(oldDate().addDays(-3)) + '&to=' + String.valueOf(Date.today())));
        Assert.isTrue(r.note != null && r.note.contains('archived'), 'Note: ' + r.note);
    }
}
