/**
 * Internal console actions for the platform owner. Requires the VKF_Platform_Admin
 * custom permission (granted by the VKF_Platform_Admin permission set).
 */
public with sharing class VkfConsoleController {
    @AuraEnabled
    public static FamilyOnboardingService.Result onboardFamily(
        String familyName,
        String currencyCode,
        String timeZone,
        Integer maxMembers,
        String firstName,
        String lastName,
        String username,
        String email
    ) {
        requirePlatformAdmin();
        Savepoint sp = Database.setSavepoint();
        try {
            MemberService.MemberInput admin = new MemberService.MemberInput();
            admin.firstName = firstName == null ? null : firstName.trim();
            admin.lastName = lastName == null ? null : lastName.trim();
            admin.username = AuthService.normalizeUsername(username);
            admin.email = email == null ? null : email.trim();
            return FamilyOnboardingService.onboard(familyName, currencyCode, timeZone, maxMembers, admin);
        } catch (PortalException e) {
            Database.rollback(sp);
            throw auraError(e.errors.isEmpty() ? e.code() : String.join(e.errors, ' '));
        }
    }

    @AuraEnabled
    public static String resetPortalPassword(String username) {
        requirePlatformAdmin();
        try {
            return FamilyOnboardingService.resetPassword(username);
        } catch (PortalException e) {
            throw auraError(e.errors.isEmpty() ? e.code() : String.join(e.errors, ' '));
        }
    }

    private static void requirePlatformAdmin() {
        if (!FeatureManagement.checkPermission('VKF_Platform_Admin')) {
            throw auraError('You need the VKF Platform Admin permission set to do this.');
        }
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}