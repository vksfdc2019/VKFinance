/**
 * Base class for every portal selector. Subclasses are 'without sharing' (the portal
 * runs as the site guest user), so the family filter here is the tenant boundary:
 * every query in a subclass must include Family__c = :familyId.
 */
public abstract inherited sharing class FamilyScopedSelector {
    protected final UserContext ctx;
    protected final Id familyId;

    protected FamilyScopedSelector(UserContext ctx) {
        if (ctx == null || ctx.familyId == null) {
            throw new PortalException('SESSION_EXPIRED');
        }
        this.ctx = ctx;
        this.familyId = ctx.familyId;
    }

    /** Logs a probe for a record that exists in another family, then hides it behind NOT_FOUND. */
    protected PortalException notFound(String objectName, Id recordId, Boolean existsElsewhere) {
        if (existsElsewhere) {
            AuditService.log(ctx, 'CROSS_FAMILY_ATTEMPT', objectName, recordId, null);
        }
        return new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
    }
}