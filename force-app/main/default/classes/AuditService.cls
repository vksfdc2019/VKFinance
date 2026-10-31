/**
 * Publishes Audit_Event__e (publish-immediately), so the event survives even when the
 * surrounding transaction rolls back - failed logins are still recorded.
 *
 * Deliberately on API 66.0: from 67.0 Apex runs in user mode by default, and the site
 * guest user can't be granted platform-event access, so EventBus.publish would be denied.
 * This class only publishes audit events, so the system-mode exception stays this narrow.
 */
public without sharing class AuditService {
    public static void log(UserContext ctx, String eventType, String objectName, Id recordId, String details) {
        log(ctx?.familyId, ctx?.userId, eventType, objectName, recordId, details);
    }

    public static void log(Id familyId, Id actorId, String eventType, String objectName, Id recordId, String details) {
        Database.SaveResult result = EventBus.publish(
            new Audit_Event__e(
                Family_Id__c = familyId,
                Actor_Id__c = actorId,
                Event_Type__c = eventType,
                Object_Name__c = objectName,
                Record_Id__c = recordId,
                Details__c = details == null ? null : details.left(32000),
                Occurred_At__c = Datetime.now()
            )
        );
        if (!result.isSuccess()) {
            System.debug(LoggingLevel.ERROR, 'Audit event not published: ' + result.getErrors());
        }
    }
}