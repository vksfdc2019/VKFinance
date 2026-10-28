/**
 * Pre-authentication lookups (sign-in, password reset). These run before a session
 * exists, so they are the only Portal_User__c queries without a family filter.
 * Never return these records to the client - map them to DTOs.
 */
public without sharing class IdentitySelector {
    private static final String FIELDS =
        'Id, Name, Family__c, Family__r.Name, Family__r.Family_Code__c, Family__r.Status__c, Family__r.Base_Currency__c, ' +
        'First_Name__c, ' +
        'Last_Name__c, Username__c, Email__c, Mobile__c, Relationship__c, Role__c, Status__c, Viewer_Scope__c, ' +
        'Password_Hash__c, Password_Salt__c, Hash_Iterations__c, Password_Changed_At__c, Must_Change_Password__c, ' +
        'Temp_Password_Expires_At__c, Failed_Login_Count__c, Lockout_Count__c, Locked_Until__c, ' +
        'Login_Window_Start__c, Login_Window_Attempts__c, Last_Login__c, MFA_Method__c';

    public static Portal_User__c byUsername(String username) {
        List<Portal_User__c> rows = query('Username__c = :value', username);
        return rows.isEmpty() ? null : rows[0];
    }

    public static List<Portal_User__c> byEmail(String email) {
        return query('Email__c = :value AND Status__c IN (\'Active\', \'Invited\')', email);
    }

    public static Portal_User__c byId(Id userId) {
        List<Portal_User__c> rows = query('Id = :value', userId);
        return rows.isEmpty() ? null : rows[0];
    }

    public static Boolean usernameTaken(String username) {
        return [SELECT COUNT() FROM Portal_User__c WHERE Username__c = :username WITH SYSTEM_MODE] > 0;
    }

    private static List<Portal_User__c> query(String whereClause, Object value) {
        // whereClause is always a constant from this class; user input only travels as a bind value.
        return Database.queryWithBinds(
            'SELECT ' + FIELDS + ' FROM Portal_User__c WHERE ' + whereClause + ' LIMIT 2',
            new Map<String, Object>{ 'value' => value },
            AccessLevel.SYSTEM_MODE
        );
    }
}
