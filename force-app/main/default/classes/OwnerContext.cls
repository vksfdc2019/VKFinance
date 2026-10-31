/**
 * Builds the UserContext the Owner Workspace acts with: the platform owner (a Salesforce
 * user holding the VKF_Platform_Admin custom permission) works inside one family as that
 * family's admin, so every existing service rule - scoping, validation, transfer pairing,
 * bill/EMI linkage, balances - applies unchanged.
 *
 * without sharing + SYSTEM_MODE because portal records are not shared to internal users;
 * every entry point re-checks the custom permission first, and familyId is always re-read
 * from the database.
 */
public without sharing class OwnerContext {
  public static final String PERMISSION = 'VKF_Platform_Admin';
  private static final List<String> ADMIN_STATUSES = new List<String>{
    'Active',
    'Invited'
  };

  /** One family as the workspace's family picker shows it. */
  public class FamilySummary {
    public Id id;
    public String name;
    public String familyCode;
    public String status;
    public String currencyCode;
    public Integer memberCount = 0;
    public String adminName;
  }

  /**
   * @param familyId the family to act in
   * @param forWrite true for changes: suspended families are then refused
   * @return a Family Admin context tagged with the owner, with audit tagging switched on
   * @throws PortalException NOT_AUTHORIZED without the permission, NOT_FOUND for an unknown family
   *         or one without an admin, CONFLICT when writing to a suspended family
   */
  public static UserContext forFamily(Id familyId, Boolean forWrite) {
    requirePermission();
    Portal_User__c admin = adminOf(familyId);
    if (forWrite == true && admin.Family__r.Status__c != 'Active') {
      throw new PortalException('CONFLICT')
        .withError(
          'This family is suspended. Reactivate it before making changes.'
        );
    }
    UserContext ctx = new UserContext(admin, null, SessionService.SCOPE_FULL);
    ctx.ownerUserId = UserInfo.getUserId();
    AuditService.actingOwnerId = ctx.ownerUserId;
    return ctx;
  }

  /**
   * Read-only Family Admin context for the scheduled owner alerts (OwnerAlertJob). Server-side
   * only - no @AuraEnabled path reaches it - so it skips the custom permission check (the job
   * runs as whoever scheduled it) and the audit tag (it changes nothing).
   * @throws PortalException NOT_FOUND when the family has no admin
   */
  public static UserContext forAlerts(Id familyId) {
    return new UserContext(adminOf(familyId), null, SessionService.SCOPE_FULL);
  }

  private static Portal_User__c adminOf(Id familyId) {
    if (familyId == null) {
      throw new PortalException('BAD_REQUEST')
        .withError('Choose a family first.');
    }
    List<Portal_User__c> admins = [
      SELECT
        Id,
        Family__c,
        Family__r.Name,
        Family__r.Family_Code__c,
        Family__r.Status__c,
        Family__r.Base_Currency__c,
        Role__c,
        Status__c,
        First_Name__c,
        Last_Name__c,
        Username__c,
        Email__c,
        Mobile__c,
        Relationship__c,
        Viewer_Scope__c,
        Must_Change_Password__c
      FROM Portal_User__c
      WHERE
        Family__c = :familyId
        AND Role__c = 'Family Admin'
        AND Status__c IN :ADMIN_STATUSES
      WITH SYSTEM_MODE
      ORDER BY CreatedDate ASC
      LIMIT 20
    ];
    if (admins.isEmpty()) {
      throw new PortalException('NOT_FOUND')
        .withError('That family has no Family Admin to act as.');
    }
    // Picklists sort in definition order (Invited before Active), so prefer an active admin here.
    Portal_User__c admin = admins[0];
    for (Portal_User__c candidate : admins) {
      if (candidate.Status__c == 'Active') {
        admin = candidate;
        break;
      }
    }
    return admin;
  }

  /** @return every family (Active before Suspended - the picklist order), then by name, with member counts and the admin's name */
  public static List<FamilySummary> families() {
    requirePermission();
    Map<Id, Integer> counts = new Map<Id, Integer>();
    for (AggregateResult r : [
      SELECT Family__c fam, COUNT(Id) total
      FROM Portal_User__c
      WHERE Status__c != 'Removed'
      WITH SYSTEM_MODE
      GROUP BY Family__c
    ]) {
      counts.put((Id) r.get('fam'), (Integer) r.get('total'));
    }
    Map<Id, String> adminNames = new Map<Id, String>();
    for (Portal_User__c u : [
      SELECT Family__c, First_Name__c, Last_Name__c
      FROM Portal_User__c
      WHERE Role__c = 'Family Admin' AND Status__c IN :ADMIN_STATUSES
      WITH SYSTEM_MODE
      ORDER BY CreatedDate ASC
    ]) {
      if (!adminNames.containsKey(u.Family__c)) {
        adminNames.put(
          u.Family__c,
          FinanceDtos.personName(u.First_Name__c, u.Last_Name__c)
        );
      }
    }
    List<FamilySummary> result = new List<FamilySummary>();
    for (Family__c f : [
      SELECT Id, Name, Family_Code__c, Status__c, Base_Currency__c
      FROM Family__c
      WITH SYSTEM_MODE
      ORDER BY Status__c ASC, Name ASC
      LIMIT 1000
    ]) {
      FamilySummary s = new FamilySummary();
      s.id = f.Id;
      s.name = f.Name;
      s.familyCode = f.Family_Code__c;
      s.status = f.Status__c;
      s.currencyCode = String.isBlank(f.Base_Currency__c)
        ? 'INR'
        : f.Base_Currency__c;
      s.memberCount = counts.containsKey(f.Id) ? counts.get(f.Id) : 0;
      s.adminName = adminNames.get(f.Id);
      result.add(s);
    }
    return result;
  }

  public static void requirePermission() {
    if (!FeatureManagement.checkPermission(PERMISSION)) {
      throw new PortalException('NOT_AUTHORIZED')
        .withError(
          'You need the VKF Platform Admin permission set to do this.'
        );
    }
  }
}
