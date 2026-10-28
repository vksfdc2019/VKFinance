/** New API surface only. Existing resource contracts and ledger behavior are unchanged. */
@RestResource(urlMapping='/vkf/v1/enhancements/*')
global with sharing class VkfEnhancementsResource {
    private static UserContext context() {
        return SessionService.require(VkfRest.sessionToken(RestContext.request), VkfRest.userAgent(RestContext.request));
    }
    private static List<String> parts() { return VkfRest.segmentsAfter(RestContext.request, 'enhancements'); }

    @HttpGet
    global static void get() {
        try {
            UserContext ctx = context(); List<String> path = parts();
            if (path.size() == 1 && path[0] == 'settings') VkfRest.ok(EnhancementService.settings(ctx));
            else if (path.size() == 1 && path[0] == 'imports') VkfRest.ok(StatementImportService.listImports(ctx));
            else if (path.size() == 2 && path[0] == 'imports') VkfRest.ok(StatementImportService.detail(ctx, VkfRest.toId(path[1])));
            else if (path.size() == 1 && path[0] == 'goals') VkfRest.ok(SavingsGoalService.listGoals(ctx));
            else if (path.size() == 1 && path[0] == 'requests') VkfRest.ok(SpendRequestService.listRequests(ctx));
            else if (path.size() == 1 && path[0] == 'insights') VkfRest.ok(SmartInsightService.insights(ctx));
            else if (path.size() == 3 && path[0] == 'transactions' && path[2] == 'receipts') VkfRest.ok(ReceiptService.listReceipts(ctx, VkfRest.toId(path[1])));
            else if (path.size() == 2 && path[0] == 'receipts') VkfRest.ok(ReceiptService.download(ctx, VkfRest.toId(path[1])));
            else throw new PortalException('NOT_FOUND');
        } catch (Exception e) { VkfRest.fail(e); }
    }

    @HttpPost
    global static void post() {
        Savepoint sp = Database.setSavepoint();
        try {
            if (RestContext.request.requestBody != null && RestContext.request.requestBody.size() > 1000000)
                throw EnhancementService.invalid('This upload is too large. Use a smaller file.');
            UserContext ctx = context(); List<String> path = parts(); Map<String, Object> body = VkfRest.body(RestContext.request);
            if (path.size() == 1 && path[0] == 'imports') VkfRest.respond(201, StatementImportService.stage(ctx, body));
            else if (path.size() == 3 && path[0] == 'imports' && (path[2] == 'commit' || path[2] == 'cancel'))
                VkfRest.ok(StatementImportService.startImport(ctx, VkfRest.toId(path[1]), path[2] == 'cancel'));
            else if (path.size() == 1 && path[0] == 'goals') VkfRest.respond(201, SavingsGoalService.save(ctx, null, body));
            else if (path.size() == 1 && path[0] == 'requests') VkfRest.respond(201, SpendRequestService.create(ctx, body));
            else if (path.size() == 3 && path[0] == 'requests') VkfRest.ok(SpendRequestService.act(ctx, VkfRest.toId(path[1]), path[2], body));
            else if (path.size() == 3 && path[0] == 'transactions' && path[2] == 'receipts') VkfRest.respond(201, ReceiptService.upload(ctx, VkfRest.toId(path[1]), body));
            else if (path.size() == 2 && path[0] == 'insights' && path[1] == 'dismiss') { SmartInsightService.dismiss(ctx, body); VkfRest.noContent(); }
            else throw new PortalException('NOT_FOUND');
        } catch (Exception e) { VkfRest.fail(e, sp); }
    }

    @HttpPatch
    global static void patch() {
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = context(); List<String> path = parts(); Map<String, Object> body = VkfRest.body(RestContext.request);
            if (path.size() == 1 && path[0] == 'settings') VkfRest.ok(EnhancementService.configure(ctx, body));
            else if (path.size() == 2 && path[0] == 'goals') VkfRest.ok(SavingsGoalService.save(ctx, VkfRest.toId(path[1]), body));
            else throw new PortalException('NOT_FOUND');
        } catch (Exception e) { VkfRest.fail(e, sp); }
    }

    @HttpDelete
    global static void remove() {
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = context(); List<String> path = parts();
            if (path.size() == 2 && path[0] == 'goals') SavingsGoalService.archive(ctx, VkfRest.toId(path[1]));
            else if (path.size() == 2 && path[0] == 'receipts') ReceiptService.remove(ctx, VkfRest.toId(path[1]));
            else throw new PortalException('NOT_FOUND');
            VkfRest.noContent();
        } catch (Exception e) { VkfRest.fail(e, sp); }
    }
}
