/**
 * VK portal sessions. The browser holds a 256-bit random token; the database holds
 * only its SHA-256 hash. Every portal request goes through require().
 */
public without sharing class SessionService {
    public static final String SCOPE_FULL = 'FULL';
    public static final String SCOPE_CHANGE_PASSWORD = 'CHANGE_PASSWORD'; // NOPMD - a session scope name, not a credential

    /** Session whose activity time is saved when the response is written (see flushActivity). */
    private static Id activityPending;

    public class NewSession {
        public String token;
        public Portal_Session__c record;
    }

    public static NewSession create(Portal_User__c user, String scope, String userAgent) {
        String token = TokenService.newToken();
        Datetime now = Datetime.now();
        Portal_Session__c session = new Portal_Session__c(
            Portal_User__c = user.Id,
            Family__c = user.Family__c,
            Token_Hash__c = TokenService.hash(token),
            Status__c = 'Active',
            Scope__c = scope,
            Last_Activity__c = now,
            Expires_At__c = now.addHours(SecurityPolicy.absoluteHours()),
            User_Agent__c = userAgent == null ? null : userAgent.left(255),
            User_Agent_Hash__c = String.isBlank(userAgent) ? null : TokenService.hash(userAgent)
        );
        insert as system session;
        enforceSessionLimit(user.Id, session.Id);
        NewSession result = new NewSession();
        result.token = token;
        result.record = session;
        return result;
    }

    private static void enforceSessionLimit(Id userId, Id keepId) {
        Integer max = SecurityPolicy.maxSessions();
        List<Portal_Session__c> others = [
            SELECT Id
            FROM Portal_Session__c
            WHERE Portal_User__c = :userId AND Status__c = 'Active' AND Id != :keepId
            WITH SYSTEM_MODE ORDER BY Last_Activity__c DESC
        ];
        List<Portal_Session__c> toRevoke = new List<Portal_Session__c>();
        for (Integer i = Math.max(max - 1, 0); i < others.size(); i++) {
            toRevoke.add(ended(others[i].Id, 'Revoked', 'Session limit reached'));
        }
        update as system toRevoke;
    }

    public static UserContext require(String rawToken, String userAgent) {
        return require(rawToken, userAgent, false);
    }

    /**
     * Validates the token and returns the caller's context. allowRestricted lets a
     * CHANGE_PASSWORD session through (first-login and sign-out only).
     */
    public static UserContext require(String rawToken, String userAgent, Boolean allowRestricted) {
        if (String.isBlank(rawToken)) {
            throw new PortalException('SESSION_EXPIRED');
        }
        String tokenHash = TokenService.hash(rawToken);
        List<Portal_Session__c> rows = [
            SELECT
                Id, Family__c, Scope__c, Status__c, Last_Activity__c, Expires_At__c, User_Agent_Hash__c, Portal_User__c,
                Portal_User__r.Id, Portal_User__r.Family__c, Portal_User__r.Family__r.Name,
                Portal_User__r.Family__r.Family_Code__c, Portal_User__r.Family__r.Status__c,
                Portal_User__r.Family__r.Base_Currency__c, Portal_User__r.Role__c,
                Portal_User__r.Status__c, Portal_User__r.First_Name__c, Portal_User__r.Last_Name__c,
                Portal_User__r.Username__c, Portal_User__r.Email__c, Portal_User__r.Mobile__c,
                Portal_User__r.Relationship__c, Portal_User__r.Viewer_Scope__c, Portal_User__r.Must_Change_Password__c,
                Portal_User__r.MFA_Method__c
            FROM Portal_Session__c
            WHERE Token_Hash__c = :tokenHash
            WITH SYSTEM_MODE LIMIT 1
        ];
        // No DML before throwing: the REST layer rolls back, and SessionCleanupJob marks expiry.
        if (rows.isEmpty() || !isValid(rows[0], userAgent)) {
            throw new PortalException('SESSION_EXPIRED');
        }
        Portal_Session__c session = rows[0];
        if (session.Scope__c != SCOPE_FULL && !allowRestricted) {
            throw new PortalException('PASSWORD_CHANGE_REQUIRED').withError('Set a new password to continue.');
        }
        Datetime now = Datetime.now();
        if (session.Last_Activity__c.addMinutes(1) < now) {
            // Deferred: audit-log (big object) reads fail after any DML in the same request.
            activityPending = session.Id;
        }
        return new UserContext(session.Portal_User__r, session.Id, session.Scope__c);
    }

    private static Boolean isValid(Portal_Session__c session, String userAgent) {
        Datetime now = Datetime.now();
        Portal_User__c user = session.Portal_User__r;
        // A token replayed from a different browser is rejected; a missing header is tolerated.
        Boolean agentOk =
            session.User_Agent_Hash__c == null ||
            String.isBlank(userAgent) ||
            TokenService.hash(userAgent) == session.User_Agent_Hash__c;
        Boolean userOk =
            user.Status__c == 'Active' || (user.Status__c == 'Invited' && session.Scope__c == SCOPE_CHANGE_PASSWORD);
        return session.Status__c == 'Active' &&
            session.Expires_At__c > now &&
            session.Last_Activity__c.addMinutes(SecurityPolicy.idleMinutes()) > now &&
            agentOk &&
            userOk &&
            user.Family__r.Status__c == 'Active' &&
            session.Family__c == user.Family__c;
    }

    /** Saves the deferred activity time. VkfRest calls this just before writing each response. */
    public static void flushActivity() {
        if (activityPending != null) {
            update as system new Portal_Session__c(Id = activityPending, Last_Activity__c = Datetime.now());
            activityPending = null;
        }
    }

    public static void end(Id sessionId, String status, String reason) {
        update as system ended(sessionId, status, reason);
    }

    /** Revokes every active session of the user, optionally keeping one (the caller's). */
    public static Integer revokeAll(Id userId, String reason, Id exceptSessionId) {
        List<Portal_Session__c> toRevoke = new List<Portal_Session__c>();
        for (Portal_Session__c s : [
            SELECT Id
            FROM Portal_Session__c
            WHERE Portal_User__c = :userId AND Status__c = 'Active' AND Id != :exceptSessionId WITH SYSTEM_MODE
        ]) {
            toRevoke.add(ended(s.Id, 'Revoked', reason));
        }
        update as system toRevoke;
        return toRevoke.size();
    }

    public static List<Portal_Session__c> activeForUser(Id userId) {
        Datetime now = Datetime.now();
        Datetime idleCutoff = now.addMinutes(-SecurityPolicy.idleMinutes());
        return [
            SELECT Id, CreatedDate, Last_Activity__c, Expires_At__c, User_Agent__c, Scope__c
            FROM Portal_Session__c
            WHERE Portal_User__c = :userId AND Status__c = 'Active' AND Expires_At__c > :now AND Last_Activity__c > :idleCutoff
            WITH SYSTEM_MODE ORDER BY Last_Activity__c DESC
        ];
    }

    /** Ends one of the caller's own sessions. Another user's session id is NOT_FOUND. */
    public static void revokeOwn(UserContext ctx, Id sessionId) {
        List<Portal_Session__c> rows = sessionId == null
            ? new List<Portal_Session__c>()
            : [SELECT Id FROM Portal_Session__c WHERE Id = :sessionId AND Portal_User__c = :ctx.userId AND Status__c = 'Active' WITH SYSTEM_MODE];
        if (rows.isEmpty()) {
            throw new PortalException('NOT_FOUND').withError('That session has already ended.');
        }
        end(sessionId, 'Revoked', 'Signed out from another device');
    }

    /** Hourly housekeeping: mark stale sessions expired, delete old closed sessions and spent tokens. */
    public static void cleanup() {
        Datetime now = Datetime.now();
        Datetime idleCutoff = now.addMinutes(-SecurityPolicy.idleMinutes());
        List<Portal_Session__c> stale = new List<Portal_Session__c>();
        for (Portal_Session__c s : [
            SELECT Id
            FROM Portal_Session__c
            WHERE Status__c = 'Active' AND (Expires_At__c < :now OR Last_Activity__c < :idleCutoff)
            WITH SYSTEM_MODE LIMIT 5000
        ]) {
            stale.add(ended(s.Id, 'Expired', null));
        }
        update as system stale;

        Datetime retention = now.addDays(-SecurityPolicy.sessionRetentionDays());
        delete as system [SELECT Id FROM Portal_Session__c WHERE Status__c != 'Active' AND Ended_At__c < :retention WITH SYSTEM_MODE LIMIT 5000];
        delete as system [
            SELECT Id
            FROM Auth_Token__c
            WHERE (Used_At__c != null AND Used_At__c < :retention) OR Expires_At__c < :retention
            WITH SYSTEM_MODE LIMIT 5000
        ];
    }

    private static Portal_Session__c ended(Id sessionId, String status, String reason) {
        return new Portal_Session__c(
            Id = sessionId,
            Status__c = status,
            Revoke_Reason__c = reason,
            Ended_At__c = Datetime.now()
        );
    }
}
