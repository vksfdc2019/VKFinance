/**
 * The family's month. Most families count from the 1st; salaried families often count from payday,
 * so salary credited on the 30th pays for the month that follows. The Family Admin sets the start
 * day. A month is named after the calendar month it mostly covers: with a start day after the
 * 15th, "November" runs 30 Oct to 29 Nov; with one up to the 15th, "November" runs 10 Nov to 9 Dec.
 * Short months start on their last day. Budgets stay keyed by the 1st of the month they are named after.
 * without sharing: the portal runs as the site guest user, which cannot update Family__c under sharing;
 * access is the caller's own family only, and only the Family Admin can change it.
 */
public without sharing class BudgetMonth {
    public static final Integer CALENDAR = 1;
    private static Map<Id, Integer> cache = new Map<Id, Integer>();

    public class Period {
        public String key;
        /** 1st of the calendar month the period is named after - what budgets are keyed by. */
        public Date anchor;
        public Date startDate;
        public Date endDate;

        public Integer days() {
            return startDate.daysBetween(endDate) + 1;
        }
    }

    public class Settings {
        public Integer monthStartDay;
        public Period current;
        public Boolean canEdit;
    }

    public static Settings settings(UserContext ctx) {
        Settings s = new Settings();
        s.monthStartDay = startDay(ctx.familyId);
        s.current = containing(ctx.familyId, Date.today());
        s.canEdit = ctx.isFamilyAdmin();
        return s;
    }

    /** { monthStartDay: 1-31 } - Family Admin only. */
    public static Settings save(UserContext ctx, Map<String, Object> body) {
        if (!ctx.isFamilyAdmin()) {
            AuditService.log(ctx, 'ACCESS_DENIED', 'Family__c', ctx.familyId, 'FAMILY:SETTINGS');
            throw new PortalException('NOT_AUTHORIZED').withError('Only the Family Admin can change when the month starts.');
        }
        Decimal day = LedgerUtil.dec(body, 'monthStartDay', 'Month start day');
        if (day == null || day < 1 || day > 31 || day != day.round()) {
            throw new PortalException('VALIDATION').withError('The month can start on any day from 1 to 31.');
        }
        update as system new Family__c(Id = ctx.familyId, Month_Start_Day__c = day);
        forget(ctx.familyId);
        AuditService.log(ctx, 'FAMILY_MONTH_START', 'Family__c', ctx.familyId, String.valueOf(day.intValue()));
        return settings(ctx);
    }

    public static Integer startDay(Id familyId) {
        if (familyId == null) {
            return CALENDAR;
        }
        if (!cache.containsKey(familyId)) {
            List<Family__c> rows = [SELECT Month_Start_Day__c FROM Family__c WHERE Id = :familyId WITH SYSTEM_MODE LIMIT 1];
            Decimal day = rows.isEmpty() ? null : rows[0].Month_Start_Day__c;
            cache.put(familyId, day == null || day < 1 || day > 31 ? CALENDAR : day.intValue());
        }
        return cache.get(familyId);
    }

    public static void forget(Id familyId) {
        cache.remove(familyId);
    }

    /** The period named by 'yyyy-MM'; blank means the one today falls in. */
    public static Period named(Id familyId, String month) {
        return String.isBlank(month) ? containing(familyId, Date.today()) : of(familyId, LedgerUtil.monthStart(month));
    }

    /** The period named after the calendar month starting on `anchor` (any day of that month works). */
    public static Period of(Id familyId, Date anchor) {
        return build(Date.newInstance(anchor.year(), anchor.month(), 1), startDay(familyId));
    }

    public static Period containing(Id familyId, Date d) {
        Integer day = startDay(familyId);
        Date anchor = Date.newInstance(d.year(), d.month(), 1);
        if (d >= startOf(anchor.addMonths(1), day)) {
            anchor = anchor.addMonths(1);
        } else if (d < startOf(anchor, day)) {
            anchor = anchor.addMonths(-1);
        }
        return build(anchor, day);
    }

    private static Period build(Date anchor, Integer day) {
        Period p = new Period();
        p.anchor = anchor;
        p.key = LedgerUtil.monthKey(anchor);
        p.startDate = startOf(anchor, day);
        p.endDate = startOf(anchor.addMonths(1), day).addDays(-1);
        return p;
    }

    private static Date startOf(Date anchor, Integer day) {
        if (day <= CALENDAR) {
            return anchor;
        }
        Date month = day > 15 ? anchor.addMonths(-1) : anchor;
        return Date.newInstance(month.year(), month.month(), Math.min(day, Date.daysInMonth(month.year(), month.month())));
    }
}
