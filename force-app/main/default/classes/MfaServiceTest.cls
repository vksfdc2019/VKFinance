@IsTest
private class MfaServiceTest {
    // RFC 6238 appendix B, SHA-1 seed "12345678901234567890".
    private static final String RFC_SECRET = '3132333435363738393031323334353637383930';
    private static final String WRONG = 'Wrong#Password1';

    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void totpMatchesRfcVectors() {
        Assert.areEqual('287082', MfaService.codeAt(RFC_SECRET, 59L / 30));
        Assert.areEqual('081804', MfaService.codeAt(RFC_SECRET, 1111111109L / 30));
        Assert.areEqual('005924', MfaService.codeAt(RFC_SECRET, 1234567890L / 30));
        Assert.areEqual('279037', MfaService.codeAt(RFC_SECRET, 2000000000L / 30));
        Assert.areEqual('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', MfaService.base32(RFC_SECRET));
        Assert.isTrue(MfaService.otpauthUri(RFC_SECRET, 'admina').startsWith('otpauth://totp/VK%20Finance:admina?secret=GEZDGNBV'));
        Assert.areEqual(40, MfaService.newSecretHex().length());
    }

    @IsTest
    static void codesAllowOneWindowOfDriftAndNeverReplay() {
        MfaService.clockSeconds = 1700000000L;
        Long step = MfaService.currentStep();
        Assert.areEqual(step - 1, MfaService.matchingStep(RFC_SECRET, MfaService.codeAt(RFC_SECRET, step - 1), null));
        Assert.areEqual(step + 1, MfaService.matchingStep(RFC_SECRET, MfaService.codeAt(RFC_SECRET, step + 1), null));
        Assert.isNull(MfaService.matchingStep(RFC_SECRET, MfaService.codeAt(RFC_SECRET, step + 2), null), 'Too far ahead');
        Assert.isNull(MfaService.matchingStep(RFC_SECRET, MfaService.codeAt(RFC_SECRET, step), step), 'Replayed window');
        Assert.isNull(MfaService.matchingStep(RFC_SECRET, 'abc123', null));
    }

    @IsTest
    static void setupNeedsPasswordAndAWorkingCode() {
        VkfTestData.fastPolicy();
        MfaService.clockSeconds = 1700000000L;
        UserContext ctx = VkfTestData.ctx('admina');
        String otherDevice = VkfTestData.login('admina');

        Assert.areEqual('VALIDATION', setupError(ctx, WRONG));
        MfaService.Setup setup = MfaService.beginSetup(ctx, VkfTestData.PASSWORD);
        Assert.areEqual(32, setup.secret.length());
        Assert.isTrue(setup.otpauthUri.contains('secret=' + setup.secret));
        Assert.isFalse(MfaService.status(ctx.userId).enabled, 'Off until a code is confirmed');

        String secret = secretOf(ctx.userId);
        Assert.areEqual('VALIDATION', confirmError(ctx, MfaService.codeAt(secret, MfaService.currentStep() + 5)));

        List<String> codes = MfaService.confirmSetup(ctx, MfaService.codeAt(secret, MfaService.currentStep()));
        Assert.areEqual(10, codes.size());
        Assert.isTrue(Pattern.matches('[a-z2-9]{5}-[a-z2-9]{5}', codes[0]), codes[0]);
        MfaService.Status status = MfaService.status(ctx.userId);
        Assert.isTrue(status.enabled);
        Assert.areEqual(10, status.recoveryCodesLeft);
        Assert.areEqual('Revoked', sessionStatus(otherDevice), 'Other devices are signed out');
        Assert.areEqual(1, [SELECT COUNT() FROM Notification__c WHERE Recipient__c = :ctx.userId AND Type__c = 'security' WITH SYSTEM_MODE]);
        Assert.areEqual('VALIDATION', setupError(ctx, VkfTestData.PASSWORD), 'Already on');
    }

