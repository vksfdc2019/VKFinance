/**
 * Role x feature x action checks from Role_Permission__mdt. Every portal endpoint
 * calls require() after the session check; the role always comes from the database.
 */
public without sharing class AccessGuard {
    @TestVisible
    private static Map<String, Set<String>> matrix;

    private static Map<String, Set<String>> matrix() {
        if (matrix == null) {
            matrix = new Map<String, Set<String>>();
            for (Role_Permission__mdt p : [SELECT Role__c, Feature__c, Actions__c FROM Role_Permission__mdt WITH SYSTEM_MODE]) {
                Set<String> actions = new Set<String>();
                for (String action : (p.Actions__c == null ? '' : p.Actions__c).split(',')) {
                    if (String.isNotBlank(action)) {
                        actions.add(action.trim().toUpperCase());
                    }
                }
                matrix.put(p.Role__c + '|' + p.Feature__c, actions);
            }
        }
        return matrix;
    }

    public static Boolean can(UserContext ctx, String feature, String action) {
        Set<String> actions = matrix().get(ctx.role + '|' + feature);
        return actions != null && actions.contains(action);
    }

    public static void require(UserContext ctx, String feature, String action) {
        if (!can(ctx, feature, action)) {
            AuditService.log(ctx, 'ACCESS_DENIED', null, null, feature + ':' + action);
            throw new PortalException('NOT_AUTHORIZED').withError('You don\'t have access to do that.');
        }
    }

    /** 'FEATURE:ACTION' strings for the role, sent to the client to show or hide UI. */
    public static List<String> permissionsFor(String role) {
        List<String> result = new List<String>();
        for (String key : matrix().keySet()) {
            if (key.startsWith(role + '|')) {
                String feature = key.substringAfter('|');
                for (String action : matrix().get(key)) {
                    result.add(feature + ':' + action);
                }
            }
        }
        result.sort();
        return result;
    }
}