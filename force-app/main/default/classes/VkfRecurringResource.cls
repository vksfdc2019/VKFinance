/**
 * /vkf/v1/recurring/* - repeating entries.
 *   GET   /recurring
 *   POST  /recurring
 *   PATCH /recurring/{id}
 *   POST  /recurring/{id}/post    post the next occurrence now
 *   POST  /recurring/{id}/skip    skip the next occurrence
 */
@RestResource(urlMapping='/vkf/v1/recurring/*')
global with sharing class VkfRecurringResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            if (!VkfRest.segmentsAfter(req, 'recurring').isEmpty()) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(RecurringService.listRules(ctx));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'recurring');
            Map<String, Object> body = VkfRest.body(req);
            if (parts.isEmpty()) {
                VkfRest.respond(201, RecurringService.createRule(ctx, body));
            } else if (parts.size() == 2 && (parts[1] == 'post' || parts[1] == 'skip')) {
                VkfRest.ok(RecurringService.postNow(ctx, VkfRest.toId(parts[0]), parts[1] == 'skip'));
            } else {
                throw new PortalException('NOT_FOUND');
            }
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }

    @HttpPatch
    global static void patch() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'recurring');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(RecurringService.updateRule(ctx, VkfRest.toId(parts[0]), VkfRest.body(req)));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}
