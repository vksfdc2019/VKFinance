/**
 * Copies Audit_Event__e into the Audit_Log__b big object, which doesn't count
 * against the org's 5 MB data storage.
 */
public without sharing class AuditLogWriter {
    @TestVisible
    private static List<Audit_Log__b> lastWritten = new List<Audit_Log__b>();

    public static void write(List<Audit_Event__e> events) {
        List<Audit_Log__b> rows = new List<Audit_Log__b>();
        for (Audit_Event__e e : events) {
            rows.add(
                new Audit_Log__b(
                    Family_Id__c = String.isBlank(e.Family_Id__c) ? 'PLATFORM' : e.Family_Id__c,
                    Event_Time__c = e.Occurred_At__c == null ? Datetime.now() : e.Occurred_At__c,
                    Event_Key__c = String.isBlank(e.EventUuid) ? UUID.randomUUID().toString() : e.EventUuid,
                    Actor_Id__c = e.Actor_Id__c,
                    Event_Type__c = e.Event_Type__c,
                    Object_Name__c = e.Object_Name__c,
                    Record_Id__c = e.Record_Id__c,
                    Details__c = e.Details__c
                )
            );
        }
        lastWritten = rows;
        // Big objects can't be written inside Apex tests.
        if (!rows.isEmpty() && !Test.isRunningTest()) {
            Database.insertImmediate(rows);
        }
    }
}