    @IsTest
    static void signInAsksForACodeAfterThePassword() {
        VkfTestData.fastPolicy();
        MfaService.clockSeconds = 1700000000L;
        Id userId = enrol('admina');

        AuthService.LoginResult first = AuthService.login('admina', VkfTestData.PASSWORD, VkfTestData.UA);
        Assert.isTrue(first.mfaRequired);
        Assert.isNull(first.token, 'No session before the code');
        Assert.isNotNull(first.challenge);

        Assert.areEqual('INVALID_CODE', completeError(first.challenge, '000000'));
        String code = nextCode(userId);
        AuthService.LoginResult done = AuthService.completeMfa(first.challenge, code, VkfTestData.UA);
        Assert.isNotNull(SessionService.require(done.token, VkfTestData.UA));
        Assert.isTrue(done.profile.mfaEnabled);

        Assert.areEqual('MFA_EXPIRED', completeError(first.challenge, code), 'A challenge works once');
        AuthService.LoginResult second = AuthService.login('admina', VkfTestData.PASSWORD, VkfTestData.UA);
        Assert.areEqual('INVALID_CODE', completeError(second.challenge, code), 'A code works once');
        Assert.areEqual('MFA_EXPIRED', completeError(null, code));

        update as system new Auth_Token__c(Id = openChallengeId(userId), Expires_At__c = Datetime.now().addMinutes(-1));
        Assert.areEqual('MFA_EXPIRED', completeError(second.challenge, nextCode(userId)));
    }

    @IsTest
    static void recoveryCodesWorkOnceEach() {
        VkfTestData.fastPolicy();
        MfaService.clockSeconds = 1700000000L;
        UserContext ctx = VkfTestData.ctx('membera');
        MfaService.beginSetup(ctx, VkfTestData.PASSWORD);
        List<String> codes = MfaService.confirmSetup(ctx, nextCode(ctx.userId));

        AuthService.LoginResult pending = AuthService.login('membera', VkfTestData.PASSWORD, VkfTestData.UA);
        Assert.isNotNull(AuthService.completeMfa(pending.challenge, codes[0].toUpperCase(), VkfTestData.UA).token);
        Assert.areEqual(9, MfaService.status(ctx.userId).recoveryCodesLeft);

        AuthService.LoginResult again = AuthService.login('membera', VkfTestData.PASSWORD, VkfTestData.UA);
        Assert.areEqual('INVALID_CODE', completeError(again.challenge, codes[0]));
        UserContext fresh = SessionService.require(AuthService.completeMfa(again.challenge, codes[1], VkfTestData.UA).token, VkfTestData.UA);

        List<String> renewed = MfaService.renewRecoveryCodes(fresh, VkfTestData.PASSWORD, nextCode(ctx.userId));
        Assert.areEqual(10, MfaService.status(ctx.userId).recoveryCodesLeft);
        AuthService.LoginResult third = AuthService.login('membera', VkfTestData.PASSWORD, VkfTestData.UA);
        Assert.areEqual('INVALID_CODE', completeError(third.challenge, codes[2]), 'Old codes stop working');
        Assert.isNotNull(AuthService.completeMfa(third.challenge, renewed[0], VkfTestData.UA).token);
    }

    @IsTest
    static void wrongCodesCountTowardLockoutAcrossChallenges() {
        VkfTestData.fastPolicy(5, 100);
        MfaService.clockSeconds = 1700000000L;
        enrol('membera');

        AuthService.LoginResult one = AuthService.login('membera', VkfTestData.PASSWORD, VkfTestData.UA);
        for (Integer i = 0; i < 3; i++) {
            Assert.areEqual('INVALID_CODE', completeError(one.challenge, '000000'));
        }
        // A correct password doesn't reset the count while the code is still outstanding.
        AuthService.LoginResult two = AuthService.login('membera', VkfTestData.PASSWORD, VkfTestData.UA);
        Assert.areEqual('INVALID_CODE', completeError(two.challenge, '000000'));
        Assert.areEqual('LOCKED', completeError(two.challenge, '000000'));
        Assert.areEqual('LOCKED', loginError('membera', VkfTestData.PASSWORD));

        Set<Id> admins = new Set<Id>{ VkfTestData.userId('admina'), VkfTestData.userId('coadmina') };
        Assert.areEqual(2, [SELECT COUNT() FROM Notification__c WHERE Recipient__c IN :admins AND Type__c = 'security' WITH SYSTEM_MODE]);
    }

    @IsTest
    static void oneChallengeAllowsFiveTries() {
        VkfTestData.fastPolicy(100, 100);
        MfaService.clockSeconds = 1700000000L;
        Id userId = enrol('membera');
        AuthService.LoginResult pending = AuthService.login('membera', VkfTestData.PASSWORD, VkfTestData.UA);
        for (Integer i = 0; i < MfaService.MAX_CHALLENGE_ATTEMPTS - 1; i++) {
            Assert.areEqual('INVALID_CODE', completeError(pending.challenge, '000000'));
        }
        Assert.areEqual('MFA_EXPIRED', completeError(pending.challenge, '000000'));
        Assert.areEqual('MFA_EXPIRED', completeError(pending.challenge, nextCode(userId)));
    }

    @IsTest
    static void stepUpAndTurningOffNeedACode() {
        VkfTestData.fastPolicy();
        MfaService.clockSeconds = 1700000000L;
        UserContext ctx = VkfTestData.ctx('admina');
        MfaService.beginSetup(ctx, VkfTestData.PASSWORD);
        MfaService.confirmSetup(ctx, nextCode(ctx.userId));

        Assert.areEqual('VALIDATION', stepUpError(ctx, VkfTestData.PASSWORD, null), 'Code required');
        Assert.areEqual('OK', stepUpError(ctx, VkfTestData.PASSWORD, nextCode(ctx.userId)));
        Assert.areEqual('VALIDATION', disableError(ctx, WRONG, nextCode(ctx.userId)));

        MfaService.disable(ctx, VkfTestData.PASSWORD, nextCode(ctx.userId));
        Assert.isFalse(MfaService.status(ctx.userId).enabled);
        Assert.areEqual(0, [SELECT COUNT() FROM Auth_Token__c WHERE Portal_User__c = :ctx.userId AND Type__c = 'Recovery Code' WITH SYSTEM_MODE]);
        Assert.isNull(secretOf(ctx.userId));
        Assert.areEqual('OK', stepUpError(ctx, VkfTestData.PASSWORD, null), 'Password only again');
        Assert.areEqual('VALIDATION', disableError(ctx, VkfTestData.PASSWORD, null), 'Already off');
        Assert.isNotNull(AuthService.login('admina', VkfTestData.PASSWORD, VkfTestData.UA).token);
    }

