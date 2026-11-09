/**
 * /vkf/v1/savings/* - savings schemes, insurance policies and the year's tax savings.
 *   GET    /savings                              schemes, policies, cover and per-person 80C/80CCD(1B)/80D
 *   POST   /savings/schemes                      open a scheme (PPF, SSY, NSC, KVP, SCSS, POMIS, PO TD/RD, NPS, EPF, SGB)
 *   PATCH  /savings/schemes/{id}
 *   DELETE /savings/schemes/{id}                 only while nothing is recorded on it
 *   POST   /savings/schemes/{id}/contribute      { fromAccountId, amount, date? }
 *   POST   /savings/schemes/{id}/interest        { amount, date?, toAccountId? }
 *   POST   /savings/schemes/{id}/value           { value, date? }
 *   POST   /savings/schemes/{id}/close           { toAccountId?, date? }
 *   POST   /savings/policies                     add a policy; its premium becomes a bill
 *   PATCH  /savings/policies/{id}
 *   DELETE /savings/policies/{id}
 */
@RestResource(urlMapping='/vkf/v1/savings/*')
global with sharing class VkfSavingsResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            if (!VkfRest.segmentsAfter(req, 'savings').isEmpty()) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(SavingsService.portfolio(ctx));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'savings');
            Map<String, Object> body = VkfRest.body(req);
            if (parts.size() == 1 && parts[0] == 'schemes') {
                VkfRest.respond(201, SavingsService.create(ctx, body));
            } else if (parts.size() == 1 && parts[0] == 'policies') {
                VkfRest.respond(201, InsuranceService.save(ctx, null, body));
            } else if (parts.size() == 3 && parts[0] == 'schemes') {
                Id schemeId = VkfRest.toId(parts[1]);
                switch on parts[2] {
                    when 'contribute' {
                        VkfRest.ok(SavingsService.contribute(ctx, schemeId, body));
                    }
                    when 'interest' {
                        VkfRest.ok(SavingsService.creditInterest(ctx, schemeId, body));
                    }
                    when 'value' {
                        VkfRest.ok(SavingsService.updateValue(ctx, schemeId, body));
                    }
                    when 'close' {
                        VkfRest.ok(SavingsService.close(ctx, schemeId, body));
                    }
                    when else {
                        throw new PortalException('NOT_FOUND');
                    }
                }
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
            List<String> parts = VkfRest.segmentsAfter(req, 'savings');
            if (parts.size() == 2 && parts[0] == 'schemes') {
                VkfRest.ok(SavingsService.updateScheme(ctx, VkfRest.toId(parts[1]), VkfRest.body(req)));
            } else if (parts.size() == 2 && parts[0] == 'policies') {
                VkfRest.ok(InsuranceService.save(ctx, VkfRest.toId(parts[1]), VkfRest.body(req)));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'savings');
            if (parts.size() == 2 && parts[0] == 'schemes') {
                SavingsService.deleteScheme(ctx, VkfRest.toId(parts[1]));
            } else if (parts.size() == 2 && parts[0] == 'policies') {
                InsuranceService.deletePolicy(ctx, VkfRest.toId(parts[1]));
            } else {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.noContent();
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}
