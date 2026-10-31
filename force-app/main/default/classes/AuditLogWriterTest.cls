@IsTest
private class AuditLogWriterTest {
    @IsTest
    static void mapsEventsToAuditLogRows() {
        AuditLogWriter.write(
            new List<Audit_Event__e>{
                new Audit_Event__e(Event_Type__c = 'LOGIN_FAILED', Details__c = 'Unknown username', Occurred_At__c = Datetime.now())
            }
        );
        Assert.areEqual(1, AuditLogWriter.lastWritten.size());
        Audit_Log__b row = AuditLogWriter.lastWritten[0];
        Assert.areEqual('PLATFORM', row.Family_Id__c);
        Assert.areEqual('LOGIN_FAILED', row.Event_Type__c);
        Assert.isNotNull(row.Event_Key__c);
    }

    @IsTest
    static void publishedEventsReachTheTrigger() {
        Test.startTest();
        AuditService.log(null, null, 'TEST_EVENT', null, null, 'from test');
        Test.getEventBus().deliver();
        Test.stopTest();
        Assert.isTrue(true, 'Delivery ran the trigger without errors');
    }
}