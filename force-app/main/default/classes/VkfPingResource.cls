/**
 * Health check for the portal API. Also proves the guest user can reach Apex REST
 * through the Experience Cloud site and that the session header arrives intact.
 */
@RestResource(urlMapping='/vkf/v1/ping')
global with sharing class VkfPingResource {
    @HttpGet
    global static void ping() {
        try {
            VkfRest.ok(
                new Map<String, Object>{
                    'status' => 'ok',
                    'serverTime' => Datetime.now(),
                    'sessionHeaderReceived' => String.isNotBlank(VkfRest.sessionToken(RestContext.request)),
                    'userType' => UserInfo.getUserType()
                }
            );
        } catch (Exception e) {
            VkfRest.fail(e);
        }
    }
}
