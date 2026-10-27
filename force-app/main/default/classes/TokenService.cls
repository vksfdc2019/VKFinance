/**
 * Random tokens for sessions and one-time links. Only the SHA-256 hash of a token
 * is ever stored, so a leaked data export can't be replayed.
 */
public inherited sharing class TokenService {
    public static String newToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(256));
    }

    public static String hash(String value) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(value)));
    }
}
