@IsTest
private class MemberServiceTest {
    @TestSetup
    static void setup() {
        VkfTestData.twoFamilies();
    }

    private static Map<String, Object> body(Map<String, Object> values) {
        return values;
    }

    @IsTest
    static void adminsSeeTheFamilyOthersSeeThemselves() {
        VkfTestData.fastPolicy();
        Assert.areEqual(4, MemberService.listMembers(VkfTestData.ctx('admina')).size());
        Assert.areEqual(4, MemberService.listMembers(VkfTestData.ctx('coadmina')).size());
        List<PortalDtos.Member> own = MemberService.listMembers(VkfTestData.ctx('childa'));
        Assert.areEqual(1, own.size());
        Assert.isTrue(own[0].isSelf);
    }

    @IsTest
    static void createValidatesAndIssuesTemporaryPassword() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        MemberService.MemberInput bad = new MemberService.MemberInput(
            body(new Map<String, Object>{ 'firstName' => '', 'username' => 'X!', 'email' => 'not-an-email', 'role' => 'Boss' })
        );
        try {
            MemberService.createMember(admin, bad);
            Assert.fail('Invalid input');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
            Assert.isTrue(e.errors.size() >= 4, String.valueOf(e.errors));
        }
        MemberService.MemberInput duplicate = new MemberService.MemberInput(
            body(new Map<String, Object>{ 'firstName' => 'Dup', 'lastName' => 'User', 'username' => 'MemberA' })
        );
        try {
            MemberService.createMember(admin, duplicate);
            Assert.fail('Duplicate username');
        } catch (PortalException e) {
            Assert.isTrue(String.join(e.errors, ' ').contains('taken'));
        }
        MemberService.Created created = MemberService.createMember(
            admin,
            new MemberService.MemberInput(
                body(new Map<String, Object>{
                    'firstName' => 'Asha', 'lastName' => 'Tester', 'username' => 'asha.t', 'email' => 'ASHA@Example.test',
                    'role' => 'Child', 'relationship' => 'Daughter'
                })
            )
        );
        Assert.areEqual(12, created.temporaryPassword.length());
        Portal_User__c asha = [SELECT Status__c, Must_Change_Password__c, Email__c, Name FROM Portal_User__c WHERE Username__c = 'asha.t' WITH SYSTEM_MODE];
        Assert.areEqual('Invited', asha.Status__c);
        Assert.isTrue(asha.Must_Change_Password__c);
        Assert.areEqual('asha@example.test', asha.Email__c);
        Assert.areEqual('Asha Tester', asha.Name);
    }

    @IsTest
    static void createRespectsRolesAndMemberLimit() {
        VkfTestData.fastPolicy();
        MemberService.MemberInput newAdmin = new MemberService.MemberInput(
            body(new Map<String, Object>{ 'firstName' => 'New', 'lastName' => 'Admin', 'username' => 'newadmin', 'role' => 'Family Admin' })
        );
        try {
            MemberService.createMember(VkfTestData.ctx('coadmina'), newAdmin);
            Assert.fail('Co-Admin cannot create a Family Admin');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        try {
            MemberService.createMember(VkfTestData.ctx('membera'), newAdmin);
            Assert.fail('Member cannot create members');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        update as system new Family__c(Id = [SELECT Family__c FROM Portal_User__c WHERE Username__c = 'admina' WITH SYSTEM_MODE].Family__c, Max_Members__c = 4);
        try {
            MemberService.createMember(VkfTestData.ctx('admina'), newAdmin);
            Assert.fail('Member limit reached');
        } catch (PortalException e) {
            Assert.areEqual('CONFLICT', e.code());
        }
    }

    @IsTest
    static void roleChangeNeedsStepUpAndRevokesSessions() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id memberId = VkfTestData.userId('membera');
        String memberToken = VkfTestData.login('membera');
        try {
            MemberService.updateMember(admin, memberId, new Map<String, Object>{ 'role' => 'Co-Admin' });
            Assert.fail('Step-up required');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        PortalDtos.Member updated = MemberService.updateMember(
            admin,
            memberId,
            new Map<String, Object>{ 'role' => 'Co-Admin', 'currentPassword' => VkfTestData.PASSWORD, 'mobile' => '9999999999' }
        );
        Assert.areEqual('Co-Admin', updated.role);
        try {
            SessionService.require(memberToken, VkfTestData.UA);
            Assert.fail('Role change signs the member out');
        } catch (PortalException e) {
            Assert.areEqual('SESSION_EXPIRED', e.code());
        }
        try {
            MemberService.updateMember(admin, admin.userId, new Map<String, Object>{ 'role' => 'Member', 'currentPassword' => VkfTestData.PASSWORD });
            Assert.fail('Cannot change own role');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        try {
            MemberService.updateMember(
                VkfTestData.ctx('coadmina'),
                VkfTestData.userId('childa'),
                new Map<String, Object>{ 'role' => 'Family Admin', 'currentPassword' => VkfTestData.PASSWORD }
            );
            Assert.fail('Only a Family Admin can promote to Family Admin');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
    }

    @IsTest
    static void transferAdminRightsThenStepDown() {
        VkfTestData.fastPolicy();
        Id coadminId = VkfTestData.userId('coadmina');
        MemberService.updateMember(
            VkfTestData.ctx('admina'),
            coadminId,
            new Map<String, Object>{ 'role' => 'Family Admin', 'currentPassword' => VkfTestData.PASSWORD }
        );
        MemberService.updateMember(
            VkfTestData.ctx('coadmina'),
            VkfTestData.userId('admina'),
            new Map<String, Object>{ 'role' => 'Member', 'currentPassword' => VkfTestData.PASSWORD }
        );
        Assert.areEqual('Member', [SELECT Role__c FROM Portal_User__c WHERE Username__c = 'admina' WITH SYSTEM_MODE].Role__c);
    }

    @IsTest
    static void removeMemberPurgesLogin() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        MemberService.updateMember(
            admin,
            VkfTestData.userId('childa'),
            new Map<String, Object>{ 'status' => 'Removed', 'currentPassword' => VkfTestData.PASSWORD }
        );
        Portal_User__c child = [SELECT Status__c, Password_Hash__c FROM Portal_User__c WHERE Username__c = 'childa' WITH SYSTEM_MODE];
        Assert.areEqual('Removed', child.Status__c);
        Assert.isNull(child.Password_Hash__c);
        Assert.areEqual(3, MemberService.listMembers(admin).size());
        try {
            VkfTestData.login('childa');
            Assert.fail('Removed member cannot sign in');
        } catch (PortalException e) {
            Assert.areEqual('INVALID_CREDENTIALS', e.code());
        }
    }

    @IsTest
    static void unlockResetAndRevoke() {
        VkfTestData.fastPolicy();
        UserContext admin = VkfTestData.ctx('admina');
        Id memberId = VkfTestData.userId('membera');
        String memberToken = VkfTestData.login('membera');
        update as system new Portal_User__c(Id = memberId, Locked_Until__c = Datetime.now().addMinutes(30));
        MemberService.unlockMember(admin, memberId);
        Assert.isNull([SELECT Locked_Until__c FROM Portal_User__c WHERE Id = :memberId WITH SYSTEM_MODE].Locked_Until__c);

        Assert.areEqual(1, MemberService.revokeMemberSessions(admin, memberId));
        try {
            SessionService.require(memberToken, VkfTestData.UA);
            Assert.fail('Revoked');
        } catch (PortalException e) {
            Assert.areEqual('SESSION_EXPIRED', e.code());
        }

        try {
            MemberService.resetMemberPassword(admin, memberId, 'Wrong#Password1');
            Assert.fail('Step-up required');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
        String temp = MemberService.resetMemberPassword(admin, memberId, VkfTestData.PASSWORD);
        Assert.isTrue(AuthService.login('membera', temp, VkfTestData.UA).mustChangePassword);
        try {
            MemberService.resetMemberPassword(admin, admin.userId, VkfTestData.PASSWORD);
            Assert.fail('Own password goes through Profile');
        } catch (PortalException e) {
            Assert.areEqual('VALIDATION', e.code());
        }
    }

    @IsTest
    static void coAdminAndChildLimits() {
        VkfTestData.fastPolicy();
        UserContext coadmin = VkfTestData.ctx('coadmina');
        Id adminId = VkfTestData.userId('admina');
        try {
            MemberService.unlockMember(coadmin, adminId);
            Assert.fail('Co-Admin cannot manage the Family Admin');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        try {
            MemberService.resetMemberPassword(coadmin, adminId, VkfTestData.PASSWORD);
            Assert.fail('Co-Admin cannot reset the Family Admin');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        try {
            MemberService.unlockMember(VkfTestData.ctx('childa'), VkfTestData.userId('membera'));
            Assert.fail('Child has no member security access');
        } catch (PortalException e) {
            Assert.areEqual('NOT_AUTHORIZED', e.code());
        }
        Assert.isTrue(AccessGuard.permissionsFor('Family Admin').contains('MEMBERS:CREATE'));
        Assert.isFalse(AccessGuard.permissionsFor('Child').contains('MEMBERS:CREATE'));
    }
}
