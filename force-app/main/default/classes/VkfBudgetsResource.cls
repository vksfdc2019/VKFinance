/**
 * /vkf/v1/budgets/{yyyy-MM} - the family's plan for a month.
 *   GET  /budgets/{month}
 *   PUT  /budgets/{month}                  { lines: [{ categoryId, planned }] }
 *   POST /budgets/{month}/copy-previous
 */
@RestResource(urlMapping='/vkf/v1/budgets/*')
global with sharing class VkfBudgetsResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'budgets');
            if (parts.size() > 1) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(BudgetService.getBudget(ctx, parts.isEmpty() ? null : parts[0]));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'budgets');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(BudgetService.saveBudget(ctx, parts[0], VkfRest.body(req)));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }

    @HttpPost
    global static void post() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'budgets');
            if (parts.size() != 2 || parts[1] != 'copy-previous') {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(BudgetService.copyPrevious(ctx, parts[0]));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}
