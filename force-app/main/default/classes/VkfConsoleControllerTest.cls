@IsTest
private class VkfConsoleControllerTest {
    private static User newUser(String profileName, Boolean platformAdmin) {
        User u = new User(
            Alias = 'vkftest',
            Email = 'vkf.console@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Console',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName WITH SYSTEM_MODE].Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'vkf.console.' + Datetime.now().getTime() + '@example.test'
        );
        insert as system u;
        if (platformAdmin) {
            insert as system new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'VKF_Platform_Admin' WITH SYSTEM_MODE].Id
            );
        }
        return u;
    }

    @IsTest
    static void onboardsFamilyWithTemporaryAdminPassword() {
        System.runAs(newUser('System Administrator', true)) {
            VkfTestData.fastPolicy();
            FamilyOnboardingService.Result r = VkfConsoleController.onboardFamily(
                'Sharma Family', null, null, 6, 'Anil', 'Sharma', 'Anil.Sharma', 'anil@example.test'
            );
            Assert.areEqual('anil.sharma', r.username);
            Assert.isTrue(r.familyCode.startsWith('FAM-'), r.familyCode);
            Assert.areEqual(12, r.temporaryPassword.length());
            Portal_User__c admin = [
                SELECT Role__c, Status__c, Relationship__c, Family__r.Max_Members__c, Family__r.Base_Currency__c
                FROM Portal_User__c
                WHERE Id = :r.adminId WITH SYSTEM_MODE
            ];
            Assert.areEqual('Family Admin', admin.Role__c);
            Assert.areEqual('Invited', admin.Status__c);
            Assert.areEqual('Self', admin.Relationship__c);
            Assert.areEqual(6, admin.Family__r.Max_Members__c);
            Assert.areEqual('INR', admin.Family__r.Base_Currency__c);

            try {
                VkfConsoleController.onboardFamily('Second Family', 'usd', 'UTC', null, 'X', 'Y', 'anil.sharma', null);
                Assert.fail('Duplicate username');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('taken'), e.getMessage());
            }
            Assert.areEqual(1, [SELECT COUNT() FROM Family__c WITH SYSTEM_MODE], 'Failed onboarding rolls back the family');

            Assert.areEqual(12, VkfConsoleController.resetPortalPassword('anil.sharma').length());
            try {
                VkfConsoleController.resetPortalPassword('no.such.user');
                Assert.fail('Unknown user');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('No portal user'));
            }
            try {
                VkfConsoleController.onboardFamily(' ', null, null, null, 'X', 'Y', 'someone', null);
                Assert.fail('Blank family name');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Family name'));
            }
        }
    }

    @IsTest
    static void requiresPlatformAdminPermission() {
        System.runAs(newUser('Standard User', false)) {
            try {
                VkfConsoleController.onboardFamily('Family', null, null, null, 'A', 'B', 'abcd', null);
                Assert.fail('Permission required');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('VKF Platform Admin'));
            }
        }
    }
}
