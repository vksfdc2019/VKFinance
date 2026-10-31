/**
 * /vkf/v1/deposits/* - fixed and recurring deposits.
 *   GET   /deposits                   every visible deposit with totals, TDS and DICGC checks
 *   GET   /deposits/{accountId}
 *   PATCH /deposits/{accountId}       create or update the terms of an FD or RD account
 *   POST  /deposits/{accountId}/close { date?, amountReceived?, toAccountId? } - at maturity or early
 *   POST  /deposits/{accountId}/renew { date?, amountReceived?, includeInterest?, rate?, tenureMonths?, tenureDays?, maturityAmount? }
 */
@RestResource(urlMapping='/vkf/v1/deposits/*')
global with sharing class VkfDepositsResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'deposits');
            if (parts.isEmpty()) {
                VkfRest.ok(DepositService.portfolio(ctx));
            } else if (parts.size() == 1) {
                VkfRest.ok(DepositService.get(ctx, VkfRest.toId(parts[0])));
            } else {
                throw new PortalException('NOT_FOUND');
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
            List<String> parts = VkfRest.segmentsAfter(req, 'deposits');
            Map<String, Object> body = VkfRest.body(req);
            if (parts.size() == 2 && parts[1] == 'close') {
                VkfRest.ok(DepositService.close(ctx, VkfRest.toId(parts[0]), body));
            } else if (parts.size() == 2 && parts[1] == 'renew') {
                VkfRest.ok(DepositService.renew(ctx, VkfRest.toId(parts[0]), body));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'deposits');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(DepositService.save(ctx, VkfRest.toId(parts[0]), VkfRest.body(req)));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}
