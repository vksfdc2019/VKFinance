@IsTest
private class AuthServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.fastPolicy();
        Family__c f = VkfTestData.family('Auth Family');
        VkfTestData.member(f.Id, 'authuser', 'Member');
        VkfTestData.member(f.Id, 'authadmin', 'Family Admin');
    }

    @IsTest
    static void loginReturnsTokenAndProfile() {
        VkfTestData.fastPolicy();
        AuthService.LoginResult r = AuthService.login('  AuthUser ', VkfTestData.PASSWORD, VkfTestData.UA);
        Assert.isNotNull(r.token);
        Assert.isFalse(r.mustChangePassword);
        Assert.areEqual('authuser', r.profile.username);
        Assert.areEqual('Auth Family', r.profile.familyName);
        Assert.areEqual(30, r.profile.idleTimeoutMinutes);
        Assert.isNotNull([SELECT Last_Login__c FROM Portal_User__c WHERE Username__c = 'authuser' WITH SYSTEM_MODE].Last_Login__c);
    }

    @IsTest
    static void unknownUserAndBlankInput() {
        VkfTestData.fastPolicy();
        expect('INVALID_CREDENTIALS', 'nobody', 'Whatever#123');
        expect('VALIDATION', '', '');
    }

    @IsTest
    static void wrongPasswordLocksAfterFiveAttempts() {
        VkfTestData.fastPolicy();
        for (Integer i = 0; i < 5; i++) {
            expect('INVALID_CREDENTIALS', 'authuser', 'Wrong#Password1');
        }
        Portal_User__c u = [SELECT Locked_Until__c, Lockout_Count__c FROM Portal_User__c WHERE Username__c = 'authuser' WITH SYSTEM_MODE];
        Assert.isTrue(u.Locked_Until__c > Datetime.now());
        Assert.areEqual(1, u.Lockout_Count__c);
        expect('LOCKED', 'authuser', VkfTestData.PASSWORD);
    }

    @IsTest
    static void throttlesAfterTooManyAttempts() {
        VkfTestData.fastPolicy(100, 10);
        for (Integer i = 0; i < 10; i++) {
            expect('INVALID_CREDENTIALS', 'authuser', 'Wrong#Password1');
        }
        expect('THROTTLED', 'authuser', VkfTestData.PASSWORD);
    }

    @IsTest
    static void inactiveMemberOrSuspendedFamilyCannotSignIn() {
        VkfTestData.fastPolicy();
        Portal_User__c u = [SELECT Id, Family__c FROM Portal_User__c WHERE Username__c = 'authuser' WITH SYSTEM_MODE];
        update as system new Portal_User__c(Id = u.Id, Status__c = 'Disabled');
        expect('INVALID_CREDENTIALS', 'authuser', VkfTestData.PASSWORD);
        update as system new Portal_User__c(Id = u.Id, Status__c = 'Active');
        update as system new Family__c(Id = u.Family__c, Status__c = 'Suspended');
        expect('INVALID_CREDENTIALS', 'authuser', VkfTestData.PASSWORD);
    }

    @IsTest
    static void temporaryPasswordMustBeReplaced() {
        VkfTestData.fastPolicy();
        Family__c f = [SELECT Id FROM Family__c WITH SYSTEM_MODE LIMIT 1];
        MemberService.MemberInput input = new MemberService.MemberInput();
        input.firstName = 'Kiran';
        input.lastName = 'Rao';
        input.username = 'kiran.rao';
        input.role = 'Member';
        MemberService.Created created = MemberService.insertMember(f.Id, input);

        AuthService.LoginResult first = AuthService.login('kiran.rao', created.temporaryPassword, VkfTestData.UA);
        Assert.isTrue(first.mustChangePassword);
        UserContext restricted = SessionService.require(first.token, VkfTestData.UA, true);
        try {
            AuthService.firstLogin(restricted, 'weak', VkfTestData.UA);
            Assert.fail('Weak password must fail');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        AuthService.LoginResult full = AuthService.firstLogin(restricted, 'Green#Valley2026', VkfTestData.UA);
        Assert.isFalse(full.mustChangePassword);
        Assert.areEqual('Active', [SELECT Status__c FROM Portal_User__c WHERE Username__c = 'kiran.rao' WITH SYSTEM_MODE].Status__c);
        try {
            SessionService.require(first.token, VkfTestData.UA, true);
            Assert.fail('The restricted session ends after the password is set');
        } catch (PortalException e) {
            Assert.areEqual('SESSION_EXPIRED', e.code());
        }
        Assert.isNotNull(SessionService.require(full.token, VkfTestData.UA));
        try {
            AuthService.firstLogin(SessionService.require(full.token, VkfTestData.UA), 'Other#Valley2026', VkfTestData.UA);
            Assert.fail('Already set');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
    }

    @IsTest
    static void expiredTemporaryPasswordIsRejected() {
        VkfTestData.fastPolicy();
        Portal_User__c u = [SELECT Id FROM Portal_User__c WHERE Username__c = 'authuser' WITH SYSTEM_MODE];
        update as system new Portal_User__c(Id = u.Id, Must_Change_Password__c = true, Temp_Password_Expires_At__c = Datetime.now().addHours(-1));
        expect('INVALID_CREDENTIALS', 'authuser', VkfTestData.PASSWORD);
    }

    @IsTest
    static void changePasswordSignsOutOtherDevices() {
        VkfTestData.fastPolicy();
        String mine = VkfTestData.login('authuser');
        UserContext ctx = SessionService.require(mine, VkfTestData.UA);
        String other = VkfTestData.login('authuser');
        try {
            AuthService.changePassword(ctx, 'Wrong#Current1', 'River#Stone2026');
            Assert.fail('Wrong current password');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        try {
            AuthService.changePassword(ctx, VkfTestData.PASSWORD, VkfTestData.PASSWORD);
            Assert.fail('Same password');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        AuthService.changePassword(ctx, VkfTestData.PASSWORD, 'River#Stone2026');
        Assert.isNotNull(SessionService.require(mine, VkfTestData.UA));
        try {
            SessionService.require(other, VkfTestData.UA);
            Assert.fail('Other device must be signed out');
        } catch (PortalException e) {
            Assert.areEqual('SESSION_EXPIRED', e.code());
        }
        Assert.isNotNull(AuthService.login('authuser', 'River#Stone2026', VkfTestData.UA).token);
    }

    @IsTest
    static void forgotAndResetPassword() {
        VkfTestData.fastPolicy();
        AuthService.forgot('nobody-here');
        Assert.isNull(AuthService.lastIssuedResetToken);
        AuthService.forgot('AuthUser@Example.test');
        String token = AuthService.lastIssuedResetToken;
        Assert.isNotNull(token);
        String session = VkfTestData.login('authuser');

        AuthService.reset(token, 'Maple#Leaf2026');
        try {
            AuthService.reset(token, 'Another#Leaf2026');
            Assert.fail('A reset link works once');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        try {
            SessionService.require(session, VkfTestData.UA);
            Assert.fail('Reset signs out every device');
        } catch (PortalException e) {
            Assert.areEqual('SESSION_EXPIRED', e.code());
        }
        Assert.isNotNull(AuthService.login('authuser', 'Maple#Leaf2026', VkfTestData.UA).token);
        try {
            AuthService.forgot(' ');
            Assert.fail('Blank identifier');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
    }

    @IsTest
    static void newerResetLinkInvalidatesOlderOne() {
        VkfTestData.fastPolicy();
        AuthService.forgot('authuser');
        String first = AuthService.lastIssuedResetToken;
        AuthService.forgot('authuser');
        try {
            AuthService.reset(first, 'Maple#Leaf2026');
            Assert.fail('Older link is invalidated');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        AuthService.reset(AuthService.lastIssuedResetToken, 'Maple#Leaf2026');
    }

    @IsTest
    static void logoutEndsSessionAndStepUpChecksPassword() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('authadmin');
        UserContext ctx = SessionService.require(token, VkfTestData.UA);
        AuthService.requireStepUp(ctx, VkfTestData.PASSWORD);
        try {
            AuthService.requireStepUp(ctx, 'Wrong#Password1');
            Assert.fail('Wrong step-up password');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        AuthService.logout(ctx);
        Assert.areEqual('Logged Out', [SELECT Status__c FROM Portal_Session__c WHERE Id = :ctx.sessionId WITH SYSTEM_MODE].Status__c);
    }

    private static void expect(String code, String username, String password) {
        try {
            AuthService.login(username, password, VkfTestData.UA);
            Assert.fail('Expected ' + code);
        } catch (PortalException e) {
            Assert.areEqual(code, e.code());
        }
    }
}
