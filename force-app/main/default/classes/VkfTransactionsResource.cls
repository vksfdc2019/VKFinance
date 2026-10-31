/**
 * /vkf/v1/transactions/* - the family ledger.
 *   GET    /transactions?month=&from=&to=&type=&accountId=&categoryId=&memberId=&q=&includeVoid=&cursor=&limit=
 *   GET    /transactions/{id}
 *   POST   /transactions                income, expense or refund
 *   PATCH  /transactions/{id}           both legs of a transfer change together
 *   DELETE /transactions/{id}           voids (both legs of a transfer)
 */
@RestResource(urlMapping='/vkf/v1/transactions/*')
global with sharing class VkfTransactionsResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'transactions');
            if (parts.isEmpty()) {
                VkfRest.ok(TransactionService.listTransactions(ctx, req.params));
            } else if (parts.size() == 1) {
                VkfRest.ok(TransactionService.getTransaction(ctx, VkfRest.toId(parts[0])));
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
            if (!VkfRest.segmentsAfter(req, 'transactions').isEmpty()) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.respond(201, TransactionService.createTransaction(ctx, VkfRest.body(req)));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'transactions');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(TransactionService.updateTransaction(ctx, VkfRest.toId(parts[0]), VkfRest.body(req)));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'transactions');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            TransactionService.voidTransaction(ctx, VkfRest.toId(parts[0]));
            VkfRest.noContent();
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}