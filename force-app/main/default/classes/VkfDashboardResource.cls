/** /vkf/v1/dashboard?month=yyyy-MM&memberId= - all overview widgets for one month. */
@RestResource(urlMapping='/vkf/v1/dashboard/*')
global with sharing class VkfDashboardResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            VkfRest.ok(DashboardService.build(ctx, req.params));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}