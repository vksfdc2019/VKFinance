trigger AuditEventTrigger on Audit_Event__e(after insert) {
    AuditLogWriter.write(Trigger.new);
}
