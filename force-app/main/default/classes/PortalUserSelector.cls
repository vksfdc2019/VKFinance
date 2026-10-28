public without sharing class PortalUserSelector extends FamilyScopedSelector {
    public PortalUserSelector(UserContext ctx) {
        super(ctx);
    }

    public List<Portal_User__c> visibleMembers() {
        Id fid = familyId;
        Set<Id> memberIds = ctx.visibleMemberIds();
        return [
            SELECT
                Id, Name, Family__c, First_Name__c, Last_Name__c, Username__c, Email__c, Mobile__c, Relationship__c,
                Role__c, Status__c, Viewer_Scope__c, Must_Change_Password__c, Locked_Until__c, Last_Login__c, MFA_Method__c
            FROM Portal_User__c
            WHERE Family__c = :fid AND Id IN :memberIds AND Status__c != 'Removed'
            WITH SYSTEM_MODE ORDER BY First_Name__c, Last_Name__c
        ];
    }

    public Portal_User__c memberInFamily(Id memberId) {
        Id fid = familyId;
        List<Portal_User__c> rows = memberId == null
            ? new List<Portal_User__c>()
            : [
                  SELECT
                      Id, Name, Family__c, Family__r.Name, Family__r.Family_Code__c, Family__r.Status__c,
                      First_Name__c, Last_Name__c, Username__c, Email__c, Mobile__c, Relationship__c, Role__c,
                      Status__c, Viewer_Scope__c, Password_Hash__c, Password_Salt__c, Hash_Iterations__c,
                      Must_Change_Password__c, Temp_Password_Expires_At__c, Failed_Login_Count__c, Lockout_Count__c,
                      Locked_Until__c, Last_Login__c, MFA_Method__c
                  FROM Portal_User__c
                  WHERE Id = :memberId AND Family__c = :fid AND Status__c != 'Removed'
                  WITH SYSTEM_MODE LIMIT 1
              ];
        if (rows.isEmpty()) {
            Boolean elsewhere = memberId != null && [SELECT COUNT() FROM Portal_User__c WHERE Id = :memberId AND Family__c != :fid WITH SYSTEM_MODE] > 0;
            throw notFound('Portal_User__c', memberId, elsewhere);
        }
        return rows[0];
    }

    public Integer countActiveFamilyAdmins() {
        Id fid = familyId;
        return [
            SELECT COUNT()
            FROM Portal_User__c
            WHERE Family__c = :fid AND Role__c = 'Family Admin' AND Status__c IN ('Active', 'Invited') WITH SYSTEM_MODE
        ];
    }

    public Integer countMembers() {
        Id fid = familyId;
        return [SELECT COUNT() FROM Portal_User__c WHERE Family__c = :fid AND Status__c != 'Removed' WITH SYSTEM_MODE];
    }

    public Decimal maxMembers() {
        Id fid = familyId;
        Decimal max = [SELECT Max_Members__c FROM Family__c WHERE Id = :fid WITH SYSTEM_MODE].Max_Members__c;
        return max == null ? 10 : max;
    }

    public Map<Id, Integer> activeSessionCounts(Set<Id> memberIds) {
        Id fid = familyId;
        Datetime now = Datetime.now();
        Datetime idleCutoff = now.addMinutes(-SecurityPolicy.idleMinutes());
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Portal_User__c userId, COUNT(Id) total
            FROM Portal_Session__c
            WHERE
                Family__c = :fid
                AND Portal_User__c IN :memberIds
                AND Status__c = 'Active'
                AND Expires_At__c > :now
                AND Last_Activity__c > :idleCutoff
            WITH SYSTEM_MODE GROUP BY Portal_User__c
        ]) {
            counts.put((Id) ar.get('userId'), (Integer) ar.get('total'));
        }
        return counts;
    }
}
