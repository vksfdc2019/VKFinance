/**
 * Read-only view of archived months for the portal. The same rules as the live ledger apply:
 * TRANSACTIONS:READ, the family boundary, and LedgerScope (Members see own and shared
 * accounts, Children their own, family Viewers everything, others only their own entries).
 */
public without sharing class ArchiveViewService {
    public class Month {
        public String month;
        public Integer transactions;
    }

    public class Summary {
        public Date archivedThrough;
        public List<Month> months = new List<Month>();
    }

    public class Entry {
        public String id;
        public String entryNo;
        public String txnDate;
        public String type;
        public String direction;
        public Decimal amount;
        public String status;
        public String accountName;
        public String categoryName;
        public String memberName;
        public String payee;
        public String notes;
        public String paymentMode;
        public String reference;
    }

    public class MonthView {
        public String month;
        /** Same rules as the reports: income in; expenses and bill payments out, less refunds. */
        public Decimal income = 0;
        public Decimal spending = 0;
        public List<Entry> entries = new List<Entry>();
    }

    public static Summary summary(UserContext ctx) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'READ');
        Summary s = new Summary();
        Id fid = ctx.familyId;
        s.archivedThrough = [SELECT Archived_Through__c FROM Family__c WHERE Id = :fid WITH SYSTEM_MODE].Archived_Through__c;
        for (Archive_Log__c log : [
            SELECT Month__c, Counts__c FROM Archive_Log__c WHERE Family__c = :fid WITH SYSTEM_MODE ORDER BY Month__c DESC LIMIT 240
        ]) {
            Integer txns = 0;
            if (String.isNotBlank(log.Counts__c)) {
                Object n = ((Map<String, Object>) JSON.deserializeUntyped(log.Counts__c)).get(ArchiveService.TXN);
                txns = n == null ? 0 : Integer.valueOf(n);
            }
            if (txns > 0) {
                Month m = new Month();
                m.month = ArchiveService.monthKey(log.Month__c);
                m.transactions = txns;
                s.months.add(m);
            }
        }
        return s;
    }

    public static MonthView month(UserContext ctx, String monthKey) {
        AccessGuard.require(ctx, 'TRANSACTIONS', 'READ');
        if (monthKey == null || !Pattern.matches('\\d{4}-(0[1-9]|1[0-2])', monthKey)) {
            throw new PortalException('VALIDATION').withError('Choose a month like 2026-07.');
        }
        // The big-object read comes first, before anything else can write in this request.
        List<Archive_Record__b> rows = ArchiveStore.monthOfType(ctx.familyId, monthKey, ArchiveService.TXN);
        LedgerScope scope = new LedgerScope(ctx);
        Set<Id> visibleAccounts = new Set<Id>();
        Id fid = ctx.familyId;
        for (Financial_Account__c a : [SELECT Id, Owner_Member__c, Is_Shared__c FROM Financial_Account__c WHERE Family__c = :fid WITH SYSTEM_MODE]) {
            if (scope.canSeeAccount(a)) {
                visibleAccounts.add(a.Id);
            }
        }
        String me = String.valueOf(ctx.userId);
        MonthView view = new MonthView();
        view.month = monthKey;
        for (Archive_Record__b r : rows) {
            Map<String, Object> p = (Map<String, Object>) JSON.deserializeUntyped(r.Payload__c);
            String accountId = (String) p.get('accountId');
            Boolean visible = scope.wholeFamily() || (String) p.get('memberId') == me
                || (accountId != null && visibleAccounts.contains(Id.valueOf(accountId)));
            if (!visible) {
                continue;
            }
            Entry e = new Entry();
            e.id = r.Record_Id__c;
            e.entryNo = (String) p.get('number');
            e.txnDate = (String) p.get('date');
            e.type = (String) p.get('type');
            e.direction = (String) p.get('direction');
            e.amount = p.get('amount') == null ? 0 : Decimal.valueOf(String.valueOf(p.get('amount')));
            e.status = (String) p.get('status');
            e.accountName = (String) p.get('account');
            e.categoryName = (String) p.get('category');
            e.memberName = (String) p.get('member');
            e.payee = (String) p.get('payee');
            e.notes = (String) p.get('notes');
            e.paymentMode = (String) p.get('paymentMode');
            e.reference = (String) p.get('reference');
            view.entries.add(e);
            if (e.status != 'Void') {
                if (e.type == 'Income') {
                    view.income += e.amount;
                } else if (e.type == 'Expense' || e.type == 'Bill Payment') {
                    view.spending += e.amount;
                } else if (e.type == 'Refund') {
                    view.spending -= e.amount;
                }
            }
        }
        view.entries.sort(new NewestFirst());
        return view;
    }

    private class NewestFirst implements System.Comparator<Entry> {
        public Integer compare(Entry a, Entry b) {
            String ka = (a.txnDate == null ? '' : a.txnDate) + (a.entryNo == null ? '' : a.entryNo);
            String kb = (b.txnDate == null ? '' : b.txnDate) + (b.entryNo == null ? '' : b.entryNo);
            return ka == kb ? 0 : (ka < kb ? 1 : -1);
        }
    }
}
