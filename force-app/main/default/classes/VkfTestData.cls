@IsTest
public class VkfTestData {
    public static final String PASSWORD = 'Str0ng#Harbour';
    public static final String UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0 Safari/537.36';

    /** Same rules as production, but 2 hash iterations so tests stay fast. */
    public static void fastPolicy() {
        fastPolicy(5, 10);
    }

    public static void fastPolicy(Integer maxFailedLogins, Integer throttleMaxAttempts) {
        SecurityPolicy.cached = new Security_Policy__mdt(
            Idle_Timeout_Minutes__c = 30,
            Absolute_Timeout_Hours__c = 12,
            Max_Sessions_Per_User__c = 3,
            Max_Failed_Logins__c = maxFailedLogins,
            Lockout_Minutes__c = 30,
            Throttle_Window_Minutes__c = 15,
            Throttle_Max_Attempts__c = throttleMaxAttempts,
            Min_Password_Length__c = 10,
            Min_Admin_Password_Length__c = 12,
            Password_History_Count__c = 5,
            Hash_Iterations__c = 2,
            Reset_Token_Minutes__c = 30,
            Temp_Password_Hours__c = 24,
            Session_Retention_Days__c = 7,
            Portal_Base_Url__c = 'https://example.test/VKFinancePortal'
        );
    }

    public static Family__c family(String name) {
        Family__c f = new Family__c(Name = name, Status__c = 'Active', Max_Members__c = 10);
        insert as system f;
        return f;
    }

    public static Portal_User__c member(Id familyId, String username, String role) {
        Portal_User__c u = new Portal_User__c(
            Name = username + ' Tester',
            Family__c = familyId,
            First_Name__c = username.capitalize(),
            Last_Name__c = 'Tester',
            Username__c = username,
            Email__c = username + '@example.test',
            Role__c = role,
            Status__c = 'Active',
            Relationship__c = 'Other'
        );
        PasswordService.apply(u, PASSWORD, false);
        insert as system u;
        return u;
    }

    /** Family A: admina, coadmina, membera, childa. Family B: adminb, memberb. */
    public static void twoFamilies() {
        fastPolicy();
        Family__c a = family('Family A');
        member(a.Id, 'admina', 'Family Admin');
        member(a.Id, 'coadmina', 'Co-Admin');
        member(a.Id, 'membera', 'Member');
        member(a.Id, 'childa', 'Child');
        Family__c b = family('Family B');
        member(b.Id, 'adminb', 'Family Admin');
        member(b.Id, 'memberb', 'Member');
    }

    public static Id userId(String username) {
        return [SELECT Id FROM Portal_User__c WHERE Username__c = :username WITH SYSTEM_MODE].Id;
    }

    public static String login(String username) {
        return AuthService.login(username, PASSWORD, UA).token;
    }

    public static UserContext ctx(String username) {
        return SessionService.require(login(username), UA);
    }

    public static RestResponse call(String method, String uri, String body, String token) {
        RestRequest req = new RestRequest();
        req.requestURI = uri;
        req.httpMethod = method;
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        req.addHeader('User-Agent', UA);
        if (token != null) {
            req.addHeader('X-VKF-Session', token);
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return RestContext.response;
    }

    public static Map<String, Object> json(RestResponse res) {
        return (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
    }

    public static String code(RestResponse res) {
        return (String) json(res).get('code');
    }
}
