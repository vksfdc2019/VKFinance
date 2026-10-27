/**
 * Error raised anywhere in the portal stack. The message is a stable error code
 * (SESSION_EXPIRED, NOT_AUTHORIZED, ...) that VkfRest maps to an HTTP status;
 * user-facing details go in `errors`.
 */
public class PortalException extends Exception {
    private static final Map<String, Integer> HTTP_STATUS = new Map<String, Integer>{
        'BAD_REQUEST' => 400,
        'INVALID_CREDENTIALS' => 401,
        'SESSION_EXPIRED' => 401,
        'NOT_AUTHORIZED' => 403,
        'NOT_FOUND' => 404,
        'CONFLICT' => 409,
        'VALIDATION' => 422,
        'LOCKED' => 423,
        'THROTTLED' => 429
    };

    public List<String> errors = new List<String>();

    public String code() {
        return getMessage();
    }

    public Integer httpStatus() {
        return HTTP_STATUS.containsKey(getMessage()) ? HTTP_STATUS.get(getMessage()) : 400;
    }

    public PortalException withErrors(List<String> messages) {
        errors = messages == null ? new List<String>() : messages;
        return this;
    }

    public PortalException withError(String message) {
        return withErrors(new List<String>{ message });
    }
}
