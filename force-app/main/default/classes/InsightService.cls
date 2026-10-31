/**
 * Saved reports, each person's dashboard layout, and closed-month snapshots.
 *  - Saved reports store only a report type and filters; data is always re-read with the
 *    viewer's own scope, so sharing a saved report never shares anyone else's data.
 *  - Monthly_Summary__c snapshots (family and per member) are written by the daily job for the
 *    month just closed, so long-range reports don't re-aggregate old history.
 */
public without sharing class InsightService {
    public static final Integer MAX_SAVED = 50;
    public static final Set<String> FILTER_KEYS = new Set<String>{ 'from', 'to', 'preset', 'memberId', 'accountId', 'categoryId' };
    public static final Set<String> WIDGETS = new Set<String>{ 'upcoming', 'cashflow', 'categories', 'budget', 'accounts', 'recent' };

    public class SavedReport {
        public Id id;
        public String name;
        public String reportType;
        public Map<String, Object> filters;
        public Boolean shared;
        public Boolean mine;
        public String ownerName;
    }

    public static List<SavedReport> savedReports(UserContext ctx) {
        AccessGuard.require(ctx, 'REPORTS', 'READ');
        Id fid = ctx.familyId;
        Id me = ctx.userId;
        List<SavedReport> result = new List<SavedReport>();
        for (Saved_Report__c r : [
            SELECT Id, Name, Report_Type__c, Filters__c, Shared_With_Family__c, Owner_Member__c, Owner_Member__r.First_Name__c, Owner_Member__r.Last_Name__c
            FROM Saved_Report__c
            WHERE Family__c = :fid AND (Owner_Member__c = :me OR Shared_With_Family__c = TRUE)
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 200
        ]) {
            SavedReport d = new SavedReport();
            d.id = r.Id;
            d.name = r.Name;
            d.reportType = r.Report_Type__c;
            d.filters = String.isBlank(r.Filters__c) ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(r.Filters__c);
            d.shared = r.Shared_With_Family__c;
            d.mine = r.Owner_Member__c == me;
            d.ownerName = FinanceDtos.personName(r.Owner_Member__r?.First_Name__c, r.Owner_Member__r?.Last_Name__c);
            result.add(d);
        }
        return result;
    }

    public static SavedReport saveReport(UserContext ctx, Map<String, Object> body) {
        AccessGuard.require(ctx, 'REPORTS', 'CREATE');
        String name = LedgerUtil.text(body, 'name');
        String type = LedgerUtil.text(body, 'reportType');
        List<String> errors = new List<String>();
        if (String.isBlank(name) || name.length() > 80) {
            errors.add('Give the report a name (up to 80 characters).');
        }
        if (!ReportService.TYPES.contains(type)) {
            errors.add('Choose a report.');
        }
        Map<String, Object> filters = new Map<String, Object>();
        Object raw = body.get('filters');
        if (raw instanceof Map<String, Object>) {
            for (String key : ((Map<String, Object>) raw).keySet()) {
                Object value = ((Map<String, Object>) raw).get(key);
                if (!FILTER_KEYS.contains(key)) {
                    errors.add('Unknown filter "' + key + '".');
                } else if (value != null) {
                    filters.put(key, String.valueOf(value).left(40));
                }
            }
        }
        Id fid = ctx.familyId;
        Id me = ctx.userId;
        if ([SELECT COUNT() FROM Saved_Report__c WHERE Family__c = :fid AND Owner_Member__c = :me WITH SYSTEM_MODE] >= MAX_SAVED) {
            errors.add('You can keep up to ' + MAX_SAVED + ' saved reports. Delete one first.');
        }
        if (!errors.isEmpty()) {
            throw new PortalException('VALIDATION').withErrors(errors);
        }
        Saved_Report__c r = new Saved_Report__c(
            Family__c = fid, Owner_Member__c = me, Name = name, Report_Type__c = type, Filters__c = JSON.serialize(filters),
            Shared_With_Family__c = LedgerUtil.bool(body, 'shared')
        );
        insert as system r;
        AuditService.log(ctx, 'REPORT_SAVED', 'Saved_Report__c', r.Id, type);
        for (SavedReport d : savedReports(ctx)) {
            if (d.id == r.Id) {
                return d;
            }
        }
        return null;
    }

    /** The owner, or a Family Admin, can delete a saved report. */
    public static void deleteReport(UserContext ctx, Id reportId) {
        AccessGuard.require(ctx, 'REPORTS', 'READ');
        Id fid = ctx.familyId;
        List<Saved_Report__c> rows = reportId == null
            ? new List<Saved_Report__c>()
            : [SELECT Id, Owner_Member__c, Shared_With_Family__c FROM Saved_Report__c WHERE Id = :reportId AND Family__c = :fid WITH SYSTEM_MODE];
        if (rows.isEmpty() || (rows[0].Owner_Member__c != ctx.userId && !rows[0].Shared_With_Family__c)) {
            throw new PortalException('NOT_FOUND').withError('We couldn\'t find that record.');
        }
        if (rows[0].Owner_Member__c != ctx.userId && !ctx.isFamilyAdmin()) {
            throw new PortalException('NOT_AUTHORIZED').withError('Only the person who saved it or the Family Admin can delete it.');
        }
        delete as system rows;
    }

    // ------------------------------------------------------------------ dashboard layout

    public static List<Object> layout(UserContext ctx) {
        Id me = ctx.userId;
        Id fid = ctx.familyId;
        Portal_User__c u = [SELECT Dashboard_Layout__c FROM Portal_User__c WHERE Id = :me AND Family__c = :fid WITH SYSTEM_MODE];
        return String.isBlank(u.Dashboard_Layout__c) ? new List<Object>() : (List<Object>) JSON.deserializeUntyped(u.Dashboard_Layout__c);
    }

    /** body.widgets: [{ key, hidden }] in display order. */
    public static List<Object> saveLayout(UserContext ctx, Map<String, Object> body) {
        Object raw = body.get('widgets');
        if (!(raw instanceof List<Object>) || ((List<Object>) raw).size() > WIDGETS.size()) {
            throw new PortalException('VALIDATION').withError('Send the widgets as a list.');
        }
        List<Map<String, Object>> clean = new List<Map<String, Object>>();
        Set<String> seen = new Set<String>();
        for (Object item : (List<Object>) raw) {
            Map<String, Object> w = item instanceof Map<String, Object> ? (Map<String, Object>) item : new Map<String, Object>();
            String key = LedgerUtil.text(w, 'key');
            if (!WIDGETS.contains(key) || seen.contains(key)) {
                throw new PortalException('VALIDATION').withError('Unknown or repeated widget.');
            }
            seen.add(key);
            clean.add(new Map<String, Object>{ 'key' => key, 'hidden' => LedgerUtil.bool(w, 'hidden') });
        }
        update as system new Portal_User__c(Id = ctx.userId, Dashboard_Layout__c = JSON.serialize(clean));
        return layout(ctx);
    }

    // ------------------------------------------------------------------ monthly snapshots

    /** Writes the family and per-member summaries for one month (replacing any earlier snapshot). */
    public static Integer snapshot(Id familyId, Date month) {
        Date start = month.toStartOfMonth();
        Date finish = LedgerUtil.monthEnd(start);
        Map<String, Decimal[]> byMember = new Map<String, Decimal[]>{ 'family' => new List<Decimal>{ 0, 0 } };
        for (AggregateResult ar : [
            SELECT Member__c m, Type__c t, SUM(Amount__c) s FROM Transaction__c
            WHERE Family__c = :familyId AND Status__c != 'Void' AND Txn_Date__c >= :start AND Txn_Date__c <= :finish
                AND Type__c IN ('Income', 'Expense', 'Refund', 'Bill Payment')
            WITH SYSTEM_MODE GROUP BY Member__c, Type__c
        ]) {
            String key = ar.get('m') == null ? null : String.valueOf(ar.get('m'));
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            String type = (String) ar.get('t');
            Integer slot = type == 'Income' ? 0 : 1;
            Decimal signed = type == 'Refund' ? -amount : amount;
            for (String target : key == null ? new List<String>{ 'family' } : new List<String>{ 'family', key }) {
                Decimal[] row = byMember.containsKey(target) ? byMember.get(target) : new List<Decimal>{ 0, 0 };
                row[slot] += signed;
                byMember.put(target, row);
            }
        }
        Map<String, Decimal> byCategory = new Map<String, Decimal>();
        for (AggregateResult ar : [
            SELECT Category__r.Name c, Type__c t, SUM(Amount__c) s FROM Transaction__c
            WHERE Family__c = :familyId AND Status__c != 'Void' AND Txn_Date__c >= :start AND Txn_Date__c <= :finish
                AND Type__c IN ('Expense', 'Refund', 'Bill Payment')
            WITH SYSTEM_MODE GROUP BY Category__r.Name, Type__c
        ]) {
            String name = ar.get('c') == null ? 'Uncategorised' : (String) ar.get('c');
            Decimal amount = LedgerUtil.zeroIfNull(ar.get('s'));
            byCategory.put(name, (byCategory.containsKey(name) ? byCategory.get(name) : 0) + ((String) ar.get('t') == 'Refund' ? -amount : amount));
        }
        List<Monthly_Summary__c> rows = new List<Monthly_Summary__c>();
        for (String key : byMember.keySet()) {
            Decimal[] v = byMember.get(key);
            rows.add(new Monthly_Summary__c(
                Family__c = familyId, Member__c = key == 'family' ? null : (Id) key, Month__c = start, Income__c = v[0], Expense__c = v[1],
                Savings__c = v[0] - v[1], By_Category__c = key == 'family' ? JSON.serialize(byCategory) : null,
                Unique_Key__c = familyId + '-' + LedgerUtil.monthKey(start) + '-' + key
            ));
        }
        Database.upsert(rows, Monthly_Summary__c.Unique_Key__c, true, AccessLevel.SYSTEM_MODE);
        return rows.size();
    }

    /** Daily: snapshot the month that just closed, once. */
    public static Integer ensurePreviousMonth(Id familyId, Date today) {
        Date previous = today.toStartOfMonth().addMonths(-1);
        String key = familyId + '-' + LedgerUtil.monthKey(previous) + '-family';
        if ([SELECT COUNT() FROM Monthly_Summary__c WHERE Unique_Key__c = :key WITH SYSTEM_MODE] > 0) {
            return 0;
        }
        return snapshot(familyId, previous);
    }
}