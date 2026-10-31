/**
 * /vkf/v1/notifications/* - the caller's own in-app alerts.
 *   GET  /notifications           latest alerts and the unread count
 *   POST /notifications/read      { ids?: [...] } marks those (or all) read
 */
@RestResource(urlMapping='/vkf/v1/notifications/*')
global with sharing class VkfNotificationsResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            if (!VkfRest.segmentsAfter(req, 'notifications').isEmpty()) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(NotificationService.feed(ctx));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'notifications');
            if (parts.size() != 1 || parts[0] != 'read') {
                throw new PortalException('NOT_FOUND');
            }
            List<Id> ids = new List<Id>();
            Object raw = VkfRest.body(req).get('ids');
            if (raw instanceof List<Object>) {
                for (Object item : (List<Object>) raw) {
                    Id parsed = VkfRest.toId(String.valueOf(item));
                    if (parsed != null) {
                        ids.add(parsed);
                    }
                }
            }
            VkfRest.ok(new Map<String, Object>{ 'marked' => NotificationService.markRead(ctx, ids) });
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}