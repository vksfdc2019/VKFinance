/**
 * /vkf/v1/archive/* - archived months, read-only.
 *   GET /archive            archived-through date and the months that hold entries
 *   GET /archive/{YYYY-MM}  that month's archived entries the caller may see
 */
@RestResource(urlMapping='/vkf/v1/archive/*')
global with sharing class VkfArchiveResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'archive');
            if (parts.isEmpty()) {
                VkfRest.ok(ArchiveViewService.summary(ctx));
            } else if (parts.size() == 1) {
                VkfRest.ok(ArchiveViewService.month(ctx, parts[0]));
            } else {
                throw new PortalException('NOT_FOUND');
            }
        } catch (Exception e) {
            VkfRest.fail(e);
        }
    }
}