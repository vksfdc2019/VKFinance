/**
 * /vkf/v1/auth/* - sign in, sign out, session check, first-login, password change and reset.
 */
@RestResource(urlMapping='/vkf/v1/auth/*')
global with sharing class VkfAuthResource {
    @HttpPost
    global static void post() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            Map<String, Object> body = VkfRest.body(req);
            String userAgent = VkfRest.userAgent(req);
            switch on segment(req) {
                when 'login' {
                    VkfRest.ok(AuthService.login(VkfRest.str(body, 'username'), VkfRest.str(body, 'password'), userAgent));
                }
                when 'logout' {
                    AuthService.logout(SessionService.require(VkfRest.sessionToken(req), userAgent, true));
                    VkfRest.noContent();
                }
                when 'first-login' {
                    UserContext ctx = SessionService.require(VkfRest.sessionToken(req), userAgent, true);
                    VkfRest.ok(AuthService.firstLogin(ctx, VkfRest.str(body, 'newPassword'), userAgent));
                }
                when 'forgot' {
                    AuthService.forgot(VkfRest.str(body, 'identifier'));
                    VkfRest.ok(new Map<String, Object>{ 'message' => AuthService.GENERIC_RESET_MESSAGE });
                }
                when 'reset' {
                    AuthService.reset(VkfRest.str(body, 'token'), VkfRest.str(body, 'newPassword'));
                    VkfRest.ok(new Map<String, Object>{ 'message' => 'Password updated. Sign in with your new password.' });
                }
                when else {
                    throw new PortalException('NOT_FOUND');
                }
            }
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }

    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            if (segment(req) != 'session') {
                throw new PortalException('NOT_FOUND');
            }
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req), true);
            VkfRest.ok(PortalDtos.profile(ctx));
        } catch (Exception e) {
            VkfRest.fail(e);
        }
    }

    @HttpPut
    global static void put() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            if (segment(req) != 'password') {
                throw new PortalException('NOT_FOUND');
            }
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            Map<String, Object> body = VkfRest.body(req);
            AuthService.changePassword(ctx, VkfRest.str(body, 'currentPassword'), VkfRest.str(body, 'newPassword'));
            VkfRest.ok(new Map<String, Object>{ 'message' => 'Password changed. Other devices have been signed out.' });
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }

    private static String segment(RestRequest req) {
        List<String> parts = VkfRest.segmentsAfter(req, 'auth');
        return parts.isEmpty() ? '' : parts[0];
    }
}
