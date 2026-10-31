/**
 * Sundays 04:00 ("VKF Retention Purge"): deletes what the app no longer needs, so the small
 * Developer Edition data storage lasts and old secrets don't linger - read notifications after
 * 60 days, spent one-time tokens, password history beyond the policy count, removed members'
 * password history, and finished rate-limit windows. Writes one audit event with the counts.
 */
public without sharing class RetentionPurgeJob implements Schedulable {
    public void execute(SchedulableContext sc) {
        run();
    }

    public static Map<String, Integer> run() {
        Map<String, Integer> counts = new Map<String, Integer>();
        Datetime dayAgo = Datetime.now().addDays(-1);

        counts.put('notifications', NotificationService.purge());

        List<Auth_Token__c> tokens = [
            SELECT Id
            FROM Auth_Token__c
            WHERE (Used_At__c != NULL AND Used_At__c < :dayAgo) OR (Expires_At__c != NULL AND Expires_At__c < :dayAgo)
            WITH SYSTEM_MODE LIMIT 5000
        ];
        delete as system tokens;
        counts.put('tokens', tokens.size());

        Map<Id, Password_History__c> history = new Map<Id, Password_History__c>(
            [SELECT Id FROM Password_History__c WHERE Portal_User__r.Status__c = 'Removed' WITH SYSTEM_MODE LIMIT 2000]
        );
        history.putAll(historyBeyondPolicy());
        delete as system history.values();
        counts.put('passwordHistory', history.size());

        List<Rate_Limit__c> windows = [SELECT Id FROM Rate_Limit__c WHERE Window_Start__c < :dayAgo WITH SYSTEM_MODE LIMIT 5000];
        delete as system windows;
        counts.put('rateLimits', windows.size());

        AuditService.log(null, null, 'RETENTION_PURGE', null, null, JSON.serialize(counts));
        return counts;
    }

    /** Older entries for members holding more than the policy keeps (password changes trim as they go; this catches policy changes). */
    private static List<Password_History__c> historyBeyondPolicy() {
        Integer keep = Math.max(SecurityPolicy.passwordHistoryCount(), 1);
        Set<Id> over = new Set<Id>();
        for (AggregateResult ar : [SELECT Portal_User__c member, COUNT(Id) total FROM Password_History__c WITH SYSTEM_MODE GROUP BY Portal_User__c]) {
            if ((Integer) ar.get('total') > keep) {
                over.add((Id) ar.get('member'));
            }
        }
        List<Password_History__c> extra = new List<Password_History__c>();
        if (over.isEmpty()) {
            return extra;
        }
        Map<Id, Integer> seen = new Map<Id, Integer>();
        for (Password_History__c h : [
            SELECT Id, Portal_User__c
            FROM Password_History__c
            WHERE Portal_User__c IN :over
            WITH SYSTEM_MODE ORDER BY Portal_User__c, CreatedDate DESC, Id DESC
        ]) {
            Integer position = (seen.containsKey(h.Portal_User__c) ? seen.get(h.Portal_User__c) : 0) + 1;
            seen.put(h.Portal_User__c, position);
            if (position > keep) {
                extra.add(h);
            }
        }
        return extra;
    }
}