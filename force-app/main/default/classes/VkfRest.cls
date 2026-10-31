/**
 * Shared plumbing for the /vkf/v1 Apex REST resources: reads the session header,
 * parses JSON bodies and writes JSON responses. Errors never expose stack traces.
 */
public inherited sharing class VkfRest {
    public static final String SESSION_HEADER = 'X-VKF-Session';

    public static String sessionToken(RestRequest req) {
        if (req == null || req.headers == null) {
            return null;
        }
        // Header names can arrive in any case depending on the proxy in front of Apex.
        for (String key : req.headers.keySet()) {
            if (key.equalsIgnoreCase(SESSION_HEADER)) {
                return req.headers.get(key);
            }
        }
        return null;
    }

    public static String userAgent(RestRequest req) {
        if (req == null || req.headers == null) {
            return null;
        }
        for (String key : req.headers.keySet()) {
            if (key.equalsIgnoreCase('User-Agent')) {
                return req.headers.get(key);
            }
        }
        return null;
    }

    public static Map<String, Object> body(RestRequest req) {
        if (req == null || req.requestBody == null || req.requestBody.size() == 0) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(req.requestBody.toString());
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
        } catch (JSONException e) {
            // fall through to the validation error below
        }
        throw new PortalException('BAD_REQUEST').withError('Request body must be a JSON object.');
    }

    public static String str(Map<String, Object> body, String key) {
        Object value = body.get(key);
        return value == null ? null : String.valueOf(value);
    }

    /** Last path segment after the given marker, e.g. ('/vkf/v1/family/members/a01x/unlock', 'members') -> 'a01x'. */
    public static String pathParam(RestRequest req, String afterSegment) {
        List<String> parts = req.requestURI.split('/');
        for (Integer i = 0; i < parts.size() - 1; i++) {
            if (parts[i] == afterSegment) {
                return parts[i + 1];
            }
        }
        return null;
    }

    public static void ok(Object payload) {
        respond(200, payload);
    }

    public static void noContent() {
        respond(204, null);
    }

    public static void respond(Integer status, Object payload) {
        SessionService.flushActivity();
        RestResponse res = RestContext.response;
        res.statusCode = status;
        res.addHeader('Content-Type', 'application/json');
        res.addHeader('Cache-Control', 'no-store');
        res.responseBody = payload == null ? null : Blob.valueOf(JSON.serialize(payload, true));
    }

    /** Rolls back the request's DML unless the exception asks to keep it, then writes the error. */
    public static void fail(Exception e, Savepoint sp) {
        Boolean keep = e instanceof PortalException && ((PortalException) e).keepChanges;
        if (sp != null && !keep) {
            Database.rollback(sp);
        }
        fail(e);
    }

    /** Path segments after a marker, e.g. ('/vkf/v1/family/members/x/unlock', 'family') -> [members, x, unlock]. */
    public static List<String> segmentsAfter(RestRequest req, String marker) {
        List<String> result = new List<String>();
        Boolean found = false;
        for (String part : req.requestURI.split('/')) {
            if (found && String.isNotBlank(part)) {
                result.add(part);
            }
            if (part == marker) {
                found = true;
            }
        }
        return result;
    }

    public static Id toId(String value) {
        try {
            return String.isBlank(value) ? null : Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    public static void fail(Exception e) {
        if (e instanceof PortalException) {
            PortalException pe = (PortalException) e;
            respond(pe.httpStatus(), new ErrorBody(pe.code(), pe.errors));
            return;
        }
        String rowError = rowError(e);
        if (rowError != null) {
            respond(400, new ErrorBody('VALIDATION', new List<String>{ rowError }));
            return;
        }
        System.debug(LoggingLevel.ERROR, e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
        respond(500, new ErrorBody('UNEXPECTED', new List<String>{ 'Something went wrong. Please try again.' }));
    }

    /** A row error raised by a trigger (e.g. the archived-period guard) is meant for the user. */
    private static String rowError(Exception e) {
        // Read from the message: the row accessors throw an uncatchable error on a DmlException built in code.
        String marker = 'FIELD_CUSTOM_VALIDATION_EXCEPTION, ';
        String message = e instanceof DmlException ? e.getMessage() : null;
        if (message == null || !message.contains(marker)) {
            return null;
        }
        String text = message.substringAfter(marker);
        return text.contains(': [') ? text.substringBeforeLast(': [') : text;
    }

    public class ErrorBody {
        public String code;
        public List<String> errors;

        public ErrorBody(String code, List<String> errors) {
            this.code = code;
            this.errors = errors;
        }
    }
}