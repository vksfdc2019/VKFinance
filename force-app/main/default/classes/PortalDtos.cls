/**
 * Shapes returned to the portal. Only whitelisted fields leave the server - never
 * hashes, salts, tokens or counters.
 */
public inherited sharing class PortalDtos {
    public class Profile {
        public Id userId;
        public String firstName;
        public String lastName;
        public String username;
        public String email;
        public String mobile;
        public String relationship;
        public String role;
        public String status;
        public Id familyId;
        public String familyName;
        public String familyCode;
        public String currencyCode;
        public Boolean mustChangePassword;
        public Boolean mfaEnabled;
        public String sessionScope;
        public Integer idleTimeoutMinutes;
        public List<String> permissions;
        public Appearance appearance;
    }

    /** The caller's saved theme, the family default, and whether the family has locked its colours. */
    public class Appearance {
        public Map<String, Object> personal;
        public Map<String, Object> family;
        public Boolean locked = false;
    }

    public class Member {
        public Id id;
        public String firstName;
        public String lastName;
        public String username;
        public String email;
        public String mobile;
        public String relationship;
        public String role;
        public String status;
        public String viewerScope;
        public Boolean locked;
        public Datetime lockedUntil;
        public Datetime lastLogin;
        public Boolean mustChangePassword;
        public Integer activeSessions;
        public Boolean isSelf;
        public Boolean mfaEnabled;
    }

    public class Session {
        public Id id;
        public Datetime startedAt;
        public Datetime lastActivity;
        public Datetime expiresAt;
        public String device;
        public Boolean current;
    }

    public static Profile profile(UserContext ctx) {
        Profile p = new Profile();
        p.userId = ctx.userId;
        p.firstName = ctx.firstName;
        p.lastName = ctx.lastName;
        p.username = ctx.username;
        p.email = ctx.email;
        p.mobile = ctx.mobile;
        p.relationship = ctx.relationship;
        p.role = ctx.role;
        p.status = ctx.status;
        p.familyId = ctx.familyId;
        p.familyName = ctx.familyName;
        p.familyCode = ctx.familyCode;
        p.currencyCode = ctx.currencyCode;
        p.mustChangePassword = ctx.mustChangePassword == true;
        p.mfaEnabled = ctx.mfaEnabled == true;
        p.sessionScope = ctx.scope;
        p.idleTimeoutMinutes = SecurityPolicy.idleMinutes();
        p.permissions = AccessGuard.permissionsFor(ctx.role);
        p.appearance = AppearanceService.forUser(ctx);
        return p;
    }

    public static Member member(Portal_User__c u, Integer activeSessions, Id selfId) {
        Member m = new Member();
        m.id = u.Id;
        m.firstName = u.First_Name__c;
        m.lastName = u.Last_Name__c;
        m.username = u.Username__c;
        m.email = u.Email__c;
        m.mobile = u.Mobile__c;
        m.relationship = u.Relationship__c;
        m.role = u.Role__c;
        m.status = u.Status__c;
        m.viewerScope = u.Viewer_Scope__c;
        m.locked = u.Locked_Until__c != null && u.Locked_Until__c > Datetime.now();
        m.lockedUntil = m.locked ? u.Locked_Until__c : null;
        m.lastLogin = u.Last_Login__c;
        m.mustChangePassword = u.Must_Change_Password__c == true;
        m.activeSessions = activeSessions == null ? 0 : activeSessions;
        m.isSelf = u.Id == selfId;
        m.mfaEnabled = u.getPopulatedFieldsAsMap().get('MFA_Method__c') == MfaService.METHOD_APP;
        return m;
    }

    public static Session session(Portal_Session__c s, Id currentSessionId) {
        Session dto = new Session();
        dto.id = s.Id;
        dto.startedAt = s.CreatedDate;
        dto.lastActivity = s.Last_Activity__c;
        dto.expiresAt = s.Expires_At__c;
        dto.device = describeDevice(s.User_Agent__c);
        dto.current = s.Id == currentSessionId;
        return dto;
    }

    @TestVisible
    public static String describeDevice(String userAgent) {
        if (String.isBlank(userAgent)) {
            return 'Unknown device';
        }
        String browser = userAgent.contains('Edg/')
            ? 'Edge'
            : userAgent.contains('Chrome/') ? 'Chrome' : userAgent.contains('Firefox/') ? 'Firefox' : userAgent.contains('Safari/') ? 'Safari' : 'Browser';
        String os = userAgent.contains('Windows')
            ? 'Windows'
            : userAgent.contains('Android') ? 'Android' : userAgent.contains('iPhone') || userAgent.contains('iPad') ? 'iOS' : userAgent.contains('Mac OS') ? 'macOS' : userAgent.contains('Linux') ? 'Linux' : 'Unknown OS';
        return browser + ' on ' + os;
    }
}
