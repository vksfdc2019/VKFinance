/**
 * /vkf/v1/accounts/* - the caller's financial accounts.
 *   GET   /accounts[?includeClosed=true]
 *   GET   /accounts/targets            every active account a transfer can go to
 *   POST  /accounts
 *   PATCH /accounts/{id}
 *   POST  /accounts/{id}/reconcile     match the balance to a statement
 */
@RestResource(urlMapping='/vkf/v1/accounts/*')
global with sharing class VkfAccountsResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'accounts');
            if (parts.isEmpty()) {
                VkfRest.ok(AccountService.listAccounts(ctx, req.params.get('includeClosed') == 'true'));
            } else if (parts.size() == 1 && parts[0] == 'credit-groups') {
                VkfRest.ok(CreditLimitGroupService.overview(ctx));
            } else if (parts.size() == 2 && parts[1] == 'statements') {
                VkfRest.ok(CardStatementService.listStatements(ctx, VkfRest.toId(parts[0])));
            } else if (parts.size() == 1 && parts[0] == 'targets') {
                VkfRest.ok(AccountService.transferTargets(ctx));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'accounts');
            Map<String, Object> body = VkfRest.body(req);
            if (parts.isEmpty()) {
                VkfRest.respond(201, AccountService.createAccount(ctx, body));
            } else if (parts.size() == 1 && parts[0] == 'credit-groups') {
                VkfRest.respond(201, CreditLimitGroupService.save(ctx, null, body, false));
            } else if (parts.size() == 3 && parts[0] == 'credit-groups' && parts[2] == 'archive') {
                Id groupId = VkfRest.toId(parts[1]);
                if (groupId == null) throw new PortalException('NOT_FOUND');
                VkfRest.ok(CreditLimitGroupService.save(ctx, groupId, body, true));
            } else if (parts.size() == 2 && parts[1] == 'reconcile') {
                VkfRest.ok(AccountService.reconcile(ctx, VkfRest.toId(parts[0]), body));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'accounts');
            if (parts.size() == 2 && parts[0] == 'credit-groups') {
                Id groupId = VkfRest.toId(parts[1]);
                if (groupId == null) throw new PortalException('NOT_FOUND');
                VkfRest.ok(CreditLimitGroupService.save(ctx, groupId, VkfRest.body(req), false));
            } else if (parts.size() == 1) {
                VkfRest.ok(AccountService.updateAccount(ctx, VkfRest.toId(parts[0]), VkfRest.body(req)));
            } else {
                throw new PortalException('NOT_FOUND');
            }
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}
