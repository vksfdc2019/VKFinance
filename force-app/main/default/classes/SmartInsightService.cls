/** Explainable, scoped rules. No external model, automatic cancellation or financial writes. */
public without sharing class SmartInsightService {
    public static List<Map<String, Object>> insights(UserContext ctx) {
        EnhancementService.requireFeature(ctx, 'INSIGHTS', 'READ');
        Date today = Date.today();
        BudgetMonth.Period period = BudgetMonth.containing(ctx.familyId, today);
        Date month = period.startDate;
        Integer elapsed = month.daysBetween(today) + 1;
        TransactionSelector selector = new TransactionSelector(ctx);
        TransactionSelector.Filter filter = selector.scoped();
        filter.types = new Set<String>{ 'Expense', 'Bill Payment', 'Refund' };
        filter.fromDate = BudgetMonth.of(ctx.familyId, period.anchor.addMonths(-3)).startDate; filter.toDate = month.addDays(-1);
        Map<Id, Decimal> baseline = categoryTotals(selector, filter);
        filter.fromDate = month; filter.toDate = today;
        Map<Id, Decimal> current = categoryTotals(selector, filter);
        Map<Id, Category__c> categories = new CategorySelector(ctx).byIdMap();
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        if (elapsed >= 7) {
            for (Id categoryId : current.keySet()) {
                Decimal average = (baseline.containsKey(categoryId) ? baseline.get(categoryId) : 0) / 3;
                Decimal expected = average * elapsed / period.days();
                Decimal actual = current.get(categoryId);
                if (average >= 300 && actual > expected * 1.5 && actual - expected >= 300 && categories.containsKey(categoryId)) {
                    String name = categories.get(categoryId).Name;
                    result.add(tip('PACE:' + period.key + ':' + categoryId, 'Spending pace', name + ' is running ahead',
                        'Spending is above the same-day pace implied by the previous three complete months. A planned one-off purchase can explain this.',
                        actual, expected.setScale(2), '/reports/category?categoryId=' + categoryId, 'warning'));
                }
            }
        }
        Set<Id> visible = new AccountSelector(ctx).visibleIds();
        List<Recurring_Rule__c> rules = [SELECT Id, Name, Amount__c, Frequency__c FROM Recurring_Rule__c
            WHERE Family__c = :ctx.familyId AND Account__c IN :visible AND Active__c = TRUE AND Type__c = 'Expense'
            WITH SYSTEM_MODE ORDER BY Amount__c DESC LIMIT 5];
        for (Recurring_Rule__c rule : rules) {
            Decimal monthly = rule.Frequency__c == 'Weekly' ? rule.Amount__c * 52 / 12 : rule.Frequency__c == 'Quarterly' ? rule.Amount__c / 3 :
                rule.Frequency__c == 'Yearly' ? rule.Amount__c / 12 : rule.Amount__c;
            result.add(tip('REPEAT:' + period.key + ':' + rule.Id, 'Recurring review', 'Still using ' + rule.Name + '?',
                'This active recurring expense is a candidate for review. The app cannot determine whether you use the service; nothing is cancelled automatically.',
                monthly.setScale(2), null, '/recurring', 'info'));
        }
        Set<String> hidden = new Set<String>();
        for (Insight_Preference__c preference : [SELECT Insight_Key__c FROM Insight_Preference__c
            WHERE Family__c = :ctx.familyId AND Member__c = :ctx.userId AND Hidden_Until__c >= :today WITH SYSTEM_MODE LIMIT 200]) hidden.add(preference.Insight_Key__c);
        List<Map<String, Object>> shown = new List<Map<String, Object>>();
        for (Map<String, Object> item : result) if (!hidden.contains((String) item.get('key')) && shown.size() < 12) shown.add(item);
        return shown;
    }

    private static Map<Id, Decimal> categoryTotals(TransactionSelector selector, TransactionSelector.Filter filter) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        // Separate refunds to bound group count to the existing 1,000-category cap.
        for (Boolean refunds : new List<Boolean>{false, true}) {
            filter.types = refunds ? new Set<String>{'Refund'} : new Set<String>{'Expense','Bill Payment'};
            for (AggregateResult ar : selector.aggregate('Category__c cat, SUM(Amount__c) amount', filter, 'Category__c')) {
                Id categoryId = (Id) ar.get('cat');
                Decimal amount = LedgerUtil.zeroIfNull(ar.get('amount')) * (refunds ? -1 : 1);
                totals.put(categoryId, (totals.containsKey(categoryId) ? totals.get(categoryId) : 0) + amount);
            }
        }
        return totals;
    }

    public static void dismiss(UserContext ctx, Map<String, Object> body) {
        EnhancementService.requireFeature(ctx, 'INSIGHTS', 'READ');
        String key = EnhancementService.title(body, 'key', 120);
        if (!key.startsWith('PACE:') && !key.startsWith('REPEAT:')) throw EnhancementService.invalid('Unknown insight key.');
        // Validate against this viewer's current insights, never accept another viewer's raw entity id.
        Boolean exists = false;
        for (Map<String, Object> item : insights(ctx)) if (item.get('key') == key) exists = true;
        if (!exists) throw new PortalException('NOT_FOUND');
        String uniqueKey = TokenService.hash(ctx.familyId + ':' + ctx.userId + ':' + key);
        Date untilDate = Date.today().addDays(LedgerUtil.bool(body, 'snooze') ? 7 : 31);
        Insight_Preference__c preference = new Insight_Preference__c(Family__c = ctx.familyId, Member__c = ctx.userId,
            Insight_Key__c = key, Unique_Key__c = uniqueKey, Hidden_Until__c = untilDate);
        List<Insight_Preference__c> prior = [SELECT Id FROM Insight_Preference__c WHERE Family__c = :ctx.familyId AND Unique_Key__c = :uniqueKey WITH SYSTEM_MODE LIMIT 1];
        if (!prior.isEmpty()) preference.Id = prior[0].Id;
        if (preference.Id == null) insert as system preference; else update as system preference;
    }

    private static Map<String, Object> tip(String key, String kind, String title, String explanation, Decimal actual, Decimal baseline, String link, String severity) {
        return new Map<String, Object>{ 'key' => key, 'kind' => kind, 'title' => title, 'explanation' => explanation,
            'actual' => actual, 'baseline' => baseline, 'link' => link, 'severity' => severity };
    }
}