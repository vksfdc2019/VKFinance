/**
 * /vkf/v1/profile/* - the signed-in member's own profile and devices.
 *   GET    /profile/me
 *   GET    /profile/sessions
 *   GET    /profile/security                 (two-step status, password age, recent security events)
 *   POST   /profile/mfa/setup                {currentPassword} -> key + QR link
 *   POST   /profile/mfa/confirm              {code} -> recovery codes (shown once)
 *   POST   /profile/mfa/disable              {currentPassword, code}
 *   POST   /profile/mfa/recovery-codes       {currentPassword, code} -> new recovery codes
 *   PUT    /profile/appearance               {preset, brand?, mode, radius, text} -> appearance
 *   DELETE /profile/sessions        (sign out every other device)
 *   DELETE /profile/sessions/{id}   (sign out one device)
 *   DELETE /profile/appearance      (back to the family theme)
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
            } else if (target == 'security') {
                VkfRest.ok(AccountSecurityService.overview(ctx));
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

    @HttpPost
    global static void post() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'profile');
            Map<String, Object> body = VkfRest.body(req);
            String action = parts.size() == 2 && parts[0] == 'mfa' ? parts[1] : '';
            switch on action {
                when 'setup' {
                    VkfRest.ok(MfaService.beginSetup(ctx, VkfRest.str(body, 'currentPassword')));
                }
                when 'confirm' {
                    VkfRest.ok(new Map<String, Object>{ 'recoveryCodes' => MfaService.confirmSetup(ctx, VkfRest.str(body, 'code')) });
                }
                when 'disable' {
                    MfaService.disable(ctx, VkfRest.str(body, 'currentPassword'), VkfRest.str(body, 'code'));
                    VkfRest.noContent();
                }
                when 'recovery-codes' {
                    List<String> codes = MfaService.renewRecoveryCodes(ctx, VkfRest.str(body, 'currentPassword'), VkfRest.str(body, 'code'));
                    VkfRest.ok(new Map<String, Object>{ 'recoveryCodes' => codes });
                }
                when else {
                    throw new PortalException('NOT_FOUND');
                }
            }
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }

    @HttpPut
    global static void put() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'profile');
            if (parts.size() != 1 || parts[0] != 'appearance') {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(AppearanceService.savePersonal(ctx, VkfRest.body(req)));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }

    @HttpDelete
    global static void del() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'profile');
            if (parts.size() == 1 && parts[0] == 'appearance') {
                VkfRest.ok(AppearanceService.savePersonal(ctx, null));
                return;
            }
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