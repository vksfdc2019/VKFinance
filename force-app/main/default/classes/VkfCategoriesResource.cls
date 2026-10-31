/**
 * /vkf/v1/categories/* - the family's income and expense categories.
 *   GET   /categories
 *   POST  /categories
 *   PATCH /categories/{id}
 */
@RestResource(urlMapping='/vkf/v1/categories/*')
global with sharing class VkfCategoriesResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            if (!VkfRest.segmentsAfter(req, 'categories').isEmpty()) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(CategoryService.listCategories(ctx));
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
            if (!VkfRest.segmentsAfter(req, 'categories').isEmpty()) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.respond(201, CategoryService.createCategory(ctx, VkfRest.body(req)));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'categories');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(CategoryService.updateCategory(ctx, VkfRest.toId(parts[0]), VkfRest.body(req)));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}