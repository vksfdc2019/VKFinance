/**
 * Release gate: a member of one family must never read or change another family's
 * records, whatever Id or payload they send. Covers the service and REST layers.
 */
@IsTest
private class FamilyIsolationTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    @IsTest
    static void listingShowsOnlyOwnFamily() {
        VkfTestData.fastPolicy();
        Id familyB = [SELECT Family__c FROM Portal_User__c WHERE Username__c = 'adminb' WITH SYSTEM_MODE].Family__c;
        List<PortalDtos.Member> members = MemberService.listMembers(VkfTestData.ctx('adminb'));
        Assert.areEqual(2, members.size());
        for (PortalDtos.Member m : members) {
            Assert.areEqual(familyB, [SELECT Family__c FROM Portal_User__c WHERE Id = :m.id WITH SYSTEM_MODE].Family__c);
        }
    }

    @IsTest
    static void otherFamilyIdsAreNotFoundInEveryServiceAction() {
        VkfTestData.fastPolicy();
        UserContext adminB = VkfTestData.ctx('adminb');
        Id memberA = VkfTestData.userId('membera');
        Portal_User__c before = [SELECT Role__c, Status__c, Locked_Until__c FROM Portal_User__c WHERE Id = :memberA WITH SYSTEM_MODE];

        expectNotFound(adminB, memberA, 'update');
        expectNotFound(adminB, memberA, 'unlock');
        expectNotFound(adminB, memberA, 'reset');
        expectNotFound(adminB, memberA, 'revoke');

        Portal_User__c after = [SELECT Role__c, Status__c, Locked_Until__c FROM Portal_User__c WHERE Id = :memberA WITH SYSTEM_MODE];
        Assert.areEqual(before.Role__c, after.Role__c);
        Assert.areEqual(before.Status__c, after.Status__c);
    }

    @IsTest
    static void restLayerHidesOtherFamilyRecords() {
        VkfTestData.fastPolicy();
        String tokenB = VkfTestData.login('adminb');
        Id memberA = VkfTestData.userId('membera');

        RestResponse res = VkfTestData.call('PATCH', '/vkf/v1/family/members/' + memberA, '{"role":"Viewer","currentPassword":"' + VkfTestData.PASSWORD + '"}', tokenB);
        VkfFamilyResource.patch();
        Assert.areEqual(404, res.statusCode);

        res = VkfTestData.call('POST', '/vkf/v1/family/members/' + memberA + '/unlock', '{}', tokenB);
        VkfFamilyResource.post();
        Assert.areEqual(404, res.statusCode);

        res = VkfTestData.call('POST', '/vkf/v1/family/members/' + memberA + '/reset-password', '{"currentPassword":"' + VkfTestData.PASSWORD + '"}', tokenB);
        VkfFamilyResource.post();
        Assert.areEqual(404, res.statusCode);

        res = VkfTestData.call('DELETE', '/vkf/v1/family/members/' + memberA + '/sessions', null, tokenB);
        VkfFamilyResource.del();
        Assert.areEqual(404, res.statusCode);

        res = VkfTestData.call('GET', '/vkf/v1/family/members', null, tokenB);
        VkfFamilyResource.get();
        Assert.areEqual(200, res.statusCode);
        Assert.isFalse(res.responseBody.toString().contains('membera'));
    }

    @IsTest
    static void cannotEndAnotherMembersSession() {
        VkfTestData.fastPolicy();
        String tokenA = VkfTestData.login('membera');
        Id sessionA = [SELECT Id FROM Portal_Session__c WHERE Token_Hash__c = :TokenService.hash(tokenA) WITH SYSTEM_MODE].Id;
        RestResponse res = VkfTestData.call('DELETE', '/vkf/v1/profile/sessions/' + sessionA, null, VkfTestData.login('adminb'));
        VkfProfileResource.del();
        Assert.areEqual(404, res.statusCode);
        Assert.isNotNull(SessionService.require(tokenA, VkfTestData.UA));
    }

    @IsTest
    static void payloadCannotChooseTheFamily() {
        VkfTestData.fastPolicy();
        Id familyA = [SELECT Family__c FROM Portal_User__c WHERE Username__c = 'admina' WITH SYSTEM_MODE].Family__c;
        Id familyB = [SELECT Family__c FROM Portal_User__c WHERE Username__c = 'adminb' WITH SYSTEM_MODE].Family__c;
        RestResponse res = VkfTestData.call(
            'POST',
            '/vkf/v1/family/members',
            '{"firstName":"Sneaky","lastName":"Member","username":"sneaky","familyId":"' + familyA + '","Family__c":"' + familyA + '"}',
            VkfTestData.login('adminb')
        );
        VkfFamilyResource.post();
        Assert.areEqual(201, res.statusCode);
        Assert.areEqual(familyB, [SELECT Family__c FROM Portal_User__c WHERE Username__c = 'sneaky' WITH SYSTEM_MODE].Family__c);
    }

    @IsTest
    static void sessionCarriesItsOwnFamily() {
        VkfTestData.fastPolicy();
        RestResponse res = VkfTestData.call('GET', '/vkf/v1/profile/me', null, VkfTestData.login('membera'));
        VkfProfileResource.get();
        Assert.areEqual('Family A', VkfTestData.json(res).get('familyName'));
    }

    private static void expectNotFound(UserContext ctx, Id target, String action) {
        try {
            if (action == 'update') {
                MemberService.updateMember(ctx, target, new Map<String, Object>{ 'firstName' => 'Hacked' });
            } else if (action == 'unlock') {
                MemberService.unlockMember(ctx, target);
            } else if (action == 'reset') {
                MemberService.resetMemberPassword(ctx, target, VkfTestData.PASSWORD);
            } else {
                MemberService.revokeMemberSessions(ctx, target);
            }
            Assert.fail(action + ' must not reach another family');
        } catch (PortalException e) {
            Assert.areEqual('NOT_FOUND', e.code(), action);
        }
    }
}
