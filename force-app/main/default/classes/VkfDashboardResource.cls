/**
 * /vkf/v1/dashboard?month=yyyy-MM&memberId= - all overview widgets for one month.
 * /vkf/v1/dashboard/position?month=yyyy-MM   - available vs spent for accounts, cards, bills and loans.
 * /vkf/v1/dashboard/analytics?month=yyyy-MM&months=12&memberId= - where the money went, month by month.
 */
@RestResource(urlMapping='/vkf/v1/dashboard/*')
global with sharing class VkfDashboardResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'dashboard');
            if (parts.isEmpty()) {
                VkfRest.ok(DashboardService.build(ctx, req.params));
            } else if (parts.size() == 1 && parts[0] == 'position') {
                VkfRest.ok(MoneyPositionService.build(ctx, req.params));
            } else if (parts.size() == 1 && parts[0] == 'analytics') {
                VkfRest.ok(AnalyticsService.build(ctx, req.params));
            } else {
                throw new PortalException('NOT_FOUND');
            }
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}
