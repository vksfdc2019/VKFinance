/**
 * Password hashing, policy and history. Hashes use iterated HMAC-SHA256 with a
 * per-user random salt; the iteration count is stored per user so it can be raised
 * later and applied on the next successful sign-in.
 */
public without sharing class PasswordService {
    private static final String UPPER = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    private static final String LOWER = 'abcdefghijkmnopqrstuvwxyz';
    private static final String DIGITS = '23456789';
    private static final String SYMBOLS = '!@#$%*?-_';
    private static final Set<String> COMMON_WORDS = new Set<String>{
        'password', 'passw', 'qwerty', 'qwertyuiop', 'asdfgh', 'iloveyou', 'admin', 'administrator', 'welcome',
        'letmein', 'monkey', 'football', 'cricket', 'india', 'sunshine', 'princess', 'dragon', 'master', 'changeme',
        'abc', 'abcdef', 'secret', 'login', 'family', 'finance', 'vkfinance', 'test', ''
    };

    public static String newSalt() {
        return EncodingUtil.base64Encode(Crypto.generateAesKey(128));
    }

    public static String hash(String password, String salt, Integer iterations) {
        Blob key = Blob.valueOf(password);
        Blob digest = Crypto.generateMac('hmacSHA256', EncodingUtil.base64Decode(salt), key);
        for (Integer i = 1; i < iterations; i++) {
            digest = Crypto.generateMac('hmacSHA256', digest, key);
        }
        return EncodingUtil.base64Encode(digest);
    }

    public static Boolean matches(String candidate, String salt, Decimal iterations, String expectedHash) {
        if (String.isBlank(candidate) || String.isBlank(salt) || String.isBlank(expectedHash) || iterations == null) {
            return false;
        }
        return slowEquals(hash(candidate, salt, iterations.intValue()), expectedHash);
    }

    private static Boolean slowEquals(String a, String b) {
        if (a.length() != b.length()) {
            return false;
        }
        Integer diff = 0;
        for (Integer i = 0; i < a.length(); i++) {
            diff |= a.charAt(i) ^ b.charAt(i);
        }
        return diff == 0;
    }

    public static List<String> policyErrors(String password, Portal_User__c user) {
        List<String> errors = new List<String>();
        String value = password == null ? '' : password;
        Boolean admin = user != null && (user.Role__c == 'Family Admin' || user.Role__c == 'Co-Admin');
        Integer minLength = admin ? SecurityPolicy.minAdminPasswordLength() : SecurityPolicy.minPasswordLength();
        if (value.length() < minLength) {
            errors.add('Use at least ' + minLength + ' characters.');
        }
        if (value.length() > 128) {
            errors.add('Use at most 128 characters.');
        }
        Integer classes = 0;
        for (String regex : new List<String>{ '[A-Z]', '[a-z]', '[0-9]', '[^A-Za-z0-9]' }) {
            if (Pattern.compile(regex).matcher(value).find()) {
                classes++;
            }
        }
        if (classes < 3) {
            errors.add('Mix at least three of: upper-case letters, lower-case letters, digits and symbols.');
        }
        String lower = value.toLowerCase();
        if (user != null) {
            for (String part : new List<String>{ user.Username__c, user.First_Name__c, user.Last_Name__c }) {
                if (String.isNotBlank(part) && part.length() >= 3 && lower.contains(part.toLowerCase())) {
                    errors.add('Don\'t include your name or username.');
                    break;
                }
            }
        }
        if (value.length() > 0 && COMMON_WORDS.contains(lower.replaceAll('[^a-z]', ''))) {
            errors.add('This password is too common. Pick something less predictable.');
        }
        return errors;
    }

    /** Throws VALIDATION when the password breaks policy or matches one of the recent passwords. */
    public static void validateNew(Portal_User__c user, String password) {
        List<String> errors = policyErrors(password, user);
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }
        Integer keep = SecurityPolicy.passwordHistoryCount();
        if (user.Id == null || keep <= 0) {
            return;
        }
        Boolean reused = matches(password, user.Password_Salt__c, user.Hash_Iterations__c, user.Password_Hash__c);
        if (!reused) {
            for (Password_History__c h : [
                SELECT Password_Hash__c, Password_Salt__c, Hash_Iterations__c
                FROM Password_History__c
                WHERE Portal_User__c = :user.Id
                WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Id DESC
                LIMIT :keep
            ]) {
                if (matches(password, h.Password_Salt__c, h.Hash_Iterations__c, h.Password_Hash__c)) {
                    reused = true;
                    break;
                }
            }
        }
        if (reused) {
            throw new PortalException('VALIDATION').withError('You used this password recently. Choose a new one.');
        }
    }

    /** Sets the hash fields on the record; the caller saves it. */
    public static void apply(Portal_User__c user, String password, Boolean temporary) {
        Integer iterations = SecurityPolicy.hashIterations();
        user.Password_Salt__c = newSalt();
        user.Hash_Iterations__c = iterations;
        user.Password_Hash__c = hash(password, user.Password_Salt__c, iterations);
        user.Password_Changed_At__c = Datetime.now();
        user.Must_Change_Password__c = temporary;
        user.Temp_Password_Expires_At__c = temporary ? Datetime.now().addHours(SecurityPolicy.tempPasswordHours()) : null;
        user.Failed_Login_Count__c = 0;
        user.Locked_Until__c = null;
    }

    /** Stores the user's current hash in history and trims history to the policy size. */
    public static void recordHistory(Portal_User__c user) {
        insert as system new Password_History__c(
            Portal_User__c = user.Id,
            Password_Hash__c = user.Password_Hash__c,
            Password_Salt__c = user.Password_Salt__c,
            Hash_Iterations__c = user.Hash_Iterations__c
        );
        Integer keep = Math.max(SecurityPolicy.passwordHistoryCount(), 1);
        List<Password_History__c> rows = [
            SELECT Id
            FROM Password_History__c
            WHERE Portal_User__c = :user.Id
            WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Id DESC
        ];
        if (rows.size() > keep) {
            List<Password_History__c> extra = new List<Password_History__c>();
            for (Integer i = keep; i < rows.size(); i++) {
                extra.add(rows[i]);
            }
            delete as system extra;
        }
    }

    /** 12 characters with at least one upper, lower, digit and symbol; avoids look-alike characters. */
    public static String generateTemporaryPassword() {
        String all = UPPER + LOWER + DIGITS + SYMBOLS;
        List<String> chars = new List<String>{ pick(UPPER), pick(LOWER), pick(DIGITS), pick(SYMBOLS) };
        while (chars.size() < 12) {
            chars.add(pick(all));
        }
        for (Integer i = chars.size() - 1; i > 0; i--) {
            Integer j = randomInt(i + 1);
            String swap = chars[i];
            chars[i] = chars[j];
            chars[j] = swap;
        }
        return String.join(chars, '');
    }

    private static String pick(String source) {
        Integer i = randomInt(source.length());
        return source.substring(i, i + 1);
    }

    private static Integer randomInt(Integer bound) {
        Integer value = Math.mod(Crypto.getRandomInteger(), bound);
        return value < 0 ? value + bound : value;
    }
}