/**
 * Who may see or change which accounts and transactions inside their own family
 * (the family boundary itself is enforced by the selectors). Mirrors the blueprint matrix:
 *   Family Admin / Co-Admin - everything in the family
 *   Member                  - own accounts plus accounts shared with the family
 *   Child                   - own accounts only; edits own entries for 24 hours
 *   Viewer                  - read only: the whole family (Viewer_Scope Family) or nothing
 */
public without sharing class LedgerScope {
    public static final Integer CHILD_EDIT_HOURS = 24;
    private final UserContext ctx;

    public LedgerScope(UserContext ctx) {
        this.ctx = ctx;
    }

    public Boolean wholeFamily() {
        return ctx.isAdmin() || isFamilyViewer();
    }

    public Boolean isFamilyViewer() {
        return ctx.role == 'Viewer' && ctx.viewerScope == 'Family';
    }

    public Boolean canSeeAccount(Financial_Account__c a) {
        if (wholeFamily() || a.Owner_Member__c == ctx.userId) {
            return true;
        }
        return ctx.role == 'Member' && a.Is_Shared__c == true;
    }

    /** May post transactions to (or transfer from) the account. */
    public Boolean canUseAccount(Financial_Account__c a) {
        if (ctx.role == 'Viewer') {
            return false;
        }
        return ctx.isAdmin() || canSeeAccount(a);
    }

    /** May change the account's settings or reconcile it. */
    public Boolean canManageAccount(Financial_Account__c a) {
        return ctx.isAdmin() || (ctx.role == 'Member' && a.Owner_Member__c == ctx.userId);
    }

    /** Transactions are visible when they're the caller's own or sit on an account the caller can see. */
    public Boolean canSeeTransaction(Transaction__c t, Set<Id> visibleAccountIds) {
        return wholeFamily() || t.Member__c == ctx.userId || visibleAccountIds.contains(t.Account__c);
    }

    public Boolean canEditTransaction(Transaction__c t) {
        if (t.Status__c == 'Void' || ctx.role == 'Viewer') {
            return false;
        }
        if (ctx.isAdmin()) {
            return true;
        }
        if (t.Member__c != ctx.userId) {
            return false;
        }
        if (ctx.role == 'Child') {
            return t.CreatedDate == null || t.CreatedDate > Datetime.now().addHours(-CHILD_EDIT_HOURS);
        }
        return ctx.role == 'Member';
    }

    /** Admins can record entries for anyone in the family; everyone else only for themselves. */
    public Id memberFor(Id requested, PortalUserSelector members) {
        if (requested == null || requested == ctx.userId) {
            return ctx.userId;
        }
        if (!ctx.isAdmin()) {
            throw new PortalException('NOT_AUTHORIZED').withError('You can only record your own transactions.');
        }
        return members.memberInFamily(requested).Id;
    }
}
