/**
 * The signed-in member's own security picture for the portal's Security page: two-step status,
 * password age, devices and their recent security events from the audit trail.
 */
public without sharing class AccountSecurityService {
    public static final Integer ACTIVITY_DAYS = 30;
    public static final Integer ACTIVITY_SIZE = 25;

    /** Events about the member's own account, whoever triggered them. */
    private static final Set<String> OWN_EVENTS = new Set<String>{
        'LOGIN_SUCCESS', 'LOGIN_FAILED', 'LOGIN_LOCKED', 'LOGIN_THROTTLED', 'ACCOUNT_LOCKED', 'PASSWORD_SET', 'PASSWORD_CHANGED',
        'PASSWORD_RESET', 'PASSWORD_CHANGE_FAILED', 'STEP_UP_FAILED', 'MFA_ENABLED', 'MFA_DISABLED', 'MFA_RECOVERY_CODE_USED',
        'MFA_RECOVERY_CODES_RENEWED', 'SIGN_OUT_EVERYWHERE', 'SESSION_REVOKED'
    };
    /** Admin actions on the member's account. */
    private static final Set<String> ADMIN_EVENTS = new Set<String>{
        'ADMIN_PASSWORD_RESET', 'ADMIN_MFA_RESET', 'MEMBER_UNLOCKED', 'MEMBER_SESSIONS_REVOKED'
    };

    public class Overview {
        public MfaService.Status mfa;
        public Datetime passwordChangedAt;
        public Datetime lastLogin;
        public Integer activeSessions;
        public List<Event> activity = new List<Event>();
    }

    public class Event {
        public Datetime at;
        public String type;
        public String details;
        public Boolean byAdmin;
    }

    public static Overview overview(UserContext ctx) {
        Portal_User__c me = [
            SELECT Password_Changed_At__c, Last_Login__c
            FROM Portal_User__c
            WHERE Id = :ctx.userId AND Family__c = :ctx.familyId
            WITH SYSTEM_MODE
        ];
        Overview o = new Overview();
        o.mfa = MfaService.status(ctx.userId);
        o.passwordChangedAt = me.Password_Changed_At__c;
        o.lastLogin = me.Last_Login__c;
        o.activeSessions = SessionService.activeForUser(ctx.userId).size();
        o.activity = activity(ctx);
        return o;
    }

    private static List<Event> activity(UserContext ctx) {
        List<Event> events = new List<Event>();
        String me = String.valueOf(ctx.userId);
        try {
            // Index order (family, time desc) returns newest first.
            for (SObject row : Database.queryWithBinds(
                'SELECT Event_Time__c, Event_Type__c, Actor_Id__c, Record_Id__c, Details__c FROM Audit_Log__b ' +
                'WHERE Family_Id__c = :fid AND Event_Time__c >= :since LIMIT 2000',
                new Map<String, Object>{ 'fid' => String.valueOf(ctx.familyId), 'since' => Datetime.now().addDays(-ACTIVITY_DAYS) },
                AccessLevel.SYSTEM_MODE
            )) {
                String type = (String) row.get('Event_Type__c');
                String actor = (String) row.get('Actor_Id__c');
                String target = (String) row.get('Record_Id__c');
                Boolean mine = OWN_EVENTS.contains(type) && sameId(actor, me);
                Boolean byAdmin = ADMIN_EVENTS.contains(type) && sameId(target, me);
                if (!mine && !byAdmin) {
                    continue;
                }
                Event e = new Event();
                e.at = (Datetime) row.get('Event_Time__c');
                e.type = type;
                e.details = friendlyDetails(type, (String) row.get('Details__c'));
                e.byAdmin = byAdmin;
                events.add(e);
                if (events.size() == ACTIVITY_SIZE) {
                    break;
                }
            }
        } catch (Exception ex) {
            // The audit store can be unavailable (e.g. in tests); the page still shows everything else.
            System.debug(LoggingLevel.WARN, 'Security activity unavailable: ' + ex.getMessage());
        }
        return events;
    }

    /** Ids are stored as text, sometimes 15 and sometimes 18 characters. */
    private static Boolean sameId(String stored, String userId) {
        return String.isNotBlank(stored) && userId.startsWith(stored.left(15));
    }

    private static String friendlyDetails(String type, String details) {
        if (type == 'LOGIN_SUCCESS') {
            // Stored as "<scope>[, <method>]".
            return details != null && details.contains(', ') ? 'With ' + details.substringAfter(', ') : 'With password';
        }
        return details;
    }
}
