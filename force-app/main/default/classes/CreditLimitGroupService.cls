/** Shared facilities: one limit, live ledger balances, explicit membership and no hidden-card disclosure. */
public without sharing class CreditLimitGroupService {
    public virtual class GroupSummary {
        public Id id;
        public String name;
        public String issuer;
        public Decimal creditLimit;
        public Decimal outstanding = 0;
        public Decimal available;
        public Decimal utilisationPct;
        public Decimal overLimit;
        public Integer activeCardCount = 0;
        public Decimal version;
    }
    public class CardMember {
        public Id id;
        public String name;
        public String last4;
        public Decimal balance;
        public String status;
    }
    public class GroupView extends GroupSummary {
        public List<CardMember> cards = new List<CardMember>();
        public List<Id> cardIds = new List<Id>();
    }
    public class CreditTotals {
        public Decimal creditLimit = 0;
        public Decimal outstanding = 0;
        public Decimal available = 0;
        public Integer facilities = 0;
        public Integer restrictedCards = 0;
        public Boolean complete = true;
    }
    public class Overview {
        public List<GroupView> groups = new List<GroupView>();
        public CreditTotals totals;
        public Boolean canManage;
    }
    private class Snapshot {
        Map<Id, GroupView> groups = new Map<Id, GroupView>();
        Set<Id> restricted = new Set<Id>();
    }

    /** Two bulk queries, independent of transaction history; every card in a group must be visible. */
    private static Snapshot snapshot(UserContext ctx, Set<Id> ids) {
        Snapshot data = new Snapshot();
        if (ids.isEmpty()) return data;
        for (Credit_Limit_Group__c row : [
            SELECT Id, Name, Issuer__c, Credit_Limit__c, Version__c FROM Credit_Limit_Group__c
            WHERE Family__c = :ctx.familyId AND Id IN :ids AND Active__c = true
            WITH SYSTEM_MODE ORDER BY Name, Id
        ]) {
            GroupView g = new GroupView();
            g.id = row.Id; g.name = row.Name; g.issuer = row.Issuer__c;
            g.creditLimit = row.Credit_Limit__c; g.version = row.Version__c;
            data.groups.put(g.id, g);
        }
        LedgerScope scope = new LedgerScope(ctx);
        for (Financial_Account__c a : [
            SELECT Id, Name, Last4__c, Type__c, Status__c, Credit_Limit_Group__c, Current_Balance__c, Opening_Balance__c, Owner_Member__c, Is_Shared__c
            FROM Financial_Account__c WHERE Family__c = :ctx.familyId AND Credit_Limit_Group__c IN :ids
            WITH SYSTEM_MODE ORDER BY Name, Id
        ]) {
            Id groupId = a.Credit_Limit_Group__c;
            if (!scope.canSeeAccount(a) || a.Type__c != 'Credit Card') data.restricted.add(groupId);
            GroupView g = data.groups.get(groupId);
            if (g == null) continue;
            Decimal balance = a.Current_Balance__c == null ? LedgerUtil.zeroIfNull(a.Opening_Balance__c) : a.Current_Balance__c;
            CardMember member = new CardMember();
            member.id = a.Id; member.name = a.Name; member.last4 = a.Last4__c; member.balance = balance; member.status = a.Status__c;
            g.cards.add(member); g.cardIds.add(a.Id);
            // A refund credit on one card does not increase another card's spending power.
            g.outstanding += Math.max(0, balance);
            if (a.Status__c == 'Active') g.activeCardCount++;
        }
        for (GroupView g : data.groups.values()) {
            g.available = Math.max(0, g.creditLimit - g.outstanding);
            g.overLimit = Math.max(0, g.outstanding - g.creditLimit);
            g.utilisationPct = (g.outstanding / g.creditLimit * 100).setScale(1);
        }
        return data;
    }

    private static GroupSummary summary(GroupView g) {
        GroupSummary s = new GroupSummary();
        s.id = g.id; s.name = g.name; s.issuer = g.issuer; s.creditLimit = g.creditLimit;
        s.outstanding = g.outstanding; s.available = g.available; s.overLimit = g.overLimit;
        s.utilisationPct = g.utilisationPct; s.activeCardCount = g.activeCardCount; s.version = g.version;
        return s;
    }

    public static void attach(UserContext ctx, List<FinanceDtos.Account> accounts) {
        Set<Id> ids = new Set<Id>();
        for (FinanceDtos.Account a : accounts) if (a.creditLimitGroupId != null) ids.add(a.creditLimitGroupId);
        if (ids.isEmpty()) return;
        Snapshot data = snapshot(ctx, ids);
        for (FinanceDtos.Account a : accounts) {
            if (a.creditLimitGroupId == null) continue;
            // Never fall back to an independent limit if a linked facility is hidden or invalid.
            a.creditLimit = null;
            if (a.card != null) { a.card.available = null; a.card.utilisationPct = null; }
            GroupView g = data.groups.get(a.creditLimitGroupId);
            if (g == null || data.restricted.contains(a.creditLimitGroupId)) {
                a.sharedCreditRestricted = true;
                continue;
            }
            a.sharedCredit = summary(g); a.creditLimit = g.creditLimit;
            if (a.card != null) { a.card.available = g.available; a.card.utilisationPct = g.utilisationPct; }
        }
    }

    public static CreditTotals totals(List<FinanceDtos.Account> accounts) {
        CreditTotals result = new CreditTotals();
        Set<Id> counted = new Set<Id>();
        for (FinanceDtos.Account a : accounts) {
            if (a.type != 'Credit Card' || a.status != 'Active') continue;
            result.outstanding += Math.max(0, a.balance);
            if (a.creditLimitGroupId != null) {
                if (a.sharedCredit == null) { result.restrictedCards++; result.complete = false; continue; }
                if (counted.contains(a.creditLimitGroupId)) continue;
                counted.add(a.creditLimitGroupId);
                result.creditLimit += a.sharedCredit.creditLimit; result.available += a.sharedCredit.available;
            } else if (a.creditLimit != null) {
                result.creditLimit += a.creditLimit;
                result.available += Math.max(0, a.creditLimit - a.balance);
            } else { result.complete = false; }
            result.facilities++;
        }
        if (!result.complete) { result.creditLimit = null; result.available = null; }
        return result;
    }

    public static Overview overview(UserContext ctx) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'READ');
        Set<Id> ids = new Map<Id, Credit_Limit_Group__c>([
            SELECT Id FROM Credit_Limit_Group__c WHERE Family__c = :ctx.familyId AND Active__c = true WITH SYSTEM_MODE
        ]).keySet();
        Snapshot data = snapshot(ctx, ids);
        Overview result = new Overview(); result.canManage = canManage(ctx);
        for (GroupView g : data.groups.values()) {
            if (!data.restricted.contains(g.id) && (result.canManage || !g.cards.isEmpty())) result.groups.add(g);
        }
        List<FinanceDtos.Account> accounts = new List<FinanceDtos.Account>();
        LedgerScope scope = new LedgerScope(ctx);
        for (Financial_Account__c a : new AccountSelector(ctx).visible(true)) {
            FinanceDtos.Account dto = FinanceDtos.account(a, scope);
            if (dto.creditLimitGroupId != null && !data.restricted.contains(dto.creditLimitGroupId) && data.groups.containsKey(dto.creditLimitGroupId)) {
                dto.sharedCredit = summary(data.groups.get(dto.creditLimitGroupId));
            }
            accounts.add(dto);
        }
        result.totals = totals(accounts);
        return result;
    }

    public static Boolean canManage(UserContext ctx) {
        return ctx.isAdmin() && AccessGuard.can(ctx, 'ACCOUNTS', 'EDIT');
    }

    /** Family lock serializes membership changes; version rejects stale browser edits. No ledger writes. */
    public static Overview save(UserContext ctx, Id groupId, Map<String, Object> body, Boolean archive) {
        AccessGuard.require(ctx, 'ACCOUNTS', 'EDIT');
        if (!ctx.isAdmin()) throw new PortalException('NOT_AUTHORIZED').withError('Only family administrators can manage shared limits.');
        List<Family__c> locked = [SELECT Id FROM Family__c WHERE Id = :ctx.familyId WITH SYSTEM_MODE FOR UPDATE];
        Credit_Limit_Group__c groupRow;
        if (groupId == null) {
            if (archive) throw new PortalException('BAD_REQUEST');
            if ([SELECT COUNT() FROM Credit_Limit_Group__c WHERE Family__c = :ctx.familyId AND Active__c = true WITH SYSTEM_MODE] >= 50)
                throw invalid('Your family can have up to 50 active credit-limit groups.');
            groupRow = new Credit_Limit_Group__c(Family__c = ctx.familyId, Active__c = true, Version__c = 1);
        } else {
            List<Credit_Limit_Group__c> rows = [SELECT Id, Name, Family__c, Active__c, Version__c FROM Credit_Limit_Group__c
                WHERE Id = :groupId AND Family__c = :ctx.familyId WITH SYSTEM_MODE FOR UPDATE];
            if (rows.isEmpty()) throw new PortalException('NOT_FOUND');
            groupRow = rows[0];
            if (!groupRow.Active__c) throw new PortalException('CONFLICT').withError('This group is archived.');
            if (LedgerUtil.dec(body, 'expectedVersion', 'Version') != groupRow.Version__c)
                throw new PortalException('CONFLICT').withError('This group changed since you opened it. Refresh and review the latest cards and limit.');
            groupRow.Version__c++;
        }
        List<Financial_Account__c> accounts = new AccountSelector(ctx).inFamily(true);
        Set<Id> selected = new Set<Id>();
        if (!archive) {
            Object raw = body.get('cardIds');
            if (!(raw instanceof List<Object>)) throw invalid('Choose the cards that share this limit.');
            if (((List<Object>) raw).size() > 100) throw invalid('Choose up to 100 cards.');
            for (Object value : (List<Object>) raw) {
                Id cardId = VkfRest.toId(value == null ? null : String.valueOf(value));
                if (cardId == null) throw invalid('Choose valid card accounts.');
                selected.add(cardId);
            }
            if (selected.isEmpty()) throw invalid('Choose at least one card.');
            String name = LedgerUtil.limited(LedgerUtil.text(body, 'name'), 80, 'Group name');
            if (String.isBlank(name)) throw invalid('Enter a group name.');
            groupRow.Name = name.trim();
            groupRow.Issuer__c = LedgerUtil.limited(LedgerUtil.text(body, 'issuer'), 80, 'Issuer');
            groupRow.Credit_Limit__c = LedgerUtil.amount(LedgerUtil.dec(body, 'creditLimit', 'Shared limit'), 'Shared limit');
            if (groupRow.Credit_Limit__c <= 0) throw invalid('Shared limit must be at least 0.01.');
            if ([SELECT COUNT() FROM Credit_Limit_Group__c WHERE Family__c = :ctx.familyId AND Active__c = true
                AND Name = :groupRow.Name AND Id != :groupId WITH SYSTEM_MODE] > 0) throw invalid('An active group already uses this name.');
            Set<Id> found = new Set<Id>();
            for (Financial_Account__c a : accounts) {
                if (!selected.contains(a.Id)) continue;
                found.add(a.Id);
                if (a.Type__c != 'Credit Card') throw invalid('Only credit-card accounts can share a credit limit.');
                if (a.Status__c != 'Active' && (groupId == null || a.Credit_Limit_Group__c != groupId)) throw invalid('A closed card cannot join a group.');
                if (a.Credit_Limit_Group__c != null && a.Credit_Limit_Group__c != groupId)
                    throw new PortalException('CONFLICT').withError('A selected card already belongs to another group. Remove it there first.');
            }
            if (found.size() != selected.size()) throw new PortalException('NOT_FOUND').withError('One or more cards could not be found.');
        }
        // Detach first on archive, so there is never a linked card in an inactive facility.
        if (groupId == null) { insert as system groupRow; groupId = groupRow.Id; }
        List<Financial_Account__c> changes = new List<Financial_Account__c>();
        for (Financial_Account__c a : accounts) {
            Id next = selected.contains(a.Id) ? groupId : (a.Credit_Limit_Group__c == groupId ? null : a.Credit_Limit_Group__c);
            if (next != a.Credit_Limit_Group__c) changes.add(new Financial_Account__c(Id = a.Id, Credit_Limit_Group__c = next));
        }
        if (!changes.isEmpty()) update as system changes;
        if (archive) groupRow.Active__c = false;
        update as system groupRow;
        AuditService.log(ctx, archive ? 'CREDIT_GROUP_ARCHIVED' : 'CREDIT_GROUP_SAVED', 'Credit_Limit_Group__c', groupId,
            archive ? 'Cards returned to independent limits; balances unchanged' : groupRow.Name + ': ' + selected.size() + ' cards; limit ' + groupRow.Credit_Limit__c);
        return overview(ctx);
    }

    private static PortalException invalid(String message) { return new PortalException('VALIDATION').withError(message); }
}