/**
 * Portal appearance: each person's theme and the family default, stored as small validated JSON
 * on Portal_User__c.Theme__c and Family__c.Theme__c. Only known keys and values are ever saved.
 *
 * Personal: { v, preset, brand?, mode, radius, text }   mode/text are always the person's own.
 *           preset 'family' keeps following the family's colours and corners.
 * Family:   { v, preset, brand?, radius, locked }       locked = members can't pick their own colours.
 */
public without sharing class AppearanceService {
    public static final Integer VERSION = 1;
    public static final String CUSTOM = 'custom';
    public static final String FOLLOW_FAMILY = 'family';
    public static final Set<String> PRESETS = new Set<String>{
        'teal', 'ocean', 'indigo', 'grape', 'berry', 'sunset', 'gold', 'forest', 'graphite', CUSTOM
    };
    public static final Set<String> MODES = new Set<String>{ 'light', 'dark', 'system' };
    public static final Set<String> RADII = new Set<String>{ 'sharp', 'default', 'round' };
    public static final Set<String> TEXT_SIZES = new Set<String>{ 'default', 'large' };
    private static final Pattern HEX = Pattern.compile('^#[0-9a-fA-F]{6}$');

    /** What the portal needs to theme itself for this caller. */
    public static PortalDtos.Appearance forUser(UserContext ctx) {
        Id me = ctx.userId;
        Id fid = ctx.familyId;
        List<Portal_User__c> rows = [
            SELECT Theme__c, Family__r.Theme__c FROM Portal_User__c WHERE Id = :me AND Family__c = :fid WITH SYSTEM_MODE
        ];
        PortalDtos.Appearance a = new PortalDtos.Appearance();
        if (rows.isEmpty()) {
            return a;
        }
        a.personal = parse(rows[0].Theme__c);
        a.family = parse(rows[0].Family__r?.Theme__c);
        a.locked = LedgerUtil.bool(a.family, 'locked');
        return a;
    }

    /** Saves the caller's own theme. A null body (or reset=true) goes back to the family theme. */
    public static PortalDtos.Appearance savePersonal(UserContext ctx, Map<String, Object> body) {
        String json = body == null || LedgerUtil.bool(body, 'reset') ? null : JSON.serialize(cleanPersonal(body));
        update as system new Portal_User__c(Id = ctx.userId, Theme__c = json);
        return forUser(ctx);
    }

    /** Saves the family default. Admins only; a null body (or reset=true) goes back to the VK Finance default. */
    public static PortalDtos.Appearance saveFamily(UserContext ctx, Map<String, Object> body) {
        if (!ctx.isAdmin()) {
            throw new PortalException('NOT_AUTHORIZED').withError('Only the Family Admin or a Co-Admin can change the family theme.');
        }
        Map<String, Object> clean = body == null || LedgerUtil.bool(body, 'reset') ? null : cleanFamily(body);
        update as system new Family__c(Id = ctx.familyId, Theme__c = clean == null ? null : JSON.serialize(clean));
        String detail = clean == null ? 'reset to default' : clean.get('preset') + (LedgerUtil.bool(clean, 'locked') ? ' (locked)' : '');
        AuditService.log(ctx, 'FAMILY_THEME_CHANGED', 'Family__c', ctx.familyId, detail);
        return forUser(ctx);
    }

    public static Map<String, Object> cleanPersonal(Map<String, Object> body) {
        Map<String, Object> clean = LedgerUtil.text(body, 'preset') == FOLLOW_FAMILY
            ? new Map<String, Object>{ 'v' => VERSION, 'preset' => FOLLOW_FAMILY }
            : colours(body);
        clean.put('mode', choice(body, 'mode', MODES, 'system', 'Choose light, dark or match device.'));
        clean.put('text', choice(body, 'text', TEXT_SIZES, 'default', 'Choose a text size.'));
        return clean;
    }

    public static Map<String, Object> cleanFamily(Map<String, Object> body) {
        Map<String, Object> clean = colours(body);
        clean.put('locked', LedgerUtil.bool(body, 'locked'));
        return clean;
    }

    /** Colour theme and corners, shared by both shapes. A custom theme needs a #rrggbb brand colour. */
    private static Map<String, Object> colours(Map<String, Object> body) {
        String preset = choice(body, 'preset', PRESETS, null, 'Choose one of the themes.');
        Map<String, Object> clean = new Map<String, Object>{ 'v' => VERSION, 'preset' => preset };
        if (preset == CUSTOM) {
            String brand = LedgerUtil.text(body, 'brand');
            if (brand == null || !HEX.matcher(brand).matches()) {
                throw new PortalException('VALIDATION').withError('Pick a colour for your custom theme, like #0f766e.');
            }
            clean.put('brand', brand.toLowerCase());
        }
        clean.put('radius', choice(body, 'radius', RADII, 'default', 'Choose a corner style.'));
        return clean;
    }

    private static String choice(Map<String, Object> body, String key, Set<String> allowed, String fallback, String error) {
        String value = LedgerUtil.text(body, key);
        if (value == null && fallback != null) {
            return fallback;
        }
        if (value == null || !allowed.contains(value)) {
            throw new PortalException('VALIDATION').withError(error);
        }
        return value;
    }

    /** Stored JSON back to a map; anything unreadable is treated as "not set" rather than breaking sign-in. */
    private static Map<String, Object> parse(String stored) {
        if (String.isBlank(stored)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(stored);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
        } catch (JSONException e) {
            return null;
        }
    }
}
