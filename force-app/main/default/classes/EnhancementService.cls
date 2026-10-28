/** Additive, per-family Phase 6 switches. Blank configuration keeps every feature off. */
public without sharing class EnhancementService {
    public static final List<String> FEATURES = new List<String>{ 'IMPORTS', 'RECEIPTS', 'REQUESTS', 'GOALS', 'INSTALL', 'INSIGHTS' };
    private static Map<Id, Set<String>> enabledByFamily = new Map<Id, Set<String>>();

    public static Set<String> enabledFor(UserContext ctx) {
        if (ctx == null || ctx.familyId == null) throw new PortalException('SESSION_EXPIRED');
        if (!enabledByFamily.containsKey(ctx.familyId)) {
            Set<String> enabled = new Set<String>();
            for (Family__c f : [SELECT Enhancements__c FROM Family__c WHERE Id = :ctx.familyId WITH SYSTEM_MODE]) {
                if (String.isNotBlank(f.Enhancements__c)) enabled.addAll(f.Enhancements__c.split(','));
            }
            enabledByFamily.put(ctx.familyId, enabled);
        }
        return enabledByFamily.get(ctx.familyId);
    }

    public static Map<String, Object> settings(UserContext ctx) {
        AccessGuard.require(ctx, 'ENHANCEMENTS', 'READ');
        return new Map<String, Object>{ 'enabled' => new List<String>(enabledFor(ctx)), 'available' => FEATURES,
            'canManage' => ctx.isFamilyAdmin() && AccessGuard.can(ctx, 'ENHANCEMENTS', 'EDIT') };
    }

    public static Map<String, Object> configure(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'ENHANCEMENTS', 'EDIT');
        if (!ctx.isFamilyAdmin()) throw new PortalException('NOT_AUTHORIZED');
        Object raw = body.get('enabled');
        if (!(raw instanceof List<Object>)) throw invalid('Choose the features to enable.');
        Set<String> next = new Set<String>();
        for (Object item : (List<Object>) raw) {
            String key = String.valueOf(item);
            if (!FEATURES.contains(key)) throw invalid('Unknown enhancement.');
            next.add(key);
        }
        AuthService.requireStepUp(ctx, VkfRest.str(body, 'currentPassword'), VkfRest.str(body, 'code'));
        lockFamily(ctx);
        List<String> ordered = new List<String>(next); ordered.sort();
        update as system new Family__c(Id = ctx.familyId, Enhancements__c = String.join(ordered, ','));
        enabledByFamily.put(ctx.familyId, next);
        AuditService.log(ctx, 'ENHANCEMENTS_CONFIGURED', 'Family__c', ctx.familyId, String.join(ordered, ','));
        return settings(ctx);
    }

    public static void requireFeature(UserContext ctx, String feature, String action) {
        AccessGuard.require(ctx, feature, action);
        if (!enabledFor(ctx).contains(feature)) throw new PortalException('NOT_AUTHORIZED').withError('This enhancement is turned off for your family.');
    }

    public static void lockFamily(UserContext ctx) {
        List<Family__c> locked = [SELECT Id FROM Family__c WHERE Id = :ctx.familyId WITH SYSTEM_MODE FOR UPDATE];
        if (locked.isEmpty()) throw new PortalException('SESSION_EXPIRED');
    }

    public static PortalException invalid(String message) {
        return new PortalException('VALIDATION').withError(message);
    }

    public static String title(Map<String, Object> body, String key, Integer maxLength) {
        String value = LedgerUtil.limited(LedgerUtil.text(body, key), maxLength, key);
        if (String.isBlank(value)) throw invalid('Enter ' + key + '.');
        return value;
    }

    /** An internal-only utility: the object allowlist and field lists are developer constants. */
    public static SObject record(UserContext ctx, String objectName, String fields, Id recordId, Boolean lockRow) {
        Set<String> allowed = new Set<String>{ 'Spend_Request__c', 'Savings_Goal__c', 'Statement_Import__c', 'Transaction_Receipt__c' };
        if (!allowed.contains(objectName)) throw new PortalException('BAD_REQUEST');
        List<SObject> found = Database.queryWithBinds('SELECT Id, Family__c, ' + fields + ' FROM ' + objectName +
            ' WHERE Id = :rid AND Family__c = :fid' + (lockRow ? ' FOR UPDATE' : ''),
            new Map<String, Object>{ 'rid' => recordId, 'fid' => ctx.familyId }, AccessLevel.SYSTEM_MODE);
        if (found.isEmpty()) throw new PortalException('NOT_FOUND');
        return found[0];
    }
}
