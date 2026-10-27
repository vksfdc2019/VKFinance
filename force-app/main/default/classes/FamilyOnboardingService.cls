/**
 * Creates a family and its first Family Admin. Used by the platform owner from the
 * VK Finance Console (internal Salesforce users only).
 */
public without sharing class FamilyOnboardingService {
    public class Result {
        @AuraEnabled
        public Id familyId;
        @AuraEnabled
        public String familyName;
        @AuraEnabled
        public String familyCode;
        @AuraEnabled
        public Id adminId;
        @AuraEnabled
        public String username;
        @AuraEnabled
        public String temporaryPassword;
        @AuraEnabled
        public String portalUrl;
    }

    public static Result onboard(String familyName, String currencyCode, String timeZone, Integer maxMembers, MemberService.MemberInput admin) {
        if (String.isBlank(familyName) || familyName.trim().length() > 80) {
            throw new PortalException('VALIDATION').withError('Family name is required (up to 80 characters).');
        }
        if (maxMembers != null && (maxMembers < 1 || maxMembers > 50)) {
            throw new PortalException('VALIDATION').withError('Max members must be between 1 and 50.');
        }
        Family__c family = new Family__c(
            Name = familyName.trim(),
            Status__c = 'Active',
            Base_Currency__c = String.isBlank(currencyCode) ? 'INR' : currencyCode.trim().toUpperCase(),
            Time_Zone__c = String.isBlank(timeZone) ? 'Asia/Kolkata' : timeZone.trim(),
            Max_Members__c = maxMembers == null ? 10 : maxMembers
        );
        insert as system family;

        admin.role = 'Family Admin';
        if (String.isBlank(admin.relationship)) {
            admin.relationship = 'Self';
        }
        MemberService.Created created = MemberService.insertMember(family.Id, admin);

        Result result = new Result();
        result.familyId = family.Id;
        result.familyName = family.Name;
        result.familyCode = [SELECT Family_Code__c FROM Family__c WHERE Id = :family.Id WITH SYSTEM_MODE].Family_Code__c;
        result.adminId = created.member.id;
        result.username = created.member.username;
        result.temporaryPassword = created.temporaryPassword;
        result.portalUrl = SecurityPolicy.portalBaseUrl();
        AuditService.log(family.Id, UserInfo.getUserId(), 'FAMILY_CREATED', 'Family__c', family.Id, family.Name);
        return result;
    }

    /** Platform-owner reset for any portal user (e.g. a Family Admin who is locked out). */
    public static String resetPassword(String username) {
        Portal_User__c user = IdentitySelector.byUsername(AuthService.normalizeUsername(username));
        if (user == null || user.Status__c == 'Removed') {
            throw new PortalException('NOT_FOUND').withError('No portal user with that username.');
        }
        String temporaryPassword = PasswordService.generateTemporaryPassword();
        PasswordService.apply(user, temporaryPassword, true);
        update as system new Portal_User__c(
            Id = user.Id,
            Password_Hash__c = user.Password_Hash__c,
            Password_Salt__c = user.Password_Salt__c,
            Hash_Iterations__c = user.Hash_Iterations__c,
            Password_Changed_At__c = user.Password_Changed_At__c,
            Must_Change_Password__c = true,
            Temp_Password_Expires_At__c = user.Temp_Password_Expires_At__c,
            Failed_Login_Count__c = 0,
            Locked_Until__c = null,
            Lockout_Count__c = 0
        );
        SessionService.revokeAll(user.Id, 'Password reset by platform owner', null);
        AuditService.log(user.Family__c, UserInfo.getUserId(), 'PLATFORM_PASSWORD_RESET', 'Portal_User__c', user.Id, null);
        return temporaryPassword;
    }
}
