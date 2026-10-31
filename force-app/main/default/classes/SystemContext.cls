/**
 * Builds a UserContext for automation (daily jobs, recurring rules) that acts as a real
 * family member, so the same permission and scope checks apply as in the portal.
 */
public without sharing class SystemContext {
    public static UserContext forMember(Id memberId) {
        Portal_User__c user = memberId == null ? null : IdentitySelector.byId(memberId);
        if (user == null || user.Status__c == 'Removed' || user.Status__c == 'Disabled') {
            return null;
        }
        return new UserContext(user, null, 'FULL');
    }

    /** The first active Family Admin - used for auto-pay when no responsible member can act. */
    public static UserContext familyAdmin(Id familyId) {
        for (Portal_User__c u : [
            SELECT Id
            FROM Portal_User__c
            WHERE Family__c = :familyId AND Role__c IN ('Family Admin', 'Co-Admin') AND Status__c = 'Active'
            WITH SYSTEM_MODE
            ORDER BY Role__c DESC, CreatedDate
            LIMIT 1
        ]) {
            return forMember(u.Id);
        }
        return null;
    }

    public static Set<Id> adminIds(Id familyId) {
        return new Map<Id, Portal_User__c>([
                SELECT Id
                FROM Portal_User__c
                WHERE Family__c = :familyId AND Role__c IN ('Family Admin', 'Co-Admin') AND Status__c IN ('Active', 'Invited')
                WITH SYSTEM_MODE
            ])
            .keySet();
    }
}