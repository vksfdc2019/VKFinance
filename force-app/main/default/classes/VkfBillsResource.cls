/**
 * /vkf/v1/bills/* - recurring bills.
 *   GET   /bills
 *   POST  /bills
 *   PATCH /bills/{id}
 *   POST  /bills/instances/{id}/pay     { amount?, accountId?, date?, paymentMode?, notes? }
 *   POST  /bills/instances/{id}/skip
 */
@RestResource(urlMapping='/vkf/v1/bills/*')
global with sharing class VkfBillsResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            if (!VkfRest.segmentsAfter(req, 'bills').isEmpty()) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(BillService.listBills(ctx));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'bills');
            Map<String, Object> body = VkfRest.body(req);
            if (parts.isEmpty()) {
                VkfRest.respond(201, BillService.createBill(ctx, body));
            } else if (parts.size() == 3 && parts[0] == 'instances' && parts[2] == 'pay') {
                VkfRest.ok(BillService.payInstance(ctx, VkfRest.toId(parts[1]), body));
            } else if (parts.size() == 3 && parts[0] == 'instances' && parts[2] == 'skip') {
                BillService.skipInstance(ctx, VkfRest.toId(parts[1]));
                VkfRest.noContent();
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
            List<String> parts = VkfRest.segmentsAfter(req, 'bills');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(BillService.updateBill(ctx, VkfRest.toId(parts[0]), VkfRest.body(req)));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}