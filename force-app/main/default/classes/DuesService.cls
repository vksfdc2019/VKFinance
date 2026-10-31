/** "Coming up": bills, EMIs and card bills due soon that the caller is allowed to see. */
public without sharing class DuesService {
    public static List<CommitmentDtos.DueItem> upcoming(UserContext ctx, Integer days) {
        Date today = Date.today();
        Date horizon = today.addDays(days);
        LedgerScope scope = new LedgerScope(ctx);
        CommitmentSelector selector = new CommitmentSelector(ctx);
        List<CommitmentDtos.DueItem> items = new List<CommitmentDtos.DueItem>();

        if (AccessGuard.can(ctx, 'BILLS', 'READ')) {
            Map<Id, Bill__c> bills = new Map<Id, Bill__c>(selector.bills(scope.wholeFamily() ? null : ctx.userId));
            Map<Id, Category__c> categories = new CategorySelector(ctx).byIdMap();
            for (Bill_Instance__c i : selector.instances(bills.keySet(), CommitmentSelector.OPEN_BILL, horizon)) {
                CommitmentDtos.BillInstance b = BillService.instance(ctx, i, bills.get(i.Bill__c), categories);
                items.add(item('bill', i.Id, i.Bill__c, b.billName, b.autoPay ? 'Auto-pay · ' + b.categoryName : b.categoryName,
                    LedgerUtil.zeroIfNull(i.Amount_Due__c) - LedgerUtil.zeroIfNull(i.Amount_Paid__c), i.Due_Date__c, b.status, b.icon, b.color, '/bills'));
            }
        }
        if (AccessGuard.can(ctx, 'LOANS', 'READ')) {
            Map<Id, Loan__c> loans = new Map<Id, Loan__c>(selector.loans(scope.wholeFamily() ? null : ctx.userId));
            Set<Id> seen = new Set<Id>();
            for (EMI_Installment__c i : selector.installments(loans.keySet(), CommitmentSelector.OPEN_EMI)) {
                if (i.Due_Date__c > horizon || seen.contains(i.Loan__c)) {
                    continue;
                }
                seen.add(i.Loan__c);
                Loan__c l = loans.get(i.Loan__c);
                items.add(item('emi', i.Id, l.Id, DuesProcessor.emiLabel(l.Name), 'Instalment ' + i.Installment_No__c.intValue() + (l.Auto_Debit__c ? ' · auto-debit' : ''),
                    i.EMI_Amount__c, i.Due_Date__c, i.Status__c, 'landmark', '#78716c', '/loans'));
            }
        }
        if (AccessGuard.can(ctx, 'ACCOUNTS', 'READ')) {
            Map<Id, Financial_Account__c> cards = new Map<Id, Financial_Account__c>();
            for (Financial_Account__c a : new AccountSelector(ctx).visible(false)) {
                if (a.Type__c == 'Credit Card') {
                    cards.put(a.Id, a);
                }
            }
            if (!cards.isEmpty()) {
                CardStatementService.generate(ctx.familyId, today);
                Map<Id, Card_Statement__c> latest = new Map<Id, Card_Statement__c>();
                for (Card_Statement__c st : selector.statements(cards.keySet(), 50)) {
                    if (!latest.containsKey(st.Account__c)) {
                        latest.put(st.Account__c, st);
                    }
                }
                for (Card_Statement__c st : latest.values()) {
                    CommitmentDtos.Statement d = CardStatementService.toDtos(new List<Card_Statement__c>{ st }, st.Account__c)[0];
                    if (d.status != 'Paid' && d.dueDate != null && d.dueDate <= horizon) {
                        items.add(item('card', st.Id, st.Account__c, cards.get(st.Account__c).Name + ' bill', 'Minimum ' + DuesProcessor.money(d.minimumDue),
                            d.amount - d.amountPaid, d.dueDate, d.status, 'credit-card', '#475569', '/accounts'));
                    }
                }
            }
        }
        items.sort(new ByDueDate());
        return items;
    }

    private static CommitmentDtos.DueItem item(
        String kind, Id recordId, Id parentId, String title, String subtitle, Decimal amount, Date due, String status, String icon, String color, String link
    ) {
        CommitmentDtos.DueItem d = new CommitmentDtos.DueItem();
        d.kind = kind;
        d.id = recordId;
        d.parentId = parentId;
        d.title = title;
        d.subtitle = subtitle;
        d.amount = amount;
        d.dueDate = due;
        d.daysLeft = CommitmentDtos.daysUntil(due);
        d.status = status;
        d.icon = icon;
        d.color = color;
        d.link = link;
        return d;
    }

    private class ByDueDate implements System.Comparator<CommitmentDtos.DueItem> {
        public Integer compare(CommitmentDtos.DueItem a, CommitmentDtos.DueItem b) {
            return a.dueDate < b.dueDate ? -1 : a.dueDate > b.dueDate ? 1 : 0;
        }
    }
}