/**
 * /vkf/v1/reports/* - reports, saved reports and the dashboard layout.
 *   GET    /reports/{type}?from=&to=&memberId=&accountId=&categoryId=
 *   GET    /reports/saved
 *   POST   /reports/saved          { name, reportType, filters, shared }
 *   DELETE /reports/saved/{id}
 *   GET    /reports/layout
 *   PUT    /reports/layout         { widgets: [{ key, hidden }] }
 */
@RestResource(urlMapping='/vkf/v1/reports/*')
global with sharing class VkfReportsResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'reports');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            if (parts[0] == 'saved') {
                VkfRest.ok(InsightService.savedReports(ctx));
            } else if (parts[0] == 'layout') {
                VkfRest.ok(new Map<String, Object>{ 'widgets' => InsightService.layout(ctx) });
            } else {
                VkfRest.ok(ReportService.run(ctx, parts[0], req.params));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'reports');
            if (parts.size() != 1 || parts[0] != 'saved') {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.respond(201, InsightService.saveReport(ctx, VkfRest.body(req)));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'reports');
            if (parts.size() != 1 || parts[0] != 'layout') {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(new Map<String, Object>{ 'widgets' => InsightService.saveLayout(ctx, VkfRest.body(req)) });
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
            List<String> parts = VkfRest.segmentsAfter(req, 'reports');
            if (parts.size() != 2 || parts[0] != 'saved') {
                throw new PortalException('NOT_FOUND');
            }
            InsightService.deleteReport(ctx, VkfRest.toId(parts[1]));
            VkfRest.noContent();
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}
