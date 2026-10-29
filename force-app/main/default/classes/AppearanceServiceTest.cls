@IsTest
private class AppearanceServiceTest {
    private static final String CUSTOM_BRAND = '#7C3AED';

    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    private static String loginViaRest(String username) {
        RestResponse res = VkfTestData.call(
            'POST', '/vkf/v1/auth/login',
            JSON.serialize(new Map<String, Object>{ 'username' => username, 'password' => VkfTestData.PASSWORD }), null
        );
        VkfAuthResource.post();
        return (String) VkfTestData.json(res).get('token');
    }

    @IsTest
    static void personalThemeIsCleanedSavedAndReset() {
        UserContext member = VkfTestData.ctx('membera');
        Test.startTest();
        PortalDtos.Appearance saved = AppearanceService.savePersonal(member, new Map<String, Object>{
            'preset' => 'custom', 'brand' => CUSTOM_BRAND, 'mode' => 'dark', 'text' => 'large', 'unknown' => 'dropped'
        });
        Test.stopTest();

        Assert.areEqual('custom', saved.personal.get('preset'));
        Assert.areEqual(CUSTOM_BRAND.toLowerCase(), saved.personal.get('brand'), 'colours are stored in lower case');
        Assert.areEqual('dark', saved.personal.get('mode'));
        Assert.areEqual('large', saved.personal.get('text'));
        Assert.areEqual('default', saved.personal.get('radius'), 'missing choices fall back to defaults');
        Assert.isFalse(saved.personal.containsKey('unknown'), 'only known keys are saved');
        Assert.isNull(saved.family, 'no family theme yet');

        PortalDtos.Appearance reset = AppearanceService.savePersonal(member, null);
        Assert.isNull(reset.personal, 'reset goes back to the family theme');
        Assert.isNull([SELECT Theme__c FROM Portal_User__c WHERE Username__c = 'membera' WITH SYSTEM_MODE].Theme__c);
    }

    @IsTest
    static void personalThemeRejectsBadChoices() {
        UserContext member = VkfTestData.ctx('membera');
        List<Map<String, Object>> bad = new List<Map<String, Object>>{
            new Map<String, Object>{ 'mode' => 'dark' },
            new Map<String, Object>{ 'preset' => 'neon' },
            new Map<String, Object>{ 'preset' => 'custom' },
            new Map<String, Object>{ 'preset' => 'custom', 'brand' => 'red' },
            new Map<String, Object>{ 'preset' => 'custom', 'brand' => '#12345g' },
            new Map<String, Object>{ 'preset' => 'teal', 'mode' => 'dim' },
            new Map<String, Object>{ 'preset' => 'teal', 'radius' => 'pill' },
            new Map<String, Object>{ 'preset' => 'teal', 'text' => 'huge' }
        };
        Test.startTest();
        for (Map<String, Object> body : bad) {
            try {
                AppearanceService.savePersonal(member, body);
                Assert.fail('expected a validation error for ' + JSON.serialize(body));
            } catch (PortalException e) {
                Assert.areEqual('VALIDATION', e.code(), JSON.serialize(body));
            }
        }
        Test.stopTest();
        Assert.isNull([SELECT Theme__c FROM Portal_User__c WHERE Username__c = 'membera' WITH SYSTEM_MODE].Theme__c, 'nothing saved');
    }

    @IsTest
    static void familyThemeIsForAdminsAndCanLockColours() {
        UserContext coAdmin = VkfTestData.ctx('coadmina');
        UserContext member = VkfTestData.ctx('membera');
        Test.startTest();
        AppearanceService.saveFamily(coAdmin, new Map<String, Object>{ 'preset' => 'forest', 'radius' => 'round', 'locked' => true, 'mode' => 'dark' });
        Test.stopTest();

        PortalDtos.Appearance seen = AppearanceService.forUser(member);
        Assert.areEqual('forest', seen.family.get('preset'), 'members see the family theme');
        Assert.areEqual('round', seen.family.get('radius'));
        Assert.isTrue(seen.locked);
        Assert.isFalse(seen.family.containsKey('mode'), 'light or dark stays personal');

        PortalDtos.Appearance following = AppearanceService.savePersonal(member, new Map<String, Object>{
            'preset' => 'family', 'mode' => 'dark', 'brand' => CUSTOM_BRAND
        });
        Assert.areEqual('family', following.personal.get('preset'), 'members can keep following the family colours');
        Assert.areEqual('dark', following.personal.get('mode'));
        Assert.isFalse(following.personal.containsKey('brand'), 'no colours are stored when following the family');

        try {
            AppearanceService.saveFamily(member, new Map<String, Object>{ 'preset' => 'berry' });
            Assert.fail('members cannot change the family theme');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        Assert.isNull(AppearanceService.forUser(VkfTestData.ctx('memberb')).family, 'another family is untouched');

        PortalDtos.Appearance reset = AppearanceService.saveFamily(coAdmin, null);
        Assert.isNull(reset.family);
        Assert.isFalse(reset.locked);
    }

    @IsTest
    static void unreadableStoredThemeIsIgnored() {
        Portal_User__c u = [SELECT Id FROM Portal_User__c WHERE Username__c = 'membera' WITH SYSTEM_MODE];
        update as system new Portal_User__c(Id = u.Id, Theme__c = '{not json');
        Test.startTest();
        PortalDtos.Appearance seen = AppearanceService.forUser(VkfTestData.ctx('membera'));
        Test.stopTest();
        Assert.isNull(seen.personal, 'a damaged value never breaks sign-in');
    }

    @IsTest
    static void restEndpointsSaveAndResetThemes() {
        VkfTestData.fastPolicy();
        String adminToken = loginViaRest('admina');
        String memberToken = loginViaRest('membera');
        Test.startTest();
        RestResponse res = VkfTestData.call('PUT', '/vkf/v1/profile/appearance', '{"preset":"ocean","mode":"light"}', memberToken);
        VkfProfileResource.put();
        Assert.areEqual(200, res.statusCode);
        Assert.areEqual('ocean', ((Map<String, Object>) VkfTestData.json(res).get('personal')).get('preset'));

        res = VkfTestData.call('GET', '/vkf/v1/profile/me', null, memberToken);
        VkfProfileResource.get();
        Map<String, Object> appearance = (Map<String, Object>) VkfTestData.json(res).get('appearance');
        Assert.areEqual('ocean', ((Map<String, Object>) appearance.get('personal')).get('preset'), 'the profile carries the theme');

        res = VkfTestData.call('DELETE', '/vkf/v1/profile/appearance', null, memberToken);
        VkfProfileResource.del();
        Assert.areEqual(200, res.statusCode);
        Assert.isNull(VkfTestData.json(res).get('personal'));

        res = VkfTestData.call('PUT', '/vkf/v1/family/appearance', '{"preset":"gold"}', memberToken);
        VkfFamilyResource.put();
        Assert.areEqual(403, res.statusCode, 'members cannot set the family theme');

        res = VkfTestData.call('PUT', '/vkf/v1/family/appearance', '{"preset":"gold","locked":true}', adminToken);
        VkfFamilyResource.put();
        Assert.areEqual(200, res.statusCode);
        Assert.areEqual(true, VkfTestData.json(res).get('locked'));

        res = VkfTestData.call('DELETE', '/vkf/v1/family/appearance', null, adminToken);
        VkfFamilyResource.del();
        Assert.areEqual(200, res.statusCode);

        res = VkfTestData.call('PUT', '/vkf/v1/profile/sessions', '{}', memberToken);
        VkfProfileResource.put();
        Assert.areEqual(404, res.statusCode);
        Test.stopTest();
    }
}
