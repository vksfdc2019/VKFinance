@IsTest
private class VkfRestTest {
    private static RestResponse setUp(String uri, String method, String body, Map<String, String> headers) {
        RestRequest req = new RestRequest();
        req.requestURI = uri;
        req.httpMethod = method;
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        if (headers != null) {
            for (String key : headers.keySet()) {
                req.addHeader(key, headers.get(key));
            }
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return RestContext.response;
    }

    @IsTest
    static void pingReportsHeaderAndStatus() {
        RestResponse res = setUp('/vkf/v1/ping', 'GET', null, new Map<String, String>{ 'x-vkf-session' => 'abc' });
        VkfPingResource.ping();
        Assert.areEqual(200, res.statusCode);
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Assert.areEqual('ok', payload.get('status'));
        Assert.areEqual(true, payload.get('sessionHeaderReceived'));
    }

    @IsTest
    static void portalExceptionMapsToStatusAndCode() {
        RestResponse res = setUp('/vkf/v1/x', 'GET', null, null);
        VkfRest.fail(new PortalException('NOT_FOUND').withError('Nope'));
        Assert.areEqual(404, res.statusCode);
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Assert.areEqual('NOT_FOUND', payload.get('code'));
    }

    @IsTest
    static void unexpectedExceptionHidesDetails() {
        RestResponse res = setUp('/vkf/v1/x', 'GET', null, null);
        VkfRest.fail(new DmlException('internal detail'));
        Assert.areEqual(500, res.statusCode);
        Assert.isFalse(res.responseBody.toString().contains('internal detail'));
    }

    @IsTest
    static void bodyParsingAndHelpers() {
        setUp('/vkf/v1/family/members/a01xx/unlock', 'POST', '{"username":"dad"}', new Map<String, String>{ 'User-Agent' => 'UA' });
        Map<String, Object> body = VkfRest.body(RestContext.request);
        Assert.areEqual('dad', VkfRest.str(body, 'username'));
        Assert.areEqual('a01xx', VkfRest.pathParam(RestContext.request, 'members'));
        Assert.areEqual('UA', VkfRest.userAgent(RestContext.request));

        setUp('/vkf/v1/x', 'POST', '[1,2]', null);
        try {
            VkfRest.body(RestContext.request);
            Assert.fail('Expected BAD_REQUEST');
        } catch (PortalException e) {
            Assert.areEqual('BAD_REQUEST', e.code());
            Assert.areEqual(400, e.httpStatus());
        }
    }
}
