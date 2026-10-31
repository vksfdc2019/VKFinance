@IsTest
private class PasswordServiceTest {
    @IsTest
    static void hashIsSaltedAndVerifiable() {
        String salt = PasswordService.newSalt();
        String hashed = PasswordService.hash('Secret#123abc', salt, 3);
        Assert.areEqual(hashed, PasswordService.hash('Secret#123abc', salt, 3));
        Assert.areNotEqual(hashed, PasswordService.hash('Secret#123abc', PasswordService.newSalt(), 3));
        Assert.isTrue(PasswordService.matches('Secret#123abc', salt, 3, hashed));
        Assert.isFalse(PasswordService.matches('secret#123abc', salt, 3, hashed));
        Assert.isFalse(PasswordService.matches(null, salt, 3, hashed));
        Assert.isFalse(PasswordService.matches('Secret#123abc', salt, 4, hashed));
    }

    @IsTest
    static void policyRules() {
        VkfTestData.fastPolicy();
        Portal_User__c u = new Portal_User__c(Role__c = 'Member', Username__c = 'ravi', First_Name__c = 'Ravi', Last_Name__c = 'Kumar');
        Assert.isFalse(PasswordService.policyErrors('Short1!', u).isEmpty(), 'too short');
        Assert.isFalse(PasswordService.policyErrors('alllowercaseletters', u).isEmpty(), 'one class');
        Assert.isFalse(PasswordService.policyErrors('Ravi#2026safe', u).isEmpty(), 'contains name');
        Assert.isFalse(PasswordService.policyErrors('Password@12345', u).isEmpty(), 'common word');
        Assert.isTrue(PasswordService.policyErrors('Blue#Harbour77', u).isEmpty());
        u.Role__c = 'Family Admin';
        Assert.isFalse(PasswordService.policyErrors('Blue#Harb77', u).isEmpty(), 'admins need 12');
    }

    @IsTest
    static void temporaryPasswordMeetsAdminPolicy() {
        VkfTestData.fastPolicy();
        Portal_User__c admin = new Portal_User__c(Role__c = 'Family Admin');
        for (Integer i = 0; i < 20; i++) {
            String temp = PasswordService.generateTemporaryPassword();
            Assert.areEqual(12, temp.length());
            Assert.isTrue(PasswordService.policyErrors(temp, admin).isEmpty(), temp);
        }
    }

    @IsTest
    static void historyBlocksReuseAndIsTrimmed() {
        VkfTestData.fastPolicy();
        Family__c f = VkfTestData.family('History');
        Portal_User__c u = VkfTestData.member(f.Id, 'histuser', 'Member');
        PasswordService.recordHistory(u);
        try {
            PasswordService.validateNew(u, VkfTestData.PASSWORD);
            Assert.fail('Reusing the current password must fail');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        for (Integer i = 0; i < 7; i++) {
            PasswordService.apply(u, 'Fresh#Pass' + i + 'xyz', false);
            update as system u;
            PasswordService.recordHistory(u);
        }
        Assert.areEqual(5, [SELECT COUNT() FROM Password_History__c WHERE Portal_User__c = :u.Id WITH SYSTEM_MODE]);
        try {
            PasswordService.validateNew(u, 'Fresh#Pass4xyz');
            Assert.fail('A password from history must fail');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        PasswordService.validateNew(u, 'Brand#NewOne99');
    }
}