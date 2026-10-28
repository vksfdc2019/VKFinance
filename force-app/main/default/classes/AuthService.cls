/**
 * Sign-in, first-login, password change and self-service reset for portal users.
 * Failure counters are saved even though the request fails (PortalException.keep()).
 */
public without sharing class AuthService {
    public static final String GENERIC_RESET_MESSAGE = 'If that account exists and has an email address, we\'ve sent a link to reset the password.';
    private static final String UNKNOWN_SALT = 'AAAAAAAAAAAAAAAAAAAAAA=='; // NOPMD - dummy salt that equalises timing, not a credential
    /** Reset requests allowed from one address per throttle window, and reset emails per member per hour. */
    private static final Integer RESETS_PER_ADDRESS = 10;
    private static final Integer RESET_EMAILS_PER_HOUR = 3;

    @TestVisible
    private static String lastIssuedResetToken;

    public class LoginResult {
        public String token;
        public Boolean mustChangePassword;
        public PortalDtos.Profile profile;
        /** True when the password was right and an authenticator code is needed next. */
        public Boolean mfaRequired;
        /** One-time token the browser sends back with the code. */
        public String challenge;
    }

    public static String normalizeUsername(String username) {
        return username == null ? null : username.trim().toLowerCase();
    }

    public static LoginResult login(String username, String password, String userAgent) {
        String normalized = normalizeUsername(username);
        if (String.isBlank(normalized) || String.isBlank(password)) {
            throw new PortalException('VALIDATION').withError('Enter your username and password.');
        }
        requireAddressAllowed();
        Portal_User__c user = IdentitySelector.byUsername(normalized);
        Datetime now = Datetime.now();
        if (user == null) {
            // Spend the same hashing time as a real check so timing doesn't reveal unknown usernames.
            PasswordService.hash(password, UNKNOWN_SALT, SecurityPolicy.hashIterations());
            RateLimiter.hit(RateLimiter.AUTH);
            AuditService.log(null, null, 'LOGIN_FAILED', 'Portal_User__c', null, 'Unknown username');
            throw invalidCredentials().keep();
        }

        if (user.Login_Window_Start__c == null || user.Login_Window_Start__c.addMinutes(SecurityPolicy.throttleWindowMinutes()) < now) {
            user.Login_Window_Start__c = now;
            user.Login_Window_Attempts__c = 0;
        }
        user.Login_Window_Attempts__c = nz(user.Login_Window_Attempts__c) + 1;
        if (user.Login_Window_Attempts__c > SecurityPolicy.throttleMaxAttempts()) {
            saveCounters(user);
            RateLimiter.hit(RateLimiter.AUTH);
            audit(user, 'LOGIN_THROTTLED', null);
            throw throttled().keep();
        }

        Boolean familyActive = user.Family__r != null && user.Family__r.Status__c == 'Active';
        Boolean userAllowed = user.Status__c == 'Active' || user.Status__c == 'Invited';
        if (!familyActive || !userAllowed) {
            PasswordService.hash(password, UNKNOWN_SALT, SecurityPolicy.hashIterations());
            saveCounters(user);
            RateLimiter.hit(RateLimiter.AUTH);
            audit(user, 'LOGIN_FAILED', 'Inactive member or family');
            throw invalidCredentials().keep();
        }

        if (user.Locked_Until__c != null && user.Locked_Until__c > now) {
            saveCounters(user);
            RateLimiter.hit(RateLimiter.AUTH);
            audit(user, 'LOGIN_LOCKED', null);
            throw lockedError().keep();
        }

        if (!PasswordService.matches(password, user.Password_Salt__c, user.Hash_Iterations__c, user.Password_Hash__c)) {
            registerFailure(user, now, 'LOGIN_FAILED', 'Wrong password');
            saveCounters(user);
            RateLimiter.hit(RateLimiter.AUTH);
            throw invalidCredentials().keep();
        }

        if (user.Must_Change_Password__c && user.Temp_Password_Expires_At__c != null && user.Temp_Password_Expires_At__c < now) {
            saveCounters(user);
            audit(user, 'LOGIN_FAILED', 'Temporary password expired');
            throw new PortalException('INVALID_CREDENTIALS')
                .withError('Your temporary password has expired. Ask your Family Admin for a new one.')
                .keep();
        }

        Portal_User__c updates = counters(user);
        if (!user.Must_Change_Password__c && user.Hash_Iterations__c != SecurityPolicy.hashIterations()) {
            // Upgrade the stored hash to the current iteration count while we know the password.
            updates.Password_Salt__c = PasswordService.newSalt();
            updates.Hash_Iterations__c = SecurityPolicy.hashIterations();
            updates.Password_Hash__c = PasswordService.hash(password, updates.Password_Salt__c, SecurityPolicy.hashIterations());
        }

        if (MfaService.isEnabled(user)) {
            // Failure counters stay as they are until the code is right, so codes can't be guessed indefinitely.
            update as system updates;
            LoginResult pending = new LoginResult();
            pending.mfaRequired = true;
            pending.challenge = MfaService.startChallenge(user);
            pending.mustChangePassword = user.Must_Change_Password__c;
            audit(user, 'LOGIN_MFA_REQUIRED', null);
            return pending;
        }
        return completeLogin(user, updates, userAgent, 'password');
    }

    /** Second sign-in step: the challenge from login() plus an authenticator or recovery code. */
    public static LoginResult completeMfa(String rawChallenge, String code, String userAgent) {
        requireAddressAllowed();
        PortalException expired = new PortalException('MFA_EXPIRED').withError('That sign-in has expired. Sign in again.');
        if (String.isBlank(rawChallenge)) {
            throw expired;
        }
        String challengeHash = TokenService.hash(rawChallenge);
        String challengeType = MfaService.TYPE_CHALLENGE;
        List<Auth_Token__c> rows = [
            SELECT Id, Portal_User__c, Expires_At__c, Used_At__c, Attempts__c
            FROM Auth_Token__c
            WHERE Token_Hash__c = :challengeHash AND Type__c = :challengeType
            WITH SYSTEM_MODE LIMIT 1
        ];
        Datetime now = Datetime.now();
        if (rows.isEmpty() || rows[0].Used_At__c != null || rows[0].Expires_At__c < now) {
            throw expired;
        }
        Auth_Token__c challenge = rows[0];
        Portal_User__c user = IdentitySelector.byId(challenge.Portal_User__c);
        if (!(user.Status__c == 'Active' || user.Status__c == 'Invited') || user.Family__r.Status__c != 'Active') {
            throw expired;
        }
        if (user.Locked_Until__c != null && user.Locked_Until__c > now) {
            update as system new Auth_Token__c(Id = challenge.Id, Used_At__c = now);
            throw lockedError().keep();
        }

        String method = MfaService.verify(user.Id, code);
        if (method == null) {
            challenge.Attempts__c = nz(challenge.Attempts__c) + 1;
            Boolean locked = registerFailure(user, now, 'LOGIN_FAILED', 'Wrong two-step code');
            if (locked || challenge.Attempts__c >= MfaService.MAX_CHALLENGE_ATTEMPTS) {
                challenge.Used_At__c = now;
            }
            update as system challenge;
            saveCounters(user);
            RateLimiter.hit(RateLimiter.AUTH);
            if (locked) {
                throw lockedError().keep();
            }
            if (challenge.Used_At__c != null) {
                throw new PortalException('MFA_EXPIRED').withError('Too many wrong codes. Sign in again.').keep();
            }
            throw new PortalException('INVALID_CODE').withError('That code didn\'t work. Enter the newest code from your app, or a recovery code.').keep();
        }
        update as system new Auth_Token__c(Id = challenge.Id, Used_At__c = now);
        return completeLogin(user, counters(user), userAgent, method == 'recovery' ? 'recovery code' : 'authenticator app');
    }

    private static LoginResult completeLogin(Portal_User__c user, Portal_User__c updates, String userAgent, String method) {
        Datetime now = Datetime.now();
        user.Failed_Login_Count__c = 0;
        user.Locked_Until__c = null;
        updates.Failed_Login_Count__c = 0;
        updates.Lockout_Count__c = 0;
        updates.Locked_Until__c = null;
        updates.Login_Window_Attempts__c = 0;
        updates.Last_Login__c = now;
        update as system updates;

        Boolean newDevice = isNewDevice(user.Id, userAgent);
        String scope = user.Must_Change_Password__c ? SessionService.SCOPE_CHANGE_PASSWORD : SessionService.SCOPE_FULL;
        SessionService.NewSession session = SessionService.create(user, scope, userAgent);
        audit(user, 'LOGIN_SUCCESS', scope + (method == 'password' ? '' : ', ' + method));
        if (newDevice && (user.Role__c == 'Family Admin' || user.Role__c == 'Co-Admin')) {
            notifySelf(user, 'info', 'New sign-in to your account', 'You signed in on ' + PortalDtos.describeDevice(userAgent) + '. If this wasn\'t you, change your password now.');
        }
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
            failConfirmation(user, 'PASSWORD_CHANGE_FAILED', 'Wrong current password', 'Your current password is incorrect.');
        }
        PasswordService.validateNew(user, newPassword);
        PasswordService.apply(user, newPassword, false);
        saveUserPassword(user);
        Integer revoked = SessionService.revokeAll(user.Id, 'Password changed', ctx.sessionId);
        audit(user, 'PASSWORD_CHANGED', revoked + ' other session(s) signed out');
        notifySelf(user, 'info', 'Your password was changed', 'Other devices were signed out. If this wasn\'t you, contact your Family Admin straight away.');
    }

    /** Always succeeds from the caller's point of view, so it never reveals whether an account exists. */
    public static void forgot(String identifier) {
        String value = normalizeUsername(identifier);
        if (String.isBlank(value)) {
            throw new PortalException('VALIDATION').withError('Enter your username or email address.');
        }
        if (RateLimiter.isBlocked(RateLimiter.RESET, RESETS_PER_ADDRESS)) {
            AuditService.log(null, null, 'RESET_THROTTLED', 'Portal_User__c', null, 'Too many requests from one address');
            throw throttled();
        }
        RateLimiter.hit(RateLimiter.RESET);
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
        // Caps reset emails per member, protecting the org's small daily email allowance.
        Datetime hourAgo = now.addHours(-1);
        if ([SELECT COUNT() FROM Auth_Token__c WHERE Portal_User__c = :user.Id AND Type__c = 'Reset' AND CreatedDate >= :hourAgo WITH SYSTEM_MODE] >= RESET_EMAILS_PER_HOUR) {
            audit(user, 'RESET_THROTTLED', 'Hourly email limit reached');
            return;
        }
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
        notifySelf(user, 'info', 'Your password was reset', 'You set a new password with an email link, and every device was signed out.');
    }

    public static void requireStepUp(UserContext ctx, String password) {
        requireStepUp(ctx, password, null);
    }

    /**
     * Re-checks the caller's own password - plus a fresh code when two-step is on - before a
     * sensitive action. Wrong answers count toward lockout, and a lockout ends every session,
     * so a stolen session can't be used to guess the password.
     */
    public static void requireStepUp(UserContext ctx, String password, String code) {
        Portal_User__c me = IdentitySelector.byId(ctx.userId);
        if (!PasswordService.matches(password, me.Password_Salt__c, me.Hash_Iterations__c, me.Password_Hash__c)) {
            failConfirmation(me, 'STEP_UP_FAILED', 'Wrong password', 'Re-enter your own password to confirm this change.');
        }
        if (MfaService.isEnabled(me) && MfaService.verify(me.Id, code) == null) {
            failConfirmation(me, 'STEP_UP_FAILED', 'Wrong two-step code', 'Enter the current code from your authenticator app, or a recovery code, to confirm.');
        }
    }

    private static void failConfirmation(Portal_User__c user, String eventType, String reason, String message) {
        Boolean locked = registerFailure(user, Datetime.now(), eventType, reason);
        saveCounters(user);
        if (locked) {
            SessionService.revokeAll(user.Id, 'Locked after failed confirmations', null);
            throw new PortalException('SESSION_EXPIRED').withError('Too many failed attempts. You have been signed out.').keep();
        }
        throw new PortalException('VALIDATION').withError(message).keep();
    }

    /** Counts a failure; at the policy limit locks the account (each repeat lockout doubles the wait, capped at 16x). */
    private static Boolean registerFailure(Portal_User__c user, Datetime now, String eventType, String reason) {
        user.Failed_Login_Count__c = nz(user.Failed_Login_Count__c) + 1;
        if (user.Failed_Login_Count__c < SecurityPolicy.maxFailedLogins()) {
            audit(user, eventType, reason);
            return false;
        }
        Integer multiplier = Math.pow(2, Math.min(nz(user.Lockout_Count__c), 4)).intValue();
        user.Locked_Until__c = now.addMinutes(SecurityPolicy.lockoutMinutes() * multiplier);
        user.Lockout_Count__c = nz(user.Lockout_Count__c) + 1;
        user.Failed_Login_Count__c = 0;
        audit(user, 'ACCOUNT_LOCKED', reason + '; locked until ' + user.Locked_Until__c.formatGmt('yyyy-MM-dd HH:mm') + ' UTC');
        Set<Id> admins = SystemContext.adminIds(user.Family__c);
        admins.remove(user.Id);
        NotificationService.notify(
            user.Family__c,
            admins,
            new NotificationService.Message(
                'security',
                'warning',
                user.First_Name__c + '\'s account is locked',
                'Locked after ' + SecurityPolicy.maxFailedLogins() + ' failed attempts (' + reason.toLowerCase() + '). It unlocks by itself, or you can unlock it from Family.',
                '/family',
                null
            )
        );
        return true;
    }

    private static void requireAddressAllowed() {
        if (RateLimiter.isBlocked(RateLimiter.AUTH, SecurityPolicy.ipMaxFailures())) {
            AuditService.log(null, null, 'LOGIN_THROTTLED', 'Portal_User__c', null, 'Too many failures from one address');
            throw throttled();
        }
    }

    /** True when this browser hasn't been used by the member before (and it isn't their first sign-in). */
    private static Boolean isNewDevice(Id userId, String userAgent) {
        if (String.isBlank(userAgent)) {
            return false;
        }
        String agentHash = TokenService.hash(userAgent);
        Integer known = [SELECT COUNT() FROM Portal_Session__c WHERE Portal_User__c = :userId AND User_Agent_Hash__c = :agentHash WITH SYSTEM_MODE];
        return known == 0 && [SELECT COUNT() FROM Portal_Session__c WHERE Portal_User__c = :userId WITH SYSTEM_MODE] > 0;
    }

    private static void notifySelf(Portal_User__c user, String severity, String title, String text) {
        NotificationService.notify(user.Family__c, new Set<Id>{ user.Id }, new NotificationService.Message('security', severity, title, text, '/profile', null));
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

    private static PortalException throttled() {
        return new PortalException('THROTTLED').withError('Too many attempts. Wait a few minutes and try again.');
    }

    private static PortalException lockedError() {
        return new PortalException('LOCKED')
            .withError('This account is locked after too many failed attempts. Try again later or ask your Family Admin to unlock it.');
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
