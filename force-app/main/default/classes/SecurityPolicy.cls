/**
 * Reads the Security_Policy__mdt record named Default. Every setting has a safe
 * fallback so a missing value never weakens security to zero.
 */
public inherited sharing class SecurityPolicy {
    @TestVisible
    private static Security_Policy__mdt cached;

    public static Security_Policy__mdt current() {
        if (cached == null) {
            // System mode: the portal runs as the site guest user, who has no access to custom metadata.
            List<Security_Policy__mdt> rows = [
                SELECT
                    Idle_Timeout_Minutes__c, Absolute_Timeout_Hours__c, Max_Sessions_Per_User__c, Max_Failed_Logins__c,
                    Lockout_Minutes__c, Throttle_Window_Minutes__c, Throttle_Max_Attempts__c, Min_Password_Length__c,
                    Min_Admin_Password_Length__c, Password_History_Count__c, Hash_Iterations__c, Reset_Token_Minutes__c,
                    Temp_Password_Hours__c, Session_Retention_Days__c, Portal_Base_Url__c
                FROM Security_Policy__mdt
                WHERE DeveloperName = 'Default'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            cached = rows.isEmpty() ? new Security_Policy__mdt() : rows[0];
        }
        return cached;
    }

    private static Integer num(Decimal value, Integer fallback) {
        return value == null ? fallback : value.intValue();
    }

    public static Integer idleMinutes() {
        return num(current().Idle_Timeout_Minutes__c, 30);
    }

    public static Integer absoluteHours() {
        return num(current().Absolute_Timeout_Hours__c, 12);
    }

    public static Integer maxSessions() {
        return num(current().Max_Sessions_Per_User__c, 3);
    }

    public static Integer maxFailedLogins() {
        return num(current().Max_Failed_Logins__c, 5);
    }

    public static Integer lockoutMinutes() {
        return num(current().Lockout_Minutes__c, 30);
    }

    public static Integer throttleWindowMinutes() {
        return num(current().Throttle_Window_Minutes__c, 15);
    }

    public static Integer throttleMaxAttempts() {
        return num(current().Throttle_Max_Attempts__c, 10);
    }

    public static Integer minPasswordLength() {
        return num(current().Min_Password_Length__c, 10);
    }

    public static Integer minAdminPasswordLength() {
        return num(current().Min_Admin_Password_Length__c, 12);
    }

    public static Integer passwordHistoryCount() {
        return num(current().Password_History_Count__c, 5);
    }

    public static Integer hashIterations() {
        return num(current().Hash_Iterations__c, 3000);
    }

    public static Integer resetTokenMinutes() {
        return num(current().Reset_Token_Minutes__c, 30);
    }

    public static Integer tempPasswordHours() {
        return num(current().Temp_Password_Hours__c, 24);
    }

    public static Integer sessionRetentionDays() {
        return num(current().Session_Retention_Days__c, 7);
    }

    public static String portalBaseUrl() {
        return current().Portal_Base_Url__c;
    }
}
