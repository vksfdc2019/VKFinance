/** One active goal per account prevents double allocation. Progress always comes from the ledger balance. */
public without sharing class SavingsGoalService {
    private static final String FIELDS = 'Title__c, Target__c, Baseline__c, Target_Date__c, Account__c, Account__r.Name, ' +
        'Account__r.Current_Balance__c, Account__r.Owner_Member__c, Account__r.Is_Shared__c, Member__c, Status__c, Color__c';

    public static List<Map<String, Object>> listGoals(UserContext ctx) {
        EnhancementService.requireFeature(ctx, 'GOALS', 'READ');
        Set<Id> visible = new AccountSelector(ctx).visibleIds();
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Savings_Goal__c g : (List<Savings_Goal__c>) Database.queryWithBinds('SELECT ' + FIELDS +
            ' FROM Savings_Goal__c WHERE Family__c = :fid AND Account__c IN :ids AND Status__c = \'Active\' ORDER BY Target_Date__c NULLS LAST, CreatedDate DESC LIMIT 100',
            new Map<String, Object>{ 'fid' => ctx.familyId, 'ids' => visible }, AccessLevel.SYSTEM_MODE)) result.add(dto(ctx, g));
        return result;
    }

    public static Map<String, Object> save(UserContext ctx, Id goalId, Map<String, Object> body) {
        EnhancementService.requireFeature(ctx, 'GOALS', goalId == null ? 'CREATE' : 'EDIT');
        EnhancementService.lockFamily(ctx);
        Savings_Goal__c g = goalId == null ? new Savings_Goal__c(Family__c = ctx.familyId, Member__c = ctx.userId, Status__c = 'Active') :
            (Savings_Goal__c) EnhancementService.record(ctx, 'Savings_Goal__c', FIELDS, goalId, true);
        if (g.Status__c != 'Active') throw new PortalException('CONFLICT');
        if (goalId != null && !ctx.isAdmin() && g.Member__c != ctx.userId) throw new PortalException('NOT_AUTHORIZED');
        Id accountId = goalId == null ? VkfRest.toId(LedgerUtil.text(body, 'accountId')) : g.Account__c;
        Financial_Account__c a = TransactionService.usableAccount(ctx, accountId);
        if (LedgerUtil.isLiability(a.Type__c)) throw EnhancementService.invalid('Choose a savings or other asset account.');
        if (!ctx.isAdmin() && a.Owner_Member__c != ctx.userId) throw EnhancementService.invalid('Choose your own account for a goal.');
        if (goalId == null) {
            if ([SELECT COUNT() FROM Savings_Goal__c WHERE Family__c = :ctx.familyId AND Status__c = 'Active' WITH SYSTEM_MODE] >= 50)
                throw EnhancementService.invalid('Archive an existing goal before adding another.');
            if ([SELECT COUNT() FROM Savings_Goal__c WHERE Family__c = :ctx.familyId AND Account__c = :accountId AND Status__c = 'Active' WITH SYSTEM_MODE] > 0)
                throw EnhancementService.invalid('This account already funds a goal. Use a separate account to avoid counting savings twice.');
            g.Account__c = accountId; g.Account_Key__c = ctx.familyId + ':' + accountId;
            g.Baseline__c = LedgerUtil.bool(body, 'includeExisting') ? 0 : a.Current_Balance__c;
        }
        g.Title__c = EnhancementService.title(body, 'title', 80);
        g.Target__c = LedgerUtil.amount(LedgerUtil.dec(body, 'target', 'Target'), 'Target');
        g.Target_Date__c = LedgerUtil.dateValue(body, 'targetDate', 'Target date');
        if (g.Target_Date__c != null && g.Target_Date__c < Date.today()) throw EnhancementService.invalid('Choose today or a future target date.');
        String color = LedgerUtil.text(body, 'color');
        g.Color__c = new Set<String>{ 'teal', 'sky', 'violet', 'amber' }.contains(color) ? color : 'teal';
        if (goalId == null) insert as system g; else update as system g;
        AuditService.log(ctx, 'SAVINGS_GOAL_SAVED', 'Savings_Goal__c', g.Id, null);
        return dto(ctx, (Savings_Goal__c) EnhancementService.record(ctx, 'Savings_Goal__c', FIELDS, g.Id, false));
    }

    public static void archive(UserContext ctx, Id goalId) {
        EnhancementService.requireFeature(ctx, 'GOALS', 'DELETE');
        Savings_Goal__c g = (Savings_Goal__c) EnhancementService.record(ctx, 'Savings_Goal__c', FIELDS, goalId, true);
        if (!ctx.isAdmin() && g.Member__c != ctx.userId) throw new PortalException('NOT_FOUND');
        Financial_Account__c account = new AccountSelector(ctx).byId(g.Account__c);
        if (!new LedgerScope(ctx).canSeeAccount(account)) throw new PortalException('NOT_FOUND');
        update as system new Savings_Goal__c(Id = g.Id, Status__c = 'Archived', Account_Key__c = null);
        AuditService.log(ctx, 'SAVINGS_GOAL_ARCHIVED', 'Savings_Goal__c', g.Id, null);
    }

    private static Map<String, Object> dto(UserContext ctx, Savings_Goal__c g) {
        Decimal progress = Math.max(0, LedgerUtil.zeroIfNull(g.Account__r.Current_Balance__c) - LedgerUtil.zeroIfNull(g.Baseline__c));
        Integer months = g.Target_Date__c == null ? null : Math.max(1, (Date.today().daysBetween(g.Target_Date__c) + 29) / 30);
        return new Map<String, Object>{ 'id' => g.Id, 'title' => g.Title__c, 'target' => g.Target__c, 'progress' => progress,
            'percent' => Math.min(100, (progress / g.Target__c * 100).setScale(1)), 'accountId' => g.Account__c,
            'accountName' => g.Account__r.Name, 'targetDate' => g.Target_Date__c, 'color' => g.Color__c,
            'monthlyNeeded' => months == null ? null : (Math.max(0, g.Target__c - progress) / months).setScale(2),
            'canEdit' => ctx.role != 'Viewer' && (ctx.isAdmin() || g.Member__c == ctx.userId) };
    }
}