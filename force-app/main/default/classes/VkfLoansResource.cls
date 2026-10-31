/**
 * /vkf/v1/loans/* - loans and EMIs.
 *   GET   /loans
 *   GET   /loans/{id}/schedule
 *   GET   /loans/{id}/rates      rate change history, newest first
 *   POST  /loans
 *   PATCH /loans/{id}             details, or corrected terms that re-price the loan
 *   DELETE /loans/{id}            only while nothing has been paid on it
 *   POST  /loans/{id}/pay        pays the next EMI { accountId?, date? }
 *   POST  /loans/{id}/prepay     { amount, accountId?, date? }
 *   POST  /loans/{id}/rate       { annualRate, adjust: EMI|Tenure, emiAmount?, effectiveDate?, note? }
 */
@RestResource(urlMapping='/vkf/v1/loans/*')
global with sharing class VkfLoansResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'loans');
            if (parts.isEmpty()) {
                VkfRest.ok(LoanService.listLoans(ctx));
            } else if (parts.size() == 2 && parts[1] == 'schedule') {
                VkfRest.ok(LoanService.schedule(ctx, VkfRest.toId(parts[0])));
            } else if (parts.size() == 2 && parts[1] == 'rates') {
                VkfRest.ok(LoanService.rateChanges(ctx, VkfRest.toId(parts[0])));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'loans');
            Map<String, Object> body = VkfRest.body(req);
            if (parts.isEmpty()) {
                VkfRest.respond(201, LoanService.createLoan(ctx, body));
            } else if (parts.size() == 2 && parts[1] == 'pay') {
                VkfRest.ok(LoanService.payEmi(ctx, VkfRest.toId(parts[0]), body));
            } else if (parts.size() == 2 && parts[1] == 'prepay') {
                VkfRest.ok(LoanService.prepay(ctx, VkfRest.toId(parts[0]), body));
            } else if (parts.size() == 2 && parts[1] == 'rate') {
                VkfRest.ok(LoanService.changeRate(ctx, VkfRest.toId(parts[0]), body));
            } else {
                throw new PortalException('NOT_FOUND');
            }
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }

    @HttpDelete
    global static void remove() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'loans');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            LoanService.deleteLoan(ctx, VkfRest.toId(parts[0]));
            VkfRest.noContent();
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
            List<String> parts = VkfRest.segmentsAfter(req, 'loans');
            if (parts.size() != 1) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(LoanService.updateLoan(ctx, VkfRest.toId(parts[0]), VkfRest.body(req)));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}