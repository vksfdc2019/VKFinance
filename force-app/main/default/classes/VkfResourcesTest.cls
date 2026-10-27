@IsTest
private class VkfResourcesTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    private static String loginViaRest(String username, String password) {
        RestResponse res = VkfTestData.call('POST', '/vkf/v1/auth/login', JSON.serialize(new Map<String, Object>{ 'username' => username, 'password' => password }), null);
        VkfAuthResource.post();
        return res.statusCode == 200 ? (String) VkfTestData.json(res).get('token') : null;
    }

    @IsTest
    static void loginAndSessionEndpoints() {
        VkfTestData.fastPolicy();
        String token = loginViaRest('admina', VkfTestData.PASSWORD);
        Assert.isNotNull(token);

        RestResponse res = VkfTestData.call('GET', '/vkf/v1/auth/session', null, token);
        VkfAuthResource.get();
        Assert.areEqual(200, res.statusCode);
        Assert.areEqual('Family Admin', VkfTestData.json(res).get('role'));

        res = VkfTestData.call('POST', '/vkf/v1/auth/login', '{"username":"admina","password":"Wrong#Password1"}', null);
        VkfAuthResource.post();
        Assert.areEqual(401, res.statusCode);
        Assert.areEqual('INVALID_CREDENTIALS', VkfTestData.code(res));
        Assert.areEqual(1, [SELECT Failed_Login_Count__c FROM Portal_User__c WHERE Username__c = 'admina' WITH SYSTEM_MODE].Failed_Login_Count__c);

        res = VkfTestData.call('GET', '/vkf/v1/auth/session', null, null);
        VkfAuthResource.get();
        Assert.areEqual(401, res.statusCode);

        res = VkfTestData.call('POST', '/vkf/v1/auth/logout', '{}', token);
        VkfAuthResource.post();
        Assert.areEqual(204, res.statusCode);
        res = VkfTestData.call('GET', '/vkf/v1/auth/session', null, token);
        VkfAuthResource.get();
        Assert.areEqual(401, res.statusCode);
    }

    @IsTest
    static void restrictedSessionMustSetPasswordFirst() {
        VkfTestData.fastPolicy();
        String adminToken = VkfTestData.login('admina');
        RestResponse res = VkfTestData.call(
            'POST',
            '/vkf/v1/family/members',
            '{"firstName":"Meera","lastName":"Tester","username":"meera","role":"Member","relationship":"Daughter"}',
            adminToken
        );
        VkfFamilyResource.post();
        Assert.areEqual(201, res.statusCode);
        String temp = (String) VkfTestData.json(res).get('temporaryPassword');

        String restricted = loginViaRest('meera', temp);
        res = VkfTestData.call('GET', '/vkf/v1/family/members', null, restricted);
        VkfFamilyResource.get();
        Assert.areEqual(403, res.statusCode);
        Assert.areEqual('PASSWORD_CHANGE_REQUIRED', VkfTestData.code(res));

        res = VkfTestData.call('POST', '/vkf/v1/auth/first-login', '{"newPassword":"Sunny#Garden2026"}', restricted);
        VkfAuthResource.post();
        Assert.areEqual(200, res.statusCode);
        String full = (String) VkfTestData.json(res).get('token');
        res = VkfTestData.call('GET', '/vkf/v1/family/members', null, full);
        VkfFamilyResource.get();
        Assert.areEqual(200, res.statusCode);
    }

    @IsTest
    static void profileAndDeviceEndpoints() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('membera');
        VkfTestData.login('membera');

        RestResponse res = VkfTestData.call('GET', '/vkf/v1/profile/me', null, token);
        VkfProfileResource.get();
        Assert.areEqual('membera', VkfTestData.json(res).get('username'));

        res = VkfTestData.call('GET', '/vkf/v1/profile/sessions', null, token);
        VkfProfileResource.get();
        List<Object> sessions = (List<Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Assert.areEqual(2, sessions.size());

        res = VkfTestData.call('DELETE', '/vkf/v1/profile/sessions', null, token);
        VkfProfileResource.del();
        Assert.areEqual(1, VkfTestData.json(res).get('revoked'));

        res = VkfTestData.call('DELETE', '/vkf/v1/profile/sessions/not-an-id', null, token);
        VkfProfileResource.del();
        Assert.areEqual(404, res.statusCode);

        res = VkfTestData.call('GET', '/vkf/v1/profile/unknown', null, token);
        VkfProfileResource.get();
        Assert.areEqual(404, res.statusCode);
    }

    @IsTest
    static void passwordEndpoints() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('membera');
        RestResponse res = VkfTestData.call('PUT', '/vkf/v1/auth/password', '{"currentPassword":"Wrong#Password1","newPassword":"Cloud#Forest2026"}', token);
        VkfAuthResource.put();
        Assert.areEqual(422, res.statusCode);
        res = VkfTestData.call('PUT', '/vkf/v1/auth/password', JSON.serialize(new Map<String, Object>{ 'currentPassword' => VkfTestData.PASSWORD, 'newPassword' => 'Cloud#Forest2026' }), token);
        VkfAuthResource.put();
        Assert.areEqual(200, res.statusCode);

        res = VkfTestData.call('POST', '/vkf/v1/auth/forgot', '{"identifier":"membera"}', null);
        VkfAuthResource.post();
        Assert.areEqual(200, res.statusCode);
        Assert.areEqual(AuthService.GENERIC_RESET_MESSAGE, VkfTestData.json(res).get('message'));

        res = VkfTestData.call('POST', '/vkf/v1/auth/reset', JSON.serialize(new Map<String, Object>{ 'token' => AuthService.lastIssuedResetToken, 'newPassword' => 'Silver#Moon2026' }), null);
        VkfAuthResource.post();
        Assert.areEqual(200, res.statusCode);

        res = VkfTestData.call('POST', '/vkf/v1/auth/reset', '{"token":"bogus","newPassword":"Silver#Moon2026"}', null);
        VkfAuthResource.post();
        Assert.areEqual(422, res.statusCode);
    }

    @IsTest
    static void familyMemberEndpoints() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('admina');
        Id memberId = VkfTestData.userId('membera');

        RestResponse res = VkfTestData.call('PATCH', '/vkf/v1/family/members/' + memberId, '{"firstName":"Renamed"}', token);
        VkfFamilyResource.patch();
        Assert.areEqual(200, res.statusCode);
        Assert.areEqual('Renamed', VkfTestData.json(res).get('firstName'));

        res = VkfTestData.call('POST', '/vkf/v1/family/members/' + memberId + '/unlock', '{}', token);
        VkfFamilyResource.post();
        Assert.areEqual(204, res.statusCode);

        res = VkfTestData.call('POST', '/vkf/v1/family/members/' + memberId + '/reset-password', JSON.serialize(new Map<String, Object>{ 'currentPassword' => VkfTestData.PASSWORD }), token);
        VkfFamilyResource.post();
        Assert.areEqual(200, res.statusCode);
        Assert.isNotNull(VkfTestData.json(res).get('temporaryPassword'));

        res = VkfTestData.call('DELETE', '/vkf/v1/family/members/' + memberId + '/sessions', null, token);
        VkfFamilyResource.del();
        Assert.areEqual(200, res.statusCode);

        res = VkfTestData.call('POST', '/vkf/v1/family/members', '{"firstName":""}', token);
        VkfFamilyResource.post();
        Assert.areEqual(422, res.statusCode);
    }

    @IsTest
    static void unknownRoutesAndBadBodies() {
        VkfTestData.fastPolicy();
        String token = VkfTestData.login('admina');
        RestResponse res = VkfTestData.call('POST', '/vkf/v1/auth/nope', '{}', null);
        VkfAuthResource.post();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('GET', '/vkf/v1/auth/nope', null, token);
        VkfAuthResource.get();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('PUT', '/vkf/v1/auth/nope', '{}', token);
        VkfAuthResource.put();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('GET', '/vkf/v1/family/nope', null, token);
        VkfFamilyResource.get();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/family/nope', '{}', token);
        VkfFamilyResource.post();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('PATCH', '/vkf/v1/family/nope', '{}', token);
        VkfFamilyResource.patch();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('DELETE', '/vkf/v1/family/nope', null, token);
        VkfFamilyResource.del();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('DELETE', '/vkf/v1/profile/nope', null, token);
        VkfProfileResource.del();
        Assert.areEqual(404, res.statusCode);
        res = VkfTestData.call('POST', '/vkf/v1/auth/login', 'not json', null);
        VkfAuthResource.post();
        Assert.areEqual(400, res.statusCode);
    }

    @IsTest
    static void deviceNames() {
        Assert.areEqual('Unknown device', PortalDtos.describeDevice(null));
        Assert.areEqual('Chrome on Windows', PortalDtos.describeDevice(VkfTestData.UA));
        Assert.areEqual('Safari on iOS', PortalDtos.describeDevice('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0) Safari/604.1'));
        Assert.areEqual('Edge on Windows', PortalDtos.describeDevice('Mozilla/5.0 (Windows NT 10.0) Chrome/130 Edg/130'));
        Assert.areEqual('Firefox on Linux', PortalDtos.describeDevice('Mozilla/5.0 (X11; Linux x86_64) Firefox/131.0'));
    }
}
