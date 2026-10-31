/**
 * /vkf/v1/transfers - POST creates both legs of a transfer, or a card payment when the
 * receiving account is a credit card.
 */
@RestResource(urlMapping='/vkf/v1/transfers/*')
global with sharing class VkfTransfersResource {
    @HttpPost
    global static void post() {
        RestRequest req = RestContext.request;
        Savepoint sp = Database.setSavepoint();
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            if (!VkfRest.segmentsAfter(req, 'transfers').isEmpty()) {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.respond(201, TransferService.createTransfer(ctx, VkfRest.body(req)));
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}