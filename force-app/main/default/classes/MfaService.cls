/**
 * Two-step verification with an authenticator app: RFC 6238 TOTP (HMAC-SHA1, 6 digits,
 * 30-second windows, one window of clock drift either side) plus ten single-use recovery codes.
 * The key lives encrypted on the member and never leaves the server after setup; recovery codes
 * and sign-in challenges are stored only as SHA-256 hashes in Auth_Token__c.
 */
public without sharing class MfaService {
    public static final String METHOD_APP = 'Authenticator';
    public static final String TYPE_CHALLENGE = 'MFA Challenge';
    public static final String TYPE_RECOVERY = 'Recovery Code';
    public static final Integer RECOVERY_CODE_COUNT = 10;
    public static final Integer MAX_CHALLENGE_ATTEMPTS = 5;
    private static final Integer STEP_SECONDS = 30;
    private static final String ISSUER = 'VK Finance';
    private static final String HEX_DIGITS = '0123456789abcdef';
    private static final String BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    // Recovery codes skip look-alike characters (0/o, 1/l/i).
    private static final String CODE_CHARS = 'abcdefghjkmnpqrstuvwxyz23456789';

    /** Fixed clock for tests, in Unix seconds. */
    @TestVisible
    private static Long clockSeconds;

    public class Status {
        public Boolean enabled;
        public Datetime enrolledAt;
        public Integer recoveryCodesLeft;
    }

    public class Setup {
        /** Base32 key for typing into the app by hand. */
        public String secret;
        /** otpauth:// link the portal draws as a QR code. */
        public String otpauthUri;
    }

    // ---------------------------------------------------------------- TOTP

    public static String newSecretHex() {
        // 160-bit key, the size RFC 4226 recommends for HMAC-SHA1.
        return EncodingUtil.convertToHex(Crypto.generateAesKey(256)).left(40);
    }

    public static Long currentStep() {
        Long seconds = clockSeconds != null ? clockSeconds : Datetime.now().getTime() / 1000;
        return seconds / STEP_SECONDS;
    }

    public static String codeAt(String secretHex, Long step) {
        Blob mac = Crypto.generateMac('hmacSHA1', EncodingUtil.convertFromHex(toHex(step, 16)), EncodingUtil.convertFromHex(secretHex));
        String digest = EncodingUtil.convertToHex(mac);
        Integer offset = HEX_DIGITS.indexOf(digest.substring(39, 40)) * 2;
        Long truncated = fromHex(digest.substring(offset, offset + 8)) & 2147483647L;
        return String.valueOf(Math.mod(truncated, 1000000L)).leftPad(6, '0');
    }

    /** The window the code belongs to, or null. Windows at or before lastUsedStep are refused (no replay). */
    public static Long matchingStep(String secretHex, String code, Decimal lastUsedStep) {
        if (String.isBlank(secretHex) || code == null || !Pattern.matches('\\d{6}', code)) {
            return null;
        }
        Long now = currentStep();
        for (Long step = now - 1; step <= now + 1; step++) {
            if (lastUsedStep != null && step <= lastUsedStep.longValue()) {
                continue;
            }
            if (codeAt(secretHex, step) == code) {
                return step;
            }
        }
        return null;
    }

    public static String base32(String hex) {
        String bits = '';
        for (Integer i = 0; i < hex.length(); i++) {
            Integer nibble = HEX_DIGITS.indexOf(hex.substring(i, i + 1).toLowerCase());
            bits += toBinary(nibble);
        }
        while (Math.mod(bits.length(), 5) != 0) {
            bits += '0';
        }
        String result = '';
        for (Integer i = 0; i < bits.length(); i += 5) {
            Integer index = binaryValue(bits.substring(i, i + 5)).intValue();
            result += BASE32.substring(index, index + 1);
        }
        return result;
    }

    public static String otpauthUri(String secretHex, String username) {
        String issuer = EncodingUtil.urlEncode(ISSUER, 'UTF-8').replace('+', '%20');
        return 'otpauth://totp/' + issuer + ':' + EncodingUtil.urlEncode(username, 'UTF-8') +
            '?secret=' + base32(secretHex) + '&issuer=' + issuer + '&algorithm=SHA1&digits=6&period=30';
    }

    // ---------------------------------------------------------------- Checks used by sign-in and step-up

    public static Boolean isEnabled(Portal_User__c user) {
        return user != null && user.MFA_Method__c == METHOD_APP;
    }

    /**
     * Checks an authenticator code or a recovery code and spends it.
     * Returns 'app', 'recovery' or null when the code is wrong.
     */
    public static String verify(Id userId, String rawCode) {
        String code = rawCode == null ? '' : rawCode.replaceAll('[\\s-]', '').toLowerCase();
        if (code.length() == 0) {
            return null;
        }
        Portal_User__c secrets = secretsFor(userId);
        if (!isEnabled(secrets)) {
            return null;
        }
        if (Pattern.matches('\\d{6}', code)) {
            Long step = matchingStep(secrets.MFA_Secret__c, code, secrets.MFA_Last_Step__c);
            if (step == null) {
                return null;
            }
            update as system new Portal_User__c(Id = userId, MFA_Last_Step__c = step);
            return 'app';
        }
        String codeHash = TokenService.hash(code);
        List<Auth_Token__c> matches = [
            SELECT Id
            FROM Auth_Token__c
            WHERE Portal_User__c = :userId AND Type__c = :TYPE_RECOVERY AND Token_Hash__c = :codeHash AND Used_At__c = NULL
            WITH SYSTEM_MODE LIMIT 1
        ];
        if (matches.isEmpty()) {
            return null;
        }
        update as system new Auth_Token__c(Id = matches[0].Id, Used_At__c = Datetime.now());
        Integer left = recoveryCodesLeft(userId);
        notify(secrets, 'warning', 'A recovery code was used', 'You signed in or confirmed a change with a recovery code. ' + left + ' left - make new ones from Security if you are running low.');
        AuditService.log(secrets.Family__c, userId, 'MFA_RECOVERY_CODE_USED', 'Portal_User__c', userId, left + ' left');
        return 'recovery';
    }

    /** One open sign-in challenge per member; returns the raw token for the browser to send back with the code. */
    public static String startChallenge(Portal_User__c user) {
        Datetime now = Datetime.now();
        List<Auth_Token__c> open = [
            SELECT Id
            FROM Auth_Token__c
            WHERE Portal_User__c = :user.Id AND Type__c = :TYPE_CHALLENGE AND Used_At__c = NULL
            WITH SYSTEM_MODE
        ];
        for (Auth_Token__c t : open) {
            t.Used_At__c = now;
        }
        update as system open;
        String token = TokenService.newToken();
        insert as system new Auth_Token__c(
            Portal_User__c = user.Id,
            Family__c = user.Family__c,
            Type__c = TYPE_CHALLENGE,
            Token_Hash__c = TokenService.hash(token),
            Expires_At__c = now.addMinutes(SecurityPolicy.mfaChallengeMinutes()),
            Attempts__c = 0
        );
        return token;
    }

    // ---------------------------------------------------------------- Self-service

    public static Status status(Id userId) {
        Portal_User__c u = secretsFor(userId);
        Status s = new Status();
        s.enabled = isEnabled(u);
        s.enrolledAt = s.enabled ? u.MFA_Enrolled_At__c : null;
        s.recoveryCodesLeft = s.enabled ? recoveryCodesLeft(userId) : 0;
        return s;
    }

    /** Step 1: password re-check, then a fresh key. Two-step stays off until a code from the app is confirmed. */
    public static Setup beginSetup(UserContext ctx, String password) {
        if (isEnabled(secretsFor(ctx.userId))) {
            throw new PortalException('VALIDATION').withError('Two-step verification is already on.');
        }
        AuthService.requireStepUp(ctx, password);
        String secret = newSecretHex();
        update as system new Portal_User__c(Id = ctx.userId, MFA_Secret__c = secret, MFA_Last_Step__c = null);
        AuditService.log(ctx, 'MFA_SETUP_STARTED', 'Portal_User__c', ctx.userId, null);
        Setup s = new Setup();
        s.secret = base32(secret);
        s.otpauthUri = otpauthUri(secret, ctx.username);
        return s;
    }

    /** Step 2: the first code proves the app is set up. Returns the recovery codes, shown once. */
    public static List<String> confirmSetup(UserContext ctx, String code) {
        Portal_User__c u = secretsFor(ctx.userId);
        if (isEnabled(u)) {
            throw new PortalException('VALIDATION').withError('Two-step verification is already on.');
        }
        if (String.isBlank(u.MFA_Secret__c)) {
            throw new PortalException('VALIDATION').withError('Start the setup again.');
        }
        Long step = matchingStep(u.MFA_Secret__c, code == null ? null : code.replaceAll('\\s', ''), null);
        if (step == null) {
            throw new PortalException('VALIDATION')
                .withError('That code didn\'t match. Use the newest code, and check your phone sets its time automatically.');
        }
        update as system new Portal_User__c(Id = ctx.userId, MFA_Method__c = METHOD_APP, MFA_Enrolled_At__c = Datetime.now(), MFA_Last_Step__c = step);
        List<String> codes = replaceRecoveryCodes(u);
        Integer revoked = SessionService.revokeAll(ctx.userId, 'Two-step verification turned on', ctx.sessionId);
        notify(u, 'success', 'Two-step verification is on', 'Signing in now needs a code from your authenticator app. Keep your recovery codes somewhere safe.');
        AuditService.log(ctx, 'MFA_ENABLED', 'Portal_User__c', ctx.userId, revoked + ' other session(s) signed out');
        return codes;
    }

    public static void disable(UserContext ctx, String password, String code) {
        requireEnabled(ctx.userId);
        AuthService.requireStepUp(ctx, password, code);
        Portal_User__c u = secretsFor(ctx.userId);
        clear(ctx.userId);
        notify(u, 'warning', 'Two-step verification is off', 'Your account is now protected by your password only. If this wasn\'t you, change your password and tell your Family Admin.');
        AuditService.log(ctx, 'MFA_DISABLED', 'Portal_User__c', ctx.userId, null);
    }

    public static List<String> renewRecoveryCodes(UserContext ctx, String password, String code) {
        requireEnabled(ctx.userId);
        AuthService.requireStepUp(ctx, password, code);
        List<String> codes = replaceRecoveryCodes(secretsFor(ctx.userId));
        AuditService.log(ctx, 'MFA_RECOVERY_CODES_RENEWED', 'Portal_User__c', ctx.userId, null);
        return codes;
    }

    /** Turns two-step off and removes its key, recovery codes and open challenges. */
    public static void clear(Id userId) {
        update as system new Portal_User__c(Id = userId, MFA_Method__c = 'None', MFA_Secret__c = null, MFA_Enrolled_At__c = null, MFA_Last_Step__c = null);
        delete as system [
            SELECT Id
            FROM Auth_Token__c
            WHERE Portal_User__c = :userId AND Type__c IN (:TYPE_RECOVERY, :TYPE_CHALLENGE)
            WITH SYSTEM_MODE
        ];
    }

    // ---------------------------------------------------------------- Helpers

    private static List<String> replaceRecoveryCodes(Portal_User__c u) {
        delete as system [SELECT Id FROM Auth_Token__c WHERE Portal_User__c = :u.Id AND Type__c = :TYPE_RECOVERY WITH SYSTEM_MODE];
        List<String> codes = new List<String>();
        List<Auth_Token__c> rows = new List<Auth_Token__c>();
        for (Integer i = 0; i < RECOVERY_CODE_COUNT; i++) {
            String raw = randomCode(10);
            codes.add(raw.left(5) + '-' + raw.right(5));
            rows.add(new Auth_Token__c(Portal_User__c = u.Id, Family__c = u.Family__c, Type__c = TYPE_RECOVERY, Token_Hash__c = TokenService.hash(raw)));
        }
        insert as system rows;
        return codes;
    }

    private static Integer recoveryCodesLeft(Id userId) {
        return [SELECT COUNT() FROM Auth_Token__c WHERE Portal_User__c = :userId AND Type__c = :TYPE_RECOVERY AND Used_At__c = NULL WITH SYSTEM_MODE];
    }

    private static void requireEnabled(Id userId) {
        if (!isEnabled(secretsFor(userId))) {
            throw new PortalException('VALIDATION').withError('Two-step verification is off.');
        }
    }

    private static Portal_User__c secretsFor(Id userId) {
        return [
            SELECT Id, Family__c, MFA_Method__c, MFA_Secret__c, MFA_Enrolled_At__c, MFA_Last_Step__c
            FROM Portal_User__c
            WHERE Id = :userId
            WITH SYSTEM_MODE
        ];
    }

    private static void notify(Portal_User__c u, String severity, String title, String text) {
        NotificationService.notify(
            u.Family__c,
            new Set<Id>{ u.Id },
            new NotificationService.Message('security', severity, title, text, '/profile', null)
        );
    }

    private static String randomCode(Integer length) {
        String result = '';
        for (Integer i = 0; i < length; i++) {
            Integer index = Math.abs(Math.mod(Crypto.getRandomInteger(), CODE_CHARS.length()));
            result += CODE_CHARS.substring(index, index + 1);
        }
        return result;
    }

    private static String toHex(Long value, Integer width) {
        String result = '';
        Long remaining = value;
        while (remaining > 0) {
            Integer digit = Math.mod(remaining, 16L).intValue();
            result = HEX_DIGITS.substring(digit, digit + 1) + result;
            remaining = remaining / 16;
        }
        return result.leftPad(width, '0');
    }

    private static Long fromHex(String hex) {
        Long value = 0;
        for (Integer i = 0; i < hex.length(); i++) {
            value = value * 16 + HEX_DIGITS.indexOf(hex.substring(i, i + 1));
        }
        return value;
    }

    private static String toBinary(Integer nibble) {
        String result = '';
        for (Integer bit = 3; bit >= 0; bit--) {
            result += ((nibble >> bit) & 1) == 1 ? '1' : '0';
        }
        return result;
    }

    private static Long binaryValue(String bits) {
        Long value = 0;
        for (Integer i = 0; i < bits.length(); i++) {
            value = value * 2 + (bits.substring(i, i + 1) == '1' ? 1 : 0);
        }
        return value;
    }
}