    @IsTest
    static void repeatedFailedConfirmationsSignTheMemberOut() {
        VkfTestData.fastPolicy(3, 100);
        UserContext ctx = VkfTestData.ctx('membera');
        Assert.areEqual('VALIDATION', stepUpError(ctx, WRONG, null));
        try {
            AuthService.changePassword(ctx, WRONG, 'An0ther#Harbour');
            Assert.fail('Wrong current password');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        Assert.areEqual('SESSION_EXPIRED', stepUpError(ctx, WRONG, null));
        Assert.areEqual('Revoked', [SELECT Status__c FROM Portal_Session__c WHERE Id = :ctx.sessionId WITH SYSTEM_MODE].Status__c);
        Assert.isNotNull([SELECT Locked_Until__c FROM Portal_User__c WHERE Id = :ctx.userId WITH SYSTEM_MODE].Locked_Until__c);
    }

    @IsTest
    static void adminCanResetAMembersTwoStep() {
        VkfTestData.fastPolicy();
        MfaService.clockSeconds = 1700000000L;
        Id memberId = enrol('membera');
        Id adminId = enrol('admina');
        AuthService.LoginResult pending = AuthService.login('admina', VkfTestData.PASSWORD, VkfTestData.UA);
        UserContext admin = SessionService.require(AuthService.completeMfa(pending.challenge, nextCode(adminId), VkfTestData.UA).token, VkfTestData.UA);
        UserContext coAdmin = VkfTestData.ctx('coadmina');
        UserContext otherFamily = VkfTestData.ctx('adminb');

        Assert.areEqual('VALIDATION', resetMfaError(admin, memberId, null), 'Admin needs their own code');
        Assert.areEqual('VALIDATION', resetMfaError(admin, adminId, nextCode(adminId)), 'Not for yourself');
        Assert.areEqual('NOT_AUTHORIZED', resetMfaError(coAdmin, adminId, null));
        Assert.areEqual('NOT_FOUND', resetMfaError(otherFamily, memberId, null));

        Assert.areEqual('OK', resetMfaError(admin, memberId, nextCode(adminId)));
        Assert.isFalse(MfaService.status(memberId).enabled);
        Assert.isNotNull(AuthService.login('membera', VkfTestData.PASSWORD, VkfTestData.UA).token, 'Password only again');
        for (PortalDtos.Member m : MemberService.listMembers(admin)) {
            Assert.areEqual(m.id == adminId, m.mfaEnabled, m.username);
        }
        Assert.areEqual('VALIDATION', resetMfaError(admin, memberId, nextCode(adminId)), 'Already off');
    }

    @IsTest
    static void oneAddressIsThrottledAcrossUsernames() {
        VkfTestData.fastPolicy(100, 100);
        SecurityPolicy.cached.Ip_Max_Failures__c = 3;
        RateLimiter.testAddress = '203.0.113.9';
        Assert.areEqual('INVALID_CREDENTIALS', loginError('nobody1', WRONG));
        Assert.areEqual('INVALID_CREDENTIALS', loginError('nobody2', WRONG));
        Assert.areEqual('INVALID_CREDENTIALS', loginError('membera', WRONG));
        Assert.areEqual('THROTTLED', loginError('admina', VkfTestData.PASSWORD), 'Even the right password waits');
        Rate_Limit__c row = [SELECT Key__c, Hits__c FROM Rate_Limit__c WITH SYSTEM_MODE LIMIT 1];
        Assert.areEqual(3, row.Hits__c);
        Assert.isFalse(row.Key__c.contains('203.0.113.9'), 'Only a hash of the address is stored');

        RateLimiter.testAddress = '198.51.100.7';
        Assert.areEqual('OK', loginError('admina', VkfTestData.PASSWORD), 'Other addresses are unaffected');
    }

    @IsTest
    static void resetRequestsAreCapped() {
        VkfTestData.fastPolicy();
        RateLimiter.testAddress = '203.0.113.10';
        Id memberId = VkfTestData.userId('membera');
        for (Integer i = 0; i < 5; i++) {
            AuthService.forgot('membera');
        }
        Assert.areEqual(3, [SELECT COUNT() FROM Auth_Token__c WHERE Portal_User__c = :memberId AND Type__c = 'Reset' WITH SYSTEM_MODE]);
        for (Integer i = 0; i < 5; i++) {
            AuthService.forgot('nobody' + i);
        }
        try {
            AuthService.forgot('membera');
            Assert.fail('Address limit');
        } catch (PortalException e) {
            Assert.areEqual('THROTTLED', e.code());
        }
    }

    @IsTest
    static void newDeviceSignInNotifiesAdmins() {
        VkfTestData.fastPolicy();
        Id adminId = VkfTestData.userId('admina');
        AuthService.login('admina', VkfTestData.PASSWORD, VkfTestData.UA);
        AuthService.login('admina', VkfTestData.PASSWORD, VkfTestData.UA);
        Assert.areEqual(0, [SELECT COUNT() FROM Notification__c WHERE Recipient__c = :adminId WITH SYSTEM_MODE], 'Known device');
        AuthService.login('admina', VkfTestData.PASSWORD, 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0) Safari/604.1');
        Notification__c n = [SELECT Message__c FROM Notification__c WHERE Recipient__c = :adminId WITH SYSTEM_MODE];
        Assert.isTrue(n.Message__c.contains('Safari on iOS'), n.Message__c);
    }

    @IsTest
    static void restEndpointsDriveTheWholeFlow() {
        VkfTestData.fastPolicy();
        MfaService.clockSeconds = 1700000000L;
        String token = VkfTestData.login('membera');
        Id userId = VkfTestData.userId('membera');
        String password = '"currentPassword":"' + VkfTestData.PASSWORD + '"';

        RestResponse res = VkfTestData.call('POST', '/vkf/v1/profile/mfa/setup', '{' + password + '}', token);
        VkfProfileResource.post();
        Assert.areEqual(200, res.statusCode, '' + res.responseBody?.toString());
        Assert.isTrue(((String) VkfTestData.json(res).get('otpauthUri')).startsWith('otpauth://'));

        res = VkfTestData.call('POST', '/vkf/v1/profile/mfa/confirm', '{"code":"' + nextCode(userId) + '"}', token);
        VkfProfileResource.post();
        Assert.areEqual(10, ((List<Object>) VkfTestData.json(res).get('recoveryCodes')).size());

        res = VkfTestData.call('GET', '/vkf/v1/profile/security', null, token);
        VkfProfileResource.get();
        Map<String, Object> overview = VkfTestData.json(res);
        Assert.isTrue((Boolean) ((Map<String, Object>) overview.get('mfa')).get('enabled'));
        Assert.areEqual(1, overview.get('activeSessions'));

        res = VkfTestData.call('POST', '/vkf/v1/auth/login', '{"username":"membera",' + password.replace('currentPassword', 'password') + '}', null);
        VkfAuthResource.post();
        String challenge = (String) VkfTestData.json(res).get('challenge');
        Assert.isNull(VkfTestData.json(res).get('token'));
        res = VkfTestData.call('POST', '/vkf/v1/auth/mfa', '{"challenge":"' + challenge + '","code":"000000"}', null);
        VkfAuthResource.post();
        Assert.areEqual(422, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/auth/mfa', '{"challenge":"' + challenge + '","code":"' + nextCode(userId) + '"}', null);
        VkfAuthResource.post();
        Assert.areEqual(200, res.statusCode);
        String newToken = (String) VkfTestData.json(res).get('token');

        res = VkfTestData.call('POST', '/vkf/v1/profile/mfa/recovery-codes', '{' + password + ',"code":"' + nextCode(userId) + '"}', newToken);
        VkfProfileResource.post();
        Assert.areEqual(200, res.statusCode, '' + res.responseBody?.toString());

        res = VkfTestData.call('POST', '/vkf/v1/profile/mfa/nothing', '{}', newToken);
        VkfProfileResource.post();
        Assert.areEqual(404, res.statusCode);

        res = VkfTestData.call('POST', '/vkf/v1/family/members/' + userId + '/reset-mfa', '{' + password + '}', VkfTestData.login('admina'));
        VkfFamilyResource.post();
        Assert.areEqual(204, res.statusCode, '' + res.responseBody?.toString());

        res = VkfTestData.call('POST', '/vkf/v1/profile/mfa/disable', '{' + password + '}', VkfTestData.login('membera'));
        VkfProfileResource.post();
        Assert.areEqual(422, res.statusCode, 'Already off');
    }

    // ---------------------------------------------------------------- helpers

    /** Turns two-step on for a member; the test clock moves on so later codes aren't replays. */
    private static Id enrol(String username) {
        UserContext ctx = VkfTestData.ctx(username);
        MfaService.beginSetup(ctx, VkfTestData.PASSWORD);
        MfaService.confirmSetup(ctx, nextCode(ctx.userId));
        return ctx.userId;
    }

    /** The code for the next 30-second window. */
    private static String nextCode(Id userId) {
        MfaService.clockSeconds += 30;
        return MfaService.codeAt(secretOf(userId), MfaService.currentStep());
    }

    private static String secretOf(Id userId) {
        return [SELECT MFA_Secret__c FROM Portal_User__c WHERE Id = :userId WITH SYSTEM_MODE].MFA_Secret__c;
    }

    private static Id openChallengeId(Id userId) {
        return [SELECT Id FROM Auth_Token__c WHERE Portal_User__c = :userId AND Type__c = 'MFA Challenge' AND Used_At__c = NULL WITH SYSTEM_MODE LIMIT 1].Id;
    }

    private static String sessionStatus(String token) {
        String tokenHash = TokenService.hash(token);
        return [SELECT Status__c FROM Portal_Session__c WHERE Token_Hash__c = :tokenHash WITH SYSTEM_MODE].Status__c;
    }

    // Each helper returns the PortalException code, or OK when the call succeeds.

    private static String loginError(String username, String password) {
        try {
            AuthService.login(username, password, VkfTestData.UA);
            return 'OK';
        } catch (PortalException e) {
            return e.code();
        }
    }

    private static String completeError(String challenge, String code) {
        try {
            AuthService.completeMfa(challenge, code, VkfTestData.UA);
            return 'OK';
        } catch (PortalException e) {
            return e.code();
        }
    }

    private static String setupError(UserContext ctx, String password) {
        try {
            MfaService.beginSetup(ctx, password);
            return 'OK';
        } catch (PortalException e) {
            return e.code();
        }
    }

    private static String confirmError(UserContext ctx, String code) {
        try {
            MfaService.confirmSetup(ctx, code);
            return 'OK';
        } catch (PortalException e) {
            return e.code();
        }
    }

    private static String stepUpError(UserContext ctx, String password, String code) {
        try {
            AuthService.requireStepUp(ctx, password, code);
            return 'OK';
        } catch (PortalException e) {
            return e.code();
        }
    }

    private static String disableError(UserContext ctx, String password, String code) {
        try {
            MfaService.disable(ctx, password, code);
            return 'OK';
        } catch (PortalException e) {
            return e.code();
        }
    }

    private static String resetMfaError(UserContext ctx, Id memberId, String code) {
        try {
            MemberService.resetMemberMfa(ctx, memberId, VkfTestData.PASSWORD, code);
            return 'OK';
        } catch (PortalException e) {
            return e.code();
        }
    }
}
