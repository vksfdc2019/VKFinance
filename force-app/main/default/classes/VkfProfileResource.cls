/**
 * /vkf/v1/profile/* - the signed-in member's own profile and devices.
 *   GET    /profile/me
 *   GET    /profile/sessions
 *   DELETE /profile/sessions        (sign out every other device)
 *   DELETE /profile/sessions/{id}   (sign out one device)
 */
@RestResource(urlMapping='/vkf/v1/profile/*')
global with sharing class VkfProfileResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'profile');
            String target = parts.isEmpty() ? '' : parts[0];
            if (target == 'me') {
                VkfRest.ok(PortalDtos.profile(ctx));
            } else if (target == 'sessions') {
                List<PortalDtos.Session> sessions = new List<PortalDtos.Session>();
                for (Portal_Session__c s : SessionService.activeForUser(ctx.userId)) {
                    sessions.add(PortalDtos.session(s, ctx.sessionId));
                }
                VkfRest.ok(sessions);
            } else {
                throw new PortalException('NOT_FOUND');
            }
        } catch (Exception e) {
            VkfRest.fail(e);
        }
    }

    @HttpDelete
    global static void del() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'profile');
            if (parts.isEmpty() || parts[0] != 'sessions') {
                throw new PortalException('NOT_FOUND');
            }
            if (parts.size() == 1) {
                Integer revoked = SessionService.revokeAll(ctx.userId, 'Signed out everywhere', ctx.sessionId);
                AuditService.log(ctx, 'SIGN_OUT_EVERYWHERE', 'Portal_Session__c', null, revoked + ' session(s)');
                VkfRest.ok(new Map<String, Object>{ 'revoked' => revoked });
            } else {
                SessionService.revokeOwn(ctx, VkfRest.toId(parts[1]));
                AuditService.log(ctx, 'SESSION_REVOKED', 'Portal_Session__c', VkfRest.toId(parts[1]), null);
                VkfRest.noContent();
            }
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}
