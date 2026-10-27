/**
 * Sign-in, first-login, password change and self-service reset for portal users.
 * Failure counters are saved even though the request fails (PortalException.keep()).
 */
public without sharing class AuthService {
    public static final String GENERIC_RESET_MESSAGE = 'If that account exists and has an email address, we\'ve sent a link to reset the password.';
    private static final String UNKNOWN_SALT = 'AAAAAAAAAAAAAAAAAAAAAA==';

    @TestVisible
    private static String lastIssuedResetToken;

    public class LoginResult {
        public String token;
        public Boolean mustChangePassword;
        public PortalDtos.Profile profile;
    }

    public static String normalizeUsername(String username) {
        return username == null ? null : username.trim().toLowerCase();
    }

    public static LoginResult login(String username, String password, String userAgent) {
        String normalized = normalizeUsername(username);
        if (String.isBlank(normalized) || String.isBlank(password)) {
            throw new PortalException('VALIDATION').withError('Enter your username and password.');
        }
        Portal_User__c user = IdentitySelector.byUsername(normalized);
        Datetime now = Datetime.now();
        if (user == null) {
            // Spend the same hashing time as a real check so timing doesn't reveal unknown usernames.
            PasswordService.hash(password, UNKNOWN_SALT, SecurityPolicy.hashIterations());
            AuditService.log(null, null, 'LOGIN_FAILED', 'Portal_User__c', null, 'Unknown username');
            throw invalidCredentials();
        }

        if (user.Login_Window_Start__c == null || user.Login_Window_Start__c.addMinutes(SecurityPolicy.throttleWindowMinutes()) < now) {
            user.Login_Window_Start__c = now;
            user.Login_Window_Attempts__c = 0;
        }
        user.Login_Window_Attempts__c = nz(user.Login_Window_Attempts__c) + 1;
        if (user.Login_Window_Attempts__c > SecurityPolicy.throttleMaxAttempts()) {
            saveCounters(user);
            audit(user, 'LOGIN_THROTTLED', null);
            throw new PortalException('THROTTLED').withError('Too many sign-in attempts. Wait a few minutes and try again.').keep();
        }

        Boolean familyActive = user.Family__r != null && user.Family__r.Status__c == 'Active';
        Boolean userAllowed = user.Status__c == 'Active' || user.Status__c == 'Invited';
        if (!familyActive || !userAllowed) {
            PasswordService.hash(password, UNKNOWN_SALT, SecurityPolicy.hashIterations());
            saveCounters(user);
            audit(user, 'LOGIN_FAILED', 'Inactive member or family');
            throw invalidCredentials().keep();
        }

        if (user.Locked_Until__c != null && user.Locked_Until__c > now) {
            saveCounters(user);
            audit(user, 'LOGIN_LOCKED', null);
            throw new PortalException('LOCKED')
                .withError('This account is locked after too many failed attempts. Try again later or ask your Family Admin to unlock it.')
                .keep();
        }

        if (!PasswordService.matches(password, user.Password_Salt__c, user.Hash_Iterations__c, user.Password_Hash__c)) {
            user.Failed_Login_Count__c = nz(user.Failed_Login_Count__c) + 1;
            if (user.Failed_Login_Count__c >= SecurityPolicy.maxFailedLogins()) {
                // Each repeat lockout doubles the wait, capped at 16x.
                Integer multiplier = Math.pow(2, Math.min(nz(user.Lockout_Count__c), 4)).intValue();
                user.Locked_Until__c = now.addMinutes(SecurityPolicy.lockoutMinutes() * multiplier);
                user.Lockout_Count__c = nz(user.Lockout_Count__c) + 1;
                user.Failed_Login_Count__c = 0;
                audit(user, 'ACCOUNT_LOCKED', 'Locked until ' + user.Locked_Until__c.formatGmt('yyyy-MM-dd HH:mm') + ' UTC');
            } else {
                audit(user, 'LOGIN_FAILED', 'Wrong password');
            }
            saveCounters(user);
            throw invalidCredentials().keep();
        }

        if (user.Must_Change_Password__c && user.Temp_Password_Expires_At__c != null && user.Temp_Password_Expires_At__c < now) {
            saveCounters(user);
            audit(user, 'LOGIN_FAILED', 'Temporary password expired');
            throw new PortalException('INVALID_CREDENTIALS')
                .withError('Your temporary password has expired. Ask your Family Admin for a new one.')
                .keep();
        }

        user.Failed_Login_Count__c = 0;
        user.Lockout_Count__c = 0;
        user.Locked_Until__c = null;
        user.Login_Window_Attempts__c = 0;
        user.Last_Login__c = now;
        Portal_User__c updates = counters(user);
        updates.Last_Login__c = now;
        if (!user.Must_Change_Password__c && user.Hash_Iterations__c != SecurityPolicy.hashIterations()) {
            // Upgrade the stored hash to the current iteration count while we know the password.
            updates.Password_Salt__c = PasswordService.newSalt();
            updates.Hash_Iterations__c = SecurityPolicy.hashIterations();
            updates.Password_Hash__c = PasswordService.hash(password, updates.Password_Salt__c, SecurityPolicy.hashIterations());
        }
        update as system updates;

        String scope = user.Must_Change_Password__c ? SessionService.SCOPE_CHANGE_PASSWORD : SessionService.SCOPE_FULL;
        SessionService.NewSession session = SessionService.create(user, scope, userAgent);
        audit(user, 'LOGIN_SUCCESS', scope);
        return result(session, user);
    }

    public static void logout(UserContext ctx) {
        SessionService.end(ctx.sessionId, 'Logged Out', 'Signed out');
        AuditService.log(ctx, 'LOGOUT', 'Portal_Session__c', ctx.sessionId, null);
    }

    /** Replaces a temporary password, activates the member and starts a full session. */
    public static LoginResult firstLogin(UserContext ctx, String newPassword, String userAgent) {
        Portal_User__c user = IdentitySelector.byId(ctx.userId);
        if (!user.Must_Change_Password__c) {
            throw new PortalException('VALIDATION').withError('Your password is already set.');
        }
        PasswordService.validateNew(user, newPassword);
        PasswordService.apply(user, newPassword, false);
        if (user.Status__c == 'Invited') {
            user.Status__c = 'Active';
        }
        saveUserPassword(user);
        SessionService.revokeAll(user.Id, 'Password set', null);
        SessionService.NewSession session = SessionService.create(user, SessionService.SCOPE_FULL, userAgent);
        audit(user, 'PASSWORD_SET', 'First sign-in');
        return result(session, user);
    }

    public static void changePassword(UserContext ctx, String currentPassword, String newPassword) {
        Portal_User__c user = IdentitySelector.byId(ctx.userId);
        if (!PasswordService.matches(currentPassword, user.Password_Salt__c, user.Hash_Iterations__c, user.Password_Hash__c)) {
            audit(user, 'PASSWORD_CHANGE_FAILED', 'Wrong current password');
            throw new PortalException('VALIDATION').withError('Your current password is incorrect.');
        }
        PasswordService.validateNew(user, newPassword);
        PasswordService.apply(user, newPassword, false);
        saveUserPassword(user);
        Integer revoked = SessionService.revokeAll(user.Id, 'Password changed', ctx.sessionId);
        audit(user, 'PASSWORD_CHANGED', revoked + ' other session(s) signed out');
    }

    /** Always succeeds from the caller's point of view, so it never reveals whether an account exists. */
    public static void forgot(String identifier) {
        String value = normalizeUsername(identifier);
        if (String.isBlank(value)) {
            throw new PortalException('VALIDATION').withError('Enter your username or email address.');
        }
        Portal_User__c user = IdentitySelector.byUsername(value);
        if (user == null && value.contains('@')) {
            List<Portal_User__c> byEmail = IdentitySelector.byEmail(value);
            user = byEmail.size() == 1 ? byEmail[0] : null;
        }
        Boolean eligible =
            user != null &&
            String.isNotBlank(user.Email__c) &&
            (user.Status__c == 'Active' || user.Status__c == 'Invited') &&
            user.Family__r.Status__c == 'Active';
        if (!eligible) {
            AuditService.log(user?.Family__c, user?.Id, 'RESET_SKIPPED', 'Portal_User__c', user?.Id, 'No eligible account or email');
            return;
        }
        Datetime now = Datetime.now();
        List<Auth_Token__c> older = [
            SELECT Id
            FROM Auth_Token__c
            WHERE Portal_User__c = :user.Id AND Type__c = 'Reset' AND Used_At__c = NULL WITH SYSTEM_MODE
        ];
        for (Auth_Token__c t : older) {
            t.Used_At__c = now;
        }
        update as system older;

        String token = TokenService.newToken();
        insert as system new Auth_Token__c(
            Portal_User__c = user.Id,
            Family__c = user.Family__c,
            Type__c = 'Reset',
            Token_Hash__c = TokenService.hash(token),
            Expires_At__c = now.addMinutes(SecurityPolicy.resetTokenMinutes())
        );
        lastIssuedResetToken = token;
        Boolean sent = sendResetEmail(user, token);
        audit(user, 'RESET_REQUESTED', sent ? 'Email sent' : 'Email could not be sent');
    }

    public static void reset(String rawToken, String newPassword) {
        String expired = 'This reset link has expired or was already used. Request a new one.';
        if (String.isBlank(rawToken)) {
            throw new PortalException('VALIDATION').withError(expired);
        }
        String tokenHash = TokenService.hash(rawToken);
        List<Auth_Token__c> tokens = [
            SELECT Id, Portal_User__c, Expires_At__c, Used_At__c
            FROM Auth_Token__c
            WHERE Token_Hash__c = :tokenHash AND Type__c = 'Reset'
            WITH SYSTEM_MODE LIMIT 1
        ];
        Datetime now = Datetime.now();
        if (tokens.isEmpty() || tokens[0].Used_At__c != null || tokens[0].Expires_At__c < now) {
            throw new PortalException('VALIDATION').withError(expired);
        }
        Portal_User__c user = IdentitySelector.byId(tokens[0].Portal_User__c);
        if (!(user.Status__c == 'Active' || user.Status__c == 'Invited') || user.Family__r.Status__c != 'Active') {
            throw new PortalException('VALIDATION').withError(expired);
        }
        PasswordService.validateNew(user, newPassword);
        PasswordService.apply(user, newPassword, false);
        if (user.Status__c == 'Invited') {
            user.Status__c = 'Active';
        }
        user.Lockout_Count__c = 0;
        saveUserPassword(user);
        update as system new Auth_Token__c(Id = tokens[0].Id, Used_At__c = now);
        SessionService.revokeAll(user.Id, 'Password reset', null);
        audit(user, 'PASSWORD_RESET', 'Self-service link');
    }

    /** Re-checks the caller's own password before a sensitive admin action. */
    public static void requireStepUp(UserContext ctx, String password) {
        Portal_User__c me = IdentitySelector.byId(ctx.userId);
        if (!PasswordService.matches(password, me.Password_Salt__c, me.Hash_Iterations__c, me.Password_Hash__c)) {
            AuditService.log(ctx, 'STEP_UP_FAILED', 'Portal_User__c', ctx.userId, null);
            throw new PortalException('VALIDATION').withError('Re-enter your own password to confirm this change.');
        }
    }

    private static Boolean sendResetEmail(Portal_User__c user, String token) {
        String base = SecurityPolicy.portalBaseUrl();
        if (String.isBlank(base)) {
            return false;
        }
        String link = base.removeEnd('/') + '/reset-password?t=' + EncodingUtil.urlEncode(token, 'UTF-8');
        try {
            Messaging.reserveSingleEmailCapacity(1);
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ user.Email__c });
            mail.setSenderDisplayName('VK Finance');
            mail.setSubject('Reset your VK Finance password');
            mail.setPlainTextBody(
                'Hi ' + user.First_Name__c + ',\n\n' +
                'Use this link within ' + SecurityPolicy.resetTokenMinutes() + ' minutes to set a new VK Finance password:\n' +
                link + '\n\n' +
                'If you didn\'t ask for this, ignore this email - your password won\'t change.\n\nVK Finance'
            );
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Reset email not sent: ' + e.getMessage());
            return false;
        }
    }

    private static LoginResult result(SessionService.NewSession session, Portal_User__c user) {
        UserContext ctx = new UserContext(user, session.record.Id, session.record.Scope__c);
        LoginResult r = new LoginResult();
        r.token = session.token;
        r.mustChangePassword = user.Must_Change_Password__c;
        r.profile = PortalDtos.profile(ctx);
        return r;
    }

    private static void saveUserPassword(Portal_User__c user) {
        update as system new Portal_User__c(
            Id = user.Id,
            Status__c = user.Status__c,
            Password_Hash__c = user.Password_Hash__c,
            Password_Salt__c = user.Password_Salt__c,
            Hash_Iterations__c = user.Hash_Iterations__c,
            Password_Changed_At__c = user.Password_Changed_At__c,
            Must_Change_Password__c = user.Must_Change_Password__c,
            Temp_Password_Expires_At__c = user.Temp_Password_Expires_At__c,
            Failed_Login_Count__c = 0,
            Locked_Until__c = null,
            Lockout_Count__c = user.Lockout_Count__c
        );
        PasswordService.recordHistory(user);
    }

    private static void saveCounters(Portal_User__c user) {
        update as system counters(user);
    }

    private static Portal_User__c counters(Portal_User__c user) {
        return new Portal_User__c(
            Id = user.Id,
            Failed_Login_Count__c = user.Failed_Login_Count__c,
            Lockout_Count__c = user.Lockout_Count__c,
            Locked_Until__c = user.Locked_Until__c,
            Login_Window_Start__c = user.Login_Window_Start__c,
            Login_Window_Attempts__c = user.Login_Window_Attempts__c
        );
    }

    private static PortalException invalidCredentials() {
        return new PortalException('INVALID_CREDENTIALS').withError('Invalid username or password.');
    }

    private static void audit(Portal_User__c user, String eventType, String details) {
        AuditService.log(user.Family__c, user.Id, eventType, 'Portal_User__c', user.Id, details);
    }

    private static Integer nz(Decimal value) {
        return value == null ? 0 : value.intValue();
    }
}
