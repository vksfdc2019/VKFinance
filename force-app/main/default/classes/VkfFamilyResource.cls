/**
 * /vkf/v1/family/* - member management for the caller's own family.
 *   GET    /family/members
 *   POST   /family/members
 *   PATCH  /family/members/{id}
 *   POST   /family/members/{id}/unlock
 *   POST   /family/members/{id}/reset-password
 *   POST   /family/members/{id}/reset-mfa
 *   DELETE /family/members/{id}/sessions
 *   GET    /family/settings          { monthStartDay, current period }
 *   PUT    /family/settings          { monthStartDay } (Family Admin)
 *   PUT    /family/appearance        {preset, brand?, radius, locked} (admins)
 *   DELETE /family/appearance        (back to the VK Finance default; admins)
 */
@RestResource(urlMapping='/vkf/v1/family/*')
global with sharing class VkfFamilyResource {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        try {
            UserContext ctx = SessionService.require(VkfRest.sessionToken(req), VkfRest.userAgent(req));
            List<String> parts = VkfRest.segmentsAfter(req, 'family');
            if (parts.size() == 1 && parts[0] == 'members') {
                VkfRest.ok(MemberService.listMembers(ctx));
            } else if (parts.size() == 1 && parts[0] == 'settings') {
                VkfRest.ok(BudgetMonth.settings(ctx));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'family');
            Map<String, Object> body = VkfRest.body(req);
            if (parts.size() == 1 && parts[0] == 'members') {
                VkfRest.respond(201, MemberService.createMember(ctx, new MemberService.MemberInput(body)));
            } else if (parts.size() == 3 && parts[0] == 'members' && parts[2] == 'unlock') {
                MemberService.unlockMember(ctx, VkfRest.toId(parts[1]));
                VkfRest.noContent();
            } else if (parts.size() == 3 && parts[0] == 'members' && parts[2] == 'reset-password') {
                String temporaryPassword = MemberService.resetMemberPassword(
                    ctx,
                    VkfRest.toId(parts[1]),
                    VkfRest.str(body, 'currentPassword'),
                    VkfRest.str(body, 'code')
                );
                VkfRest.ok(new Map<String, Object>{ 'temporaryPassword' => temporaryPassword });
            } else if (parts.size() == 3 && parts[0] == 'members' && parts[2] == 'reset-mfa') {
                MemberService.resetMemberMfa(ctx, VkfRest.toId(parts[1]), VkfRest.str(body, 'currentPassword'), VkfRest.str(body, 'code'));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'family');
            if (parts.size() == 2 && parts[0] == 'members') {
                VkfRest.ok(MemberService.updateMember(ctx, VkfRest.toId(parts[1]), VkfRest.body(req)));
            } else {
                throw new PortalException('NOT_FOUND');
            }
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
            List<String> parts = VkfRest.segmentsAfter(req, 'family');
            if (parts.size() == 1 && parts[0] == 'settings') {
                VkfRest.ok(BudgetMonth.save(ctx, VkfRest.body(req)));
                return;
            }
            if (parts.size() != 1 || parts[0] != 'appearance') {
                throw new PortalException('NOT_FOUND');
            }
            VkfRest.ok(AppearanceService.saveFamily(ctx, VkfRest.body(req)));
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
            List<String> parts = VkfRest.segmentsAfter(req, 'family');
            if (parts.size() == 1 && parts[0] == 'appearance') {
                VkfRest.ok(AppearanceService.saveFamily(ctx, null));
            } else if (parts.size() == 3 && parts[0] == 'members' && parts[2] == 'sessions') {
                VkfRest.ok(new Map<String, Object>{ 'revoked' => MemberService.revokeMemberSessions(ctx, VkfRest.toId(parts[1])) });
            } else {
                throw new PortalException('NOT_FOUND');
            }
        } catch (Exception e) {
            VkfRest.fail(e, sp);
        }
    }
}