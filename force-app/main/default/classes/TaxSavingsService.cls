/**
 * The financial year's tax-saving picture for each person (the limits apply per taxpayer):
 *   80C (up to Rs 1.5 lakh)  - PPF, SSY, NSC, SCSS, 5-year Post Office TD, EPF/VPF, tax-saver FDs,
 *                              and life premiums (each up to 10% of its sum assured);
 *   80CCD(1B) (Rs 50,000)    - own NPS contributions; anything over Rs 50,000 can count under 80C;
 *   80D (Rs 25,000)          - health premiums for self and family (Rs 50,000 if a senior citizen).
 * These deductions are for the old tax regime; the new regime (the default) does not allow them.
 */
public without sharing class TaxSavingsService {
    public static List<SavingsDtos.TaxSummary> summaries(UserContext ctx, List<SavingsDtos.Scheme> schemes, List<SavingsDtos.Policy> policies) {
        Date today = Date.today();
        Date fyStart = DepositCalculator.financialYearStart(today);
        Date fyEnd = fyStart.addYears(1).addDays(-1);
        Map<Id, SavingsDtos.TaxSummary> byOwner = new Map<Id, SavingsDtos.TaxSummary>();

        Decimal npsOverflow = 0;
        for (SavingsDtos.Scheme s : schemes) {
            if (s.contributedThisYear == null || s.contributedThisYear <= 0 || s.ownerId == null) {
                continue;
            }
            SavingsDtos.TaxSummary t = summary(byOwner, s.ownerId, s.ownerName, fyStart, fyEnd);
            String label = s.schemeLabel + (s.name == null || s.name == s.scheme ? '' : ' · ' + s.name);
            if (s.scheme == 'NPS') {
                Decimal room = t.limit80CCD1B - t.section80CCD1B;
                Decimal toNps = Math.min(room, s.contributedThisYear);
                t.section80CCD1B += toNps;
                if (s.contributedThisYear > toNps) {
                    t.items80C.add(new SavingsDtos.TaxLine(label + ' (over Rs 50,000)', s.contributedThisYear - toNps));
                }
            } else if (s.taxSection == '80C') {
                t.items80C.add(new SavingsDtos.TaxLine(label, s.contributedThisYear));
            }
        }

        Map<Id, SavingsDtos.Policy> byBill = new Map<Id, SavingsDtos.Policy>();
        for (SavingsDtos.Policy p : policies) {
            if (p.billId != null && (p.taxSection == '80C' || p.taxSection == '80D')) {
                byBill.put(p.billId, p);
            }
        }
        if (!byBill.isEmpty()) {
            Id fid = ctx.familyId;
            Set<Id> billIds = byBill.keySet();
            for (AggregateResult ar : [
                SELECT Bill__c b, SUM(Amount_Paid__c) s
                FROM Bill_Instance__c
                WHERE Family__c = :fid AND Bill__c IN :billIds AND Paid_On__c >= :fyStart AND Paid_On__c <= :fyEnd
                WITH SYSTEM_MODE
                GROUP BY Bill__c
            ]) {
                SavingsDtos.Policy p = byBill.get((Id) ar.get('b'));
                Decimal paid = LedgerUtil.zeroIfNull(ar.get('s'));
                if (paid <= 0 || p.ownerId == null) {
                    continue;
                }
                SavingsDtos.TaxSummary t = summary(byOwner, p.ownerId, p.ownerName, fyStart, fyEnd);
                String label = p.insurer + (p.planName == null ? '' : ' · ' + p.planName);
                if (p.taxSection == '80D') {
                    t.items80D.add(new SavingsDtos.TaxLine(label, paid));
                    t.section80D += paid;
                } else {
                    Boolean capped = p.sumAssured != null && p.sumAssured > 0 && p.startDate != null && p.startDate >= Date.newInstance(2012, 4, 1);
                    t.items80C.add(new SavingsDtos.TaxLine(label, capped ? Math.min(paid, p.sumAssured * 0.1) : paid));
                }
            }
        }

        // Tax-saver FDs opened this year, on accounts the caller can see.
        Set<Id> visible = new AccountSelector(ctx).visibleIds();
        Id fid = ctx.familyId;
        for (Deposit__c d : [
            SELECT Principal__c, Account__r.Name, Account__r.Owner_Member__c, Account__r.Owner_Member__r.First_Name__c, Account__r.Owner_Member__r.Last_Name__c
            FROM Deposit__c
            WHERE Family__c = :fid AND Account__c IN :visible AND Tax_Saver__c = true AND Start_Date__c >= :fyStart AND Start_Date__c <= :fyEnd
            WITH SYSTEM_MODE
        ]) {
            if (d.Principal__c == null || d.Account__r.Owner_Member__c == null) {
                continue;
            }
            String owner = FinanceDtos.personName(d.Account__r.Owner_Member__r.First_Name__c, d.Account__r.Owner_Member__r.Last_Name__c);
            summary(byOwner, d.Account__r.Owner_Member__c, owner, fyStart, fyEnd).items80C.add(new SavingsDtos.TaxLine('Tax-saver FD · ' + d.Account__r.Name, d.Principal__c));
        }

        List<SavingsDtos.TaxSummary> result = new List<SavingsDtos.TaxSummary>();
        if (byOwner.containsKey(ctx.userId)) {
            result.add(byOwner.remove(ctx.userId));
        }
        result.addAll(byOwner.values());
        for (SavingsDtos.TaxSummary t : result) {
            for (SavingsDtos.TaxLine l : t.items80C) {
                t.section80C += l.amount;
            }
        }
        return result;
    }

    private static SavingsDtos.TaxSummary summary(Map<Id, SavingsDtos.TaxSummary> byOwner, Id ownerId, String ownerName, Date fyStart, Date fyEnd) {
        SavingsDtos.TaxSummary t = byOwner.get(ownerId);
        if (t == null) {
            t = new SavingsDtos.TaxSummary();
            t.ownerId = ownerId;
            t.ownerName = ownerName;
            t.financialYear = DepositCalculator.financialYearLabel(fyStart);
            t.fromDate = fyStart;
            t.toDate = fyEnd;
            byOwner.put(ownerId, t);
        }
        return t;
    }
}
