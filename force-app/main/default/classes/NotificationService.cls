/**
 * In-app notifications (the bell). Automation passes a dedupe key, so re-running the daily
 * job never repeats an alert; each person only ever reads their own notifications.
 */
public without sharing class NotificationService {
    public static final Integer FEED_SIZE = 30;
    public static final Integer RETENTION_DAYS = 60;

    public class Message {
        public String type;
        public String severity = 'info';
        public String title;
        public String text;
        public String link;
        public String dedupeKey;

        public Message(String type, String severity, String title, String text, String link, String dedupeKey) {
            this.type = type;
            this.severity = severity;
            this.title = title == null ? null : title.left(120);
            this.text = text == null ? null : text.left(255);
            this.link = link;
            this.dedupeKey = dedupeKey;
        }
    }

    /** Creates one notification per recipient, skipping any whose dedupe key already exists. */
    public static Integer notify(Id familyId, Set<Id> recipients, Message m) {
        recipients.remove(null);
        if (recipients.isEmpty()) {
            return 0;
        }
        Map<String, Notification__c> byKey = new Map<String, Notification__c>();
        List<Notification__c> plain = new List<Notification__c>();
        for (Id recipient : recipients) {
            Notification__c n = new Notification__c(
                Family__c = familyId,
                Recipient__c = recipient,
                Type__c = m.type,
                Severity__c = m.severity,
                Title__c = m.title,
                Message__c = m.text,
                Link__c = m.link,
                Is_Read__c = false
            );
            if (m.dedupeKey == null) {
                plain.add(n);
            } else {
                n.Dedupe_Key__c = (familyId + ':' + m.dedupeKey + ':' + recipient).left(120);
                byKey.put(n.Dedupe_Key__c, n);
            }
        }
        if (!byKey.isEmpty()) {
            Set<String> keys = byKey.keySet();
            for (Notification__c existing : [SELECT Dedupe_Key__c FROM Notification__c WHERE Dedupe_Key__c IN :keys WITH SYSTEM_MODE]) {
                byKey.remove(existing.Dedupe_Key__c);
            }
            plain.addAll(byKey.values());
        }
        insert as system plain;
        return plain.size();
    }

    public static CommitmentDtos.NotificationFeed feed(UserContext ctx) {
        AccessGuard.require(ctx, 'NOTIFICATIONS', 'READ');
        CommitmentSelector selector = new CommitmentSelector(ctx);
        CommitmentDtos.NotificationFeed feed = new CommitmentDtos.NotificationFeed();
        for (Notification__c n : selector.notifications(ctx.userId, FEED_SIZE)) {
            CommitmentDtos.Notification d = new CommitmentDtos.Notification();
            d.id = n.Id;
            d.type = n.Type__c;
            d.severity = n.Severity__c;
            d.title = n.Title__c;
            d.message = n.Message__c;
            d.link = n.Link__c;
            d.read = n.Is_Read__c;
            d.createdAt = n.CreatedDate;
            feed.items.add(d);
        }
        feed.unread = selector.unreadCount(ctx.userId);
        return feed;
    }

    /** Marks the caller's own notifications read - all of them when ids is empty. */
    public static Integer markRead(UserContext ctx, List<Id> ids) {
        AccessGuard.require(ctx, 'NOTIFICATIONS', 'READ');
        Id fid = ctx.familyId;
        Id me = ctx.userId;
        List<Notification__c> rows = ids == null || ids.isEmpty()
            ? [SELECT Id FROM Notification__c WHERE Family__c = :fid AND Recipient__c = :me AND Is_Read__c = FALSE WITH SYSTEM_MODE LIMIT 2000]
            : [SELECT Id FROM Notification__c WHERE Family__c = :fid AND Recipient__c = :me AND Id IN :ids WITH SYSTEM_MODE];
        for (Notification__c n : rows) {
            n.Is_Read__c = true;
        }
        update as system rows;
        return rows.size();
    }

    /** Deletes read notifications older than the retention window, keeping storage in check. */
    public static Integer purge() {
        Datetime cutoff = Datetime.now().addDays(-RETENTION_DAYS);
        List<Notification__c> old = [SELECT Id FROM Notification__c WHERE Is_Read__c = TRUE AND CreatedDate < :cutoff WITH SYSTEM_MODE LIMIT 9000];
        delete as system old;
        return old.size();
    }
}
