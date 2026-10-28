/**
 * Per-client-address throttle for unauthenticated endpoints (sign-in, two-step codes, password
 * reset). It complements the per-username throttle: one address trying many usernames is
 * stopped here. Only a SHA-256 hash of the address is stored.
 */
public without sharing class RateLimiter {
    public static final String AUTH = 'auth';
    public static final String RESET = 'reset';

    @TestVisible
    private static String testAddress;

    /** The caller's address: the edge-supplied header when present, else the socket address. */
    public static String clientAddress() {
        if (testAddress != null) {
            return testAddress;
        }
        RestRequest req = RestContext.request;
        if (req == null) {
            return null;
        }
        if (req.headers != null) {
            for (String key : req.headers.keySet()) {
                if (key.equalsIgnoreCase('X-Salesforce-SIP') && String.isNotBlank(req.headers.get(key))) {
                    return req.headers.get(key);
                }
            }
        }
        return req.remoteAddress;
    }

    public static Boolean isBlocked(String bucket, Integer max) {
        Rate_Limit__c row = current(bucket);
        return row != null && row.Hits__c >= max;
    }

    /** Counts one hit against the caller's address in this bucket's window. */
    public static void hit(String bucket) {
        String key = keyFor(bucket);
        if (key == null) {
            return;
        }
        Rate_Limit__c row = current(bucket);
        if (row == null) {
            row = new Rate_Limit__c(Key__c = key, Window_Start__c = Datetime.now(), Hits__c = 0);
        }
        row.Hits__c = row.Hits__c + 1;
        upsert as system row Key__c;
    }

    /** The row for this window, or null when there is none or it has expired. */
    private static Rate_Limit__c current(String bucket) {
        String key = keyFor(bucket);
        if (key == null) {
            return null;
        }
        List<Rate_Limit__c> rows = [SELECT Id, Key__c, Window_Start__c, Hits__c FROM Rate_Limit__c WHERE Key__c = :key WITH SYSTEM_MODE LIMIT 1];
        Datetime windowStart = Datetime.now().addMinutes(-SecurityPolicy.throttleWindowMinutes());
        if (rows.isEmpty() || rows[0].Window_Start__c < windowStart) {
            return null;
        }
        if (rows[0].Hits__c == null) {
            rows[0].Hits__c = 0;
        }
        return rows[0];
    }

    private static String keyFor(String bucket) {
        String address = clientAddress();
        return String.isBlank(address) ? null : bucket + ':' + TokenService.hash(address.trim());
    }
}
