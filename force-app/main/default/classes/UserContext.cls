/**
 * Who is calling, built from a validated session. familyId always comes from the
 * database - never from the request - and every selector filters on it.
 */
public without sharing class UserContext {
    public Id userId;
    public Id familyId;
    public Id sessionId;
    public String scope;
    public String role;
    public String status;
    public String firstName;
    public String lastName;
    public String username;
    public String email;
    public String mobile;
    public String relationship;
    public String viewerScope;
    public Boolean mustChangePassword;
    public String familyName;
    public String familyCode;
    private Set<Id> visibleMembers;

    public UserContext(Portal_User__c user, Id sessionId, String scope) {
        this.userId = user.Id;
        this.familyId = user.Family__c;
        this.sessionId = sessionId;
        this.scope = scope;
        this.role = user.Role__c;
        this.status = user.Status__c;
        this.firstName = user.First_Name__c;
        this.lastName = user.Last_Name__c;
        this.username = user.Username__c;
        this.email = user.Email__c;
        this.mobile = user.Mobile__c;
        this.relationship = user.Relationship__c;
        this.viewerScope = user.Viewer_Scope__c;
        this.mustChangePassword = user.Must_Change_Password__c;
        this.familyName = user.Family__r?.Name;
        this.familyCode = user.Family__r?.Family_Code__c;
    }

    public Boolean isFamilyAdmin() {
        return role == 'Family Admin';
    }

    public Boolean isAdmin() {
        return role == 'Family Admin' || role == 'Co-Admin';
    }

    /** Members whose data this caller may see: everyone for admins (and family-scoped viewers), otherwise self. */
    public Set<Id> visibleMemberIds() {
        if (visibleMembers == null) {
            if (isAdmin() || (role == 'Viewer' && viewerScope == 'Family')) {
                visibleMembers = new Map<Id, Portal_User__c>([SELECT Id FROM Portal_User__c WHERE Family__c = :familyId WITH SYSTEM_MODE])
                    .keySet();
            } else {
                visibleMembers = new Set<Id>{ userId };
            }
        }
        return visibleMembers;
    }
}
