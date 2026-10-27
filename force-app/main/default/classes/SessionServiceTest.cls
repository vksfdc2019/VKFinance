@IsTest
private class SessionServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.fastPolicy();
        Family__c f = VkfTestData.family('Sessions');
        VkfTestData.member(f.Id, 'sessuser', 'Member');
    }

    @IsTest
    static void storesOnlyTheTokenHash() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('sessuser');
        UserContext ctx = SessionService.require(token, VkfTestData.UA);
        Assert.areEqual('sessuser', ctx.username);
        Assert.areEqual(SessionService.SCOPE_FULL, ctx.scope);
        Portal_Session__c s = [SELECT Token_Hash__c FROM Portal_Session__c WHERE Id = :ctx.sessionId WITH SYSTEM_MODE];
        Assert.areNotEqual(token, s.Token_Hash__c);
        Assert.areEqual(TokenService.hash(token), s.Token_Hash__c);
    }

    @IsTest
    static void rejectsMissingUnknownIdleExpiredRevokedAndOtherBrowser() {
        VkfTestData.fastPolicy();
        assertExpired(null, VkfTestData.UA);
        assertExpired('not-a-real-token', VkfTestData.UA);
        String token = VkfTestData.login('sessuser');
        assertExpired(token, 'Some Other Browser/1.0');
        Portal_Session__c s = [SELECT Id FROM Portal_Session__c WHERE Token_Hash__c = :TokenService.hash(token) WITH SYSTEM_MODE];
        s.Last_Activity__c = Datetime.now().addMinutes(-31);
        update as system s;
        assertExpired(token, VkfTestData.UA);
        s.Last_Activity__c = Datetime.now();
        s.Expires_At__c = Datetime.now().addMinutes(-1);
        update as system s;
        assertExpired(token, VkfTestData.UA);
        s.Expires_At__c = Datetime.now().addHours(1);
        s.Status__c = 'Revoked';
        update as system s;
        assertExpired(token, VkfTestData.UA);
    }

    @IsTest
    static void disabledMemberOrSuspendedFamilyEndsSessions() {
        VkfTestData.fastPolicy();
        Portal_User__c u = [SELECT Id, Family__c FROM Portal_User__c WHERE Username__c = 'sessuser' WITH SYSTEM_MODE];
        String token = VkfTestData.login('sessuser');
        update as system new Family__c(Id = u.Family__c, Status__c = 'Suspended');
        assertExpired(token, VkfTestData.UA);
        update as system new Family__c(Id = u.Family__c, Status__c = 'Active');
        Assert.isNotNull(SessionService.require(token, VkfTestData.UA));
        update as system new Portal_User__c(Id = u.Id, Status__c = 'Disabled');
        assertExpired(token, VkfTestData.UA);
    }

    @IsTest
    static void restrictedScopeOnlyWhereAllowed() {
        VkfTestData.fastPolicy();
        Portal_User__c u = [SELECT Id, Family__c FROM Portal_User__c WHERE Username__c = 'sessuser' WITH SYSTEM_MODE];
        SessionService.NewSession s = SessionService.create(u, SessionService.SCOPE_CHANGE_PASSWORD, VkfTestData.UA);
        try {
            SessionService.require(s.token, VkfTestData.UA);
            Assert.fail('Restricted session must not reach full endpoints');
        } catch (PortalException e) {
            Assert.areEqual('PASSWORD_CHANGE_REQUIRED', e.code());
            Assert.areEqual(403, e.httpStatus());
        }
        Assert.isNotNull(SessionService.require(s.token, VkfTestData.UA, true));
    }

    @IsTest
    static void sessionLimitRevokesOldest() {
        VkfTestData.fastPolicy();
        for (Integer i = 0; i < 4; i++) {
            VkfTestData.login('sessuser');
        }
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Portal_Session__c WHERE Portal_User__r.Username__c = 'sessuser' AND Status__c = 'Active' WITH SYSTEM_MODE]
        );
    }

    @IsTest
    static void revokeOwnAndCleanup() {
        VkfTestData.fastPolicy();
        UserContext ctx = VkfTestData.ctx('sessuser');
        String other = VkfTestData.login('sessuser');
        Id otherId = [SELECT Id FROM Portal_Session__c WHERE Token_Hash__c = :TokenService.hash(other) WITH SYSTEM_MODE].Id;
        Assert.areEqual(2, SessionService.activeForUser(ctx.userId).size());
        SessionService.revokeOwn(ctx, otherId);
        assertExpired(other, VkfTestData.UA);
        try {
            SessionService.revokeOwn(ctx, otherId);
            Assert.fail('Already ended');
        } catch (PortalException e) {
            Assert.areEqual('NOT_FOUND', e.code());
        }

        update as system new Portal_Session__c(Id = ctx.sessionId, Last_Activity__c = Datetime.now().addHours(-2));
        Test.startTest();
        new SessionCleanupJob().execute(null);
        Test.stopTest();
        Assert.areEqual('Expired', [SELECT Status__c FROM Portal_Session__c WHERE Id = :ctx.sessionId WITH SYSTEM_MODE].Status__c);

        update as system new Portal_Session__c(Id = ctx.sessionId, Ended_At__c = Datetime.now().addDays(-10));
        SessionService.cleanup();
        Assert.areEqual(0, [SELECT COUNT() FROM Portal_Session__c WHERE Id = :ctx.sessionId WITH SYSTEM_MODE]);
    }

    private static void assertExpired(String token, String userAgent) {
        try {
            SessionService.require(token, userAgent);
            Assert.fail('Expected SESSION_EXPIRED');
        } catch (PortalException e) {
            Assert.areEqual('SESSION_EXPIRED', e.code());
        }
    }
}
