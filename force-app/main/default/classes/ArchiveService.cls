/**
 * Moves old records out of the 5 MB data storage into the Archive_Record__b big object (with a
 * Google Sheet copy made by ArchiveExporter), then removes the originals.
 *
 *   collect() - what belongs in the archive and isn't there yet (or changed since). Ledger
 *               records qualify once their month is older than the live window (current month
 *               plus Live_Months__c, so reports and insights still read three full months);
 *               ended sessions and read notifications are copied as they happen, because the
 *               existing cleanup jobs delete those after a few days.
 *   purge()    - after the grace period, and only once the month is safely copied, deletes the
 *               archived transactions, decided spend requests and old statement imports. The
 *               deleted transactions' net effect moves into Financial_Account__c.Archived_Net__c,
 *               so every balance stays exactly the same.
 *
 * Transactions with receipt photos stay live (their files are separate storage). Entries dated
 * on or before Family__c.Archived_Through__c can't be added or changed (assertOpen), so a month
 * can't change between being copied and being removed.
 *
 * Never archived: password hashes and salts, two-step keys, recovery codes, session tokens.
 */
public without sharing class ArchiveService {
    public static final String TXN = 'Transaction';
    public static final String REQUEST = 'SpendRequest';
    public static final String STATEMENT = 'StatementImport';
    public static final String SESSION = 'Session';
    public static final String NOTICE = 'Notification';
    public static final String ACCOUNT = 'Account';
    public static final String MEMBER = 'Member';
    public static final String BILL = 'BillInstance';
    public static final String EMI = 'EmiInstallment';
    public static final Integer MAX_PER_TYPE = 2000;
    public static final Integer MAX_MONTHS = 12;

    @TestVisible
    private static Archive_Policy__mdt policy;

    // ---------- Policy ----------

    public static Archive_Policy__mdt policy() {
        if (policy == null) {
            List<Archive_Policy__mdt> rows = [
                SELECT Live_Months__c, Grace_Days__c, Google_Copy__c, Folder_Name__c
                FROM Archive_Policy__mdt WHERE DeveloperName = 'Default' WITH SYSTEM_MODE LIMIT 1
            ];
            policy = rows.isEmpty() ? new Archive_Policy__mdt(Google_Copy__c = true) : rows[0];
        }
        return policy;
    }

    /** Never fewer than three: reports and insights read the last three full months from the live ledger. */
    public static Integer liveMonths() {
        return Math.max(3, policy().Live_Months__c == null ? 3 : policy().Live_Months__c.intValue());
    }

    public static Integer graceDays() {
        return policy().Grace_Days__c == null ? 7 : Math.max(0, policy().Grace_Days__c.intValue());
    }

    public static Boolean googleCopy() {
        return policy().Google_Copy__c == true;
    }

    public static String folderName() {
        return String.isBlank(policy().Folder_Name__c) ? 'VKFinance Archive' : policy().Folder_Name__c;
    }

    /** First day of the oldest month that stays live. Ledger records dated before it are archived. */
    public static Date cutoff(Date today) {
        return today.toStartOfMonth().addMonths(-liveMonths());
    }

    public static String monthKey(Date d) {
        return LedgerUtil.monthKey(d);
    }

    public static Date monthStart(String key) {
        return Date.newInstance(Integer.valueOf(key.left(4)), Integer.valueOf(key.right(2)), 1);
    }

    public static String logKey(Id familyId, String monthKey) {
        return familyId + '-' + monthKey;
    }

    // ---------- Collect ----------

    public class Collected {
        public List<Archive_Record__b> rows = new List<Archive_Record__b>();
        /** Months that gained new or changed records in this pass. */
        public Set<String> touched = new Set<String>();
    }

    private class Candidate {
        String type;
        Id recordId;
        String month;
        Datetime recordDate;
        Datetime modified;
        Map<String, Object> payload;
        Candidate(String type, Id recordId, Date month, Datetime recordDate, Datetime modified, Map<String, Object> payload) {
            this.type = type;
            this.recordId = recordId;
            this.month = monthKey(month);
            this.recordDate = recordDate;
            this.modified = modified;
            this.payload = payload;
        }
    }

    /**
     * Everything of one family that should be archived and isn't yet. Reads only (big-object
     * reads included), so the caller can write the rows with ArchiveStore.save() afterwards.
     */
    public static Collected collect(Id familyId, Date today) {
        Date cut = cutoff(today);
        Datetime cutAt = Datetime.newInstance(cut, Time.newInstance(0, 0, 0, 0));
        List<Candidate> found = new List<Candidate>();

        for (Transaction__c t : [
            SELECT Id, Name, Txn_Date__c, Type__c, Direction__c, Amount__c, Status__c, Account__c, Account__r.Name, Category__c,
                Category__r.Name, Member__c, Member__r.First_Name__c, Member__r.Last_Name__c, Payee__c, Notes__c, Payment_Mode__c,
                Reference_No__c, Source__c, Transfer_Group_Id__c, CreatedDate, LastModifiedDate
            FROM Transaction__c
            WHERE Family__c = :familyId AND Txn_Date__c < :cut
            WITH SYSTEM_MODE ORDER BY Txn_Date__c LIMIT :MAX_PER_TYPE
        ]) {
            found.add(new Candidate(TXN, t.Id, t.Txn_Date__c, Datetime.newInstance(t.Txn_Date__c, Time.newInstance(12, 0, 0, 0)), t.LastModifiedDate, new Map<String, Object>{
                'number' => t.Name, 'date' => t.Txn_Date__c, 'type' => t.Type__c, 'direction' => t.Direction__c, 'amount' => t.Amount__c,
                'status' => t.Status__c, 'accountId' => t.Account__c, 'account' => t.Account__r?.Name, 'categoryId' => t.Category__c,
                'category' => t.Category__r?.Name, 'memberId' => t.Member__c, 'member' => fullName(t.Member__r), 'payee' => t.Payee__c,
                'notes' => t.Notes__c, 'paymentMode' => t.Payment_Mode__c, 'reference' => t.Reference_No__c, 'source' => t.Source__c,
                'transferGroup' => t.Transfer_Group_Id__c, 'createdAt' => t.CreatedDate
            }));
        }

        for (Spend_Request__c r : [
            SELECT Id, Title__c, Amount__c, Status__c, Child__r.First_Name__c, Child__r.Last_Name__c, Account__r.Name, Category__r.Name,
                Valid_Until__c, Decided_At__c, Decided_By__r.First_Name__c, Decided_By__r.Last_Name__c, Decision_Note__c, Note__c,
                Transaction__c, CreatedDate, LastModifiedDate
            FROM Spend_Request__c
            WHERE Family__c = :familyId AND CreatedDate < :cutAt AND Status__c != 'Pending'
            WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT :MAX_PER_TYPE
        ]) {
            found.add(new Candidate(REQUEST, r.Id, r.CreatedDate.date(), r.CreatedDate, r.LastModifiedDate, new Map<String, Object>{
                'title' => r.Title__c, 'amount' => r.Amount__c, 'status' => r.Status__c, 'child' => fullName(r.Child__r),
                'account' => r.Account__r?.Name, 'category' => r.Category__r?.Name, 'validUntil' => r.Valid_Until__c,
                'decidedAt' => r.Decided_At__c, 'decidedBy' => fullName(r.Decided_By__r), 'decisionNote' => r.Decision_Note__c,
                'note' => r.Note__c, 'transactionId' => r.Transaction__c, 'createdAt' => r.CreatedDate
            }));
        }

        for (Statement_Import__c s : [
            SELECT Id, Name, File_Name__c, Status__c, Account__r.Name, Member__r.First_Name__c, Member__r.Last_Name__c, Total__c,
                Imported__c, Duplicates__c, Failed__c, Error__c, CreatedDate, LastModifiedDate
            FROM Statement_Import__c
            WHERE Family__c = :familyId AND CreatedDate < :cutAt AND Status__c IN ('Archived', 'Completed', 'Cancelled')
            WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT :MAX_PER_TYPE
        ]) {
            found.add(new Candidate(STATEMENT, s.Id, s.CreatedDate.date(), s.CreatedDate, s.LastModifiedDate, new Map<String, Object>{
                'number' => s.Name, 'fileName' => s.File_Name__c, 'status' => s.Status__c, 'account' => s.Account__r?.Name,
                'member' => fullName(s.Member__r), 'total' => s.Total__c, 'imported' => s.Imported__c, 'duplicates' => s.Duplicates__c,
                'failed' => s.Failed__c, 'error' => s.Error__c, 'createdAt' => s.CreatedDate
            }));
        }

        // Token and user-agent hashes are left out on purpose.
        for (Portal_Session__c s : [
            SELECT Id, Portal_User__r.First_Name__c, Portal_User__r.Last_Name__c, Status__c, Scope__c, Revoke_Reason__c, User_Agent__c,
                Last_Activity__c, Ended_At__c, Expires_At__c, CreatedDate, LastModifiedDate
            FROM Portal_Session__c
            WHERE Family__c = :familyId AND Status__c != 'Active'
            WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT :MAX_PER_TYPE
        ]) {
            found.add(new Candidate(SESSION, s.Id, s.CreatedDate.date(), s.CreatedDate, s.LastModifiedDate, new Map<String, Object>{
                'member' => fullName(s.Portal_User__r), 'status' => s.Status__c, 'scope' => s.Scope__c, 'startedAt' => s.CreatedDate,
                'lastActivity' => s.Last_Activity__c, 'endedAt' => s.Ended_At__c, 'expiresAt' => s.Expires_At__c,
                'endReason' => s.Revoke_Reason__c, 'device' => s.User_Agent__c
            }));
        }

        for (Notification__c n : [
            SELECT Id, Title__c, Message__c, Type__c, Severity__c, Link__c, Recipient__r.First_Name__c, Recipient__r.Last_Name__c,
                CreatedDate, LastModifiedDate
            FROM Notification__c
            WHERE Family__c = :familyId AND Is_Read__c = TRUE
            WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT :MAX_PER_TYPE
        ]) {
            found.add(new Candidate(NOTICE, n.Id, n.CreatedDate.date(), n.CreatedDate, n.LastModifiedDate, new Map<String, Object>{
                'title' => n.Title__c, 'message' => n.Message__c, 'type' => n.Type__c, 'severity' => n.Severity__c,
                'recipient' => fullName(n.Recipient__r), 'link' => n.Link__c, 'createdAt' => n.CreatedDate
            }));
        }

        for (Bill_Instance__c b : [
            SELECT Id, Bill__r.Name, Due_Date__c, Amount_Due__c, Amount_Paid__c, Status__c, Paid_On__c, LastModifiedDate
            FROM Bill_Instance__c
            WHERE Family__c = :familyId AND Due_Date__c < :cut
            WITH SYSTEM_MODE ORDER BY Due_Date__c LIMIT :MAX_PER_TYPE
        ]) {
            found.add(new Candidate(BILL, b.Id, b.Due_Date__c, Datetime.newInstance(b.Due_Date__c, Time.newInstance(12, 0, 0, 0)), b.LastModifiedDate, new Map<String, Object>{
                'bill' => b.Bill__r?.Name, 'dueDate' => b.Due_Date__c, 'amountDue' => b.Amount_Due__c, 'amountPaid' => b.Amount_Paid__c,
                'status' => b.Status__c, 'paidOn' => b.Paid_On__c
            }));
        }

        for (EMI_Installment__c e : [
            SELECT Id, Loan__r.Name, Installment_No__c, Due_Date__c, EMI_Amount__c, Principal_Part__c, Interest_Part__c, Opening_Balance__c,
                Closing_Balance__c, Status__c, Paid_On__c, LastModifiedDate
            FROM EMI_Installment__c
            WHERE Family__c = :familyId AND Due_Date__c < :cut
            WITH SYSTEM_MODE ORDER BY Due_Date__c LIMIT :MAX_PER_TYPE
        ]) {
            found.add(new Candidate(EMI, e.Id, e.Due_Date__c, Datetime.newInstance(e.Due_Date__c, Time.newInstance(12, 0, 0, 0)), e.LastModifiedDate, new Map<String, Object>{
                'loan' => e.Loan__r?.Name, 'installment' => e.Installment_No__c, 'dueDate' => e.Due_Date__c, 'emi' => e.EMI_Amount__c,
                'principal' => e.Principal_Part__c, 'interest' => e.Interest_Part__c, 'openingBalance' => e.Opening_Balance__c,
                'closingBalance' => e.Closing_Balance__c, 'status' => e.Status__c, 'paidOn' => e.Paid_On__c
            }));
        }

        // Oldest months first, a bounded number per pass; the rest follow on the next run.
        Set<String> monthSet = new Set<String>();
        for (Candidate c : found) {
            monthSet.add(c.month);
        }
        List<String> months = new List<String>(monthSet);
        months.sort();
        while (months.size() > MAX_MONTHS) {
            months.remove(months.size() - 1);
        }
        Set<String> allowed = new Set<String>(months);

        Map<String, Datetime> archived = new Map<String, Datetime>();
        for (String m : months) {
            for (Archive_Record__b r : ArchiveStore.month(familyId, m)) {
                archived.put(r.Record_Type__c + '|' + r.Record_Id__c, r.Source_Modified__c);
            }
        }

        Collected result = new Collected();
        Datetime now = Datetime.now();
        Set<String> ledgerMonths = new Set<String>();
        for (Candidate c : found) {
            if (!allowed.contains(c.month)) {
                continue;
            }
            Datetime known = archived.get(c.type + '|' + c.recordId);
            if (known != null && c.modified != null && known >= c.modified) {
                continue;
            }
            result.rows.add(row(familyId, c.month, c.type, c.recordId, c.recordDate, c.modified, now, c.payload));
            result.touched.add(c.month);
            if (c.type == TXN) {
                ledgerMonths.add(c.month);
            }
        }
        if (!ledgerMonths.isEmpty()) {
            result.rows.addAll(snapshots(familyId, ledgerMonths, now));
        }
        return result;
    }

    /**
     * Accounts (with each one's balance at month end) and members, as they were when the month
     * was archived. Months already removed from the live ledger keep their earlier snapshot.
     */
    private static List<Archive_Record__b> snapshots(Id familyId, Set<String> monthKeys, Datetime now) {
        Set<String> keys = new Set<String>();
        for (String m : monthKeys) {
            keys.add(logKey(familyId, m));
        }
        Set<String> skip = new Set<String>();
        for (Archive_Log__c log : [SELECT Unique_Key__c FROM Archive_Log__c WHERE Unique_Key__c IN :keys AND Status__c = 'Purged' WITH SYSTEM_MODE]) {
            skip.add(log.Unique_Key__c.right(7));
        }
        List<Financial_Account__c> accounts = [
            SELECT Id, Name, Type__c, Institution__c, Last4__c, Status__c, Is_Shared__c, Owner_Member__r.First_Name__c,
                Owner_Member__r.Last_Name__c, Opening_Balance__c, Archived_Net__c, Credit_Limit__c, LastModifiedDate
            FROM Financial_Account__c WHERE Family__c = :familyId WITH SYSTEM_MODE
        ];
        List<Portal_User__c> members = [
            SELECT Id, First_Name__c, Last_Name__c, Username__c, Email__c, Role__c, Relationship__c, Status__c, Viewer_Scope__c,
                Last_Login__c, MFA_Enrolled_At__c, LastModifiedDate
            FROM Portal_User__c WHERE Family__c = :familyId WITH SYSTEM_MODE
        ];
        List<Archive_Record__b> rows = new List<Archive_Record__b>();
        for (String m : monthKeys) {
            if (skip.contains(m)) {
                continue;
            }
            Date monthEnd = LedgerUtil.monthEnd(monthStart(m));
            Map<Id, Decimal> net = new Map<Id, Decimal>();
            for (AggregateResult ar : [
                SELECT Account__c acct, Direction__c dir, SUM(Amount__c) total FROM Transaction__c
                WHERE Family__c = :familyId AND Status__c != 'Void' AND Txn_Date__c <= :monthEnd
                WITH SYSTEM_MODE GROUP BY Account__c, Direction__c
            ]) {
                Decimal total = LedgerUtil.zeroIfNull(ar.get('total'));
                Id acct = (Id) ar.get('acct');
                net.put(acct, (net.containsKey(acct) ? net.get(acct) : 0) + ((String) ar.get('dir') == 'Credit' ? total : -total));
            }
            Datetime at = Datetime.newInstance(monthEnd, Time.newInstance(23, 59, 0, 0));
            for (Financial_Account__c a : accounts) {
                Decimal n = LedgerUtil.zeroIfNull(a.Archived_Net__c) + (net.containsKey(a.Id) ? net.get(a.Id) : 0);
                Decimal opening = LedgerUtil.zeroIfNull(a.Opening_Balance__c);
                rows.add(row(familyId, m, ACCOUNT, a.Id, at, a.LastModifiedDate, now, new Map<String, Object>{
                    'name' => a.Name, 'type' => a.Type__c, 'institution' => a.Institution__c, 'last4' => a.Last4__c, 'status' => a.Status__c,
                    'owner' => fullName(a.Owner_Member__r), 'shared' => a.Is_Shared__c, 'openingBalance' => opening,
                    'monthEndBalance' => LedgerUtil.isLiability(a.Type__c) ? opening - n : opening + n, 'creditLimit' => a.Credit_Limit__c
                }));
            }
            // Password hashes, salts, two-step keys and recovery codes are never copied.
            for (Portal_User__c u : members) {
                rows.add(row(familyId, m, MEMBER, u.Id, at, u.LastModifiedDate, now, new Map<String, Object>{
                    'name' => fullName(u), 'username' => u.Username__c, 'email' => u.Email__c, 'role' => u.Role__c,
                    'relationship' => u.Relationship__c, 'status' => u.Status__c, 'viewerScope' => u.Viewer_Scope__c,
                    'lastLogin' => u.Last_Login__c, 'twoStep' => u.MFA_Enrolled_At__c != null
                }));
            }
        }
        return rows;
    }

    private static Archive_Record__b row(Id familyId, String month, String type, Id recordId, Datetime recordDate, Datetime modified, Datetime now, Map<String, Object> payload) {
        return new Archive_Record__b(
            Family_Id__c = String.valueOf(familyId), Archive_Month__c = month, Record_Type__c = type, Record_Id__c = String.valueOf(recordId),
            Record_Date__c = recordDate, Source_Modified__c = modified, Archived_At__c = now, Payload__c = JSON.serialize(payload, true)
        );
    }

    public static String fullName(SObject member) {
        if (member == null) {
            return null;
        }
        String first = (String) member.get('First_Name__c');
        String last = (String) member.get('Last_Name__c');
        return ((first == null ? '' : first) + ' ' + (last == null ? '' : last)).trim();
    }

    // ---------- Closed-period guard (TransactionTrigger, before insert/update) ----------

    public static void assertOpen(List<Transaction__c> rows, Map<Id, Transaction__c> oldMap) {
        Set<Id> familyIds = new Set<Id>();
        for (Transaction__c t : rows) {
            if (t.Family__c != null) {
                familyIds.add(t.Family__c);
            }
        }
        if (familyIds.isEmpty()) {
            return;
        }
        Map<Id, Date> boundary = new Map<Id, Date>();
        for (Family__c f : [SELECT Id, Archived_Through__c FROM Family__c WHERE Id IN :familyIds AND Archived_Through__c != NULL WITH SYSTEM_MODE]) {
            boundary.put(f.Id, f.Archived_Through__c);
        }
        if (boundary.isEmpty()) {
            return;
        }
        for (Transaction__c t : rows) {
            Date last = boundary.get(t.Family__c);
            Transaction__c old = oldMap == null ? null : oldMap.get(t.Id);
            if (last != null && ((t.Txn_Date__c != null && t.Txn_Date__c <= last) || (old != null && old.Txn_Date__c != null && old.Txn_Date__c <= last))) {
                // A row error (not a thrown exception) so the REST layer can show this message.
                t.addError('Entries dated on or before ' + last.format() + ' are archived, so they can\'t be added or changed.');
            }
        }
    }

    // ---------- Purge ----------

    /** Logs whose month is safely copied, past the grace period and older than the live window. */
    public static List<Archive_Log__c> purgeable(Id familyId, Date today, Integer max) {
        Date cut = cutoff(today);
        Datetime graceEnd = Datetime.now().addDays(-graceDays());
        List<Archive_Log__c> result = new List<Archive_Log__c>();
        for (Archive_Log__c log : [
            SELECT Id, Family__c, Month__c, Unique_Key__c, Status__c, Copied_At__c, Exported_At__c, Purged__c, Kept__c
            FROM Archive_Log__c
            WHERE Family__c = :familyId AND Status__c = 'Copied' AND Month__c < :cut AND Copied_At__c <= :graceEnd
            WITH SYSTEM_MODE ORDER BY Month__c
        ]) {
            if (googleCopy() && (log.Exported_At__c == null || log.Exported_At__c < log.Copied_At__c)) {
                continue;
            }
            result.add(log);
            if (result.size() >= max) {
                break;
            }
        }
        return result;
    }

    public class PurgeResult {
        public Integer removed = 0;
        public Integer kept = 0;
    }

    /**
     * Removes one archived month's ledger records. Call with a fresh transaction: the big-object
     * read comes first. Records changed after they were copied are kept; the next run copies
     * them again and they're removed after a fresh grace period.
     */
    public static PurgeResult purgeMonth(Archive_Log__c log) {
        Id familyId = log.Family__c;
        String key = monthKey(log.Month__c);
        Map<String, Map<Id, Datetime>> copied = new Map<String, Map<Id, Datetime>>{
            TXN => new Map<Id, Datetime>(), REQUEST => new Map<Id, Datetime>(), STATEMENT => new Map<Id, Datetime>()
        };
        for (Archive_Record__b r : ArchiveStore.month(familyId, key)) {
            if (copied.containsKey(r.Record_Type__c)) {
                copied.get(r.Record_Type__c).put(Id.valueOf(r.Record_Id__c), r.Source_Modified__c);
            }
        }

        // Reports read old months from the closed-month snapshot, so make sure it exists first.
        String summaryKey = familyId + '-' + key + '-family';
        if ([SELECT COUNT() FROM Monthly_Summary__c WHERE Unique_Key__c = :summaryKey WITH SYSTEM_MODE] == 0) {
            InsightService.snapshot(familyId, log.Month__c);
        }

        PurgeResult result = new PurgeResult();
        Map<Id, Datetime> requestIds = copied.get(REQUEST);
        List<Spend_Request__c> requests = new List<Spend_Request__c>();
        for (Spend_Request__c r : [
            SELECT Id, LastModifiedDate FROM Spend_Request__c
            WHERE Id IN :requestIds.keySet() AND Family__c = :familyId AND Status__c != 'Pending' WITH SYSTEM_MODE
        ]) {
            if (unchanged(r.LastModifiedDate, requestIds.get(r.Id))) {
                requests.add(r);
            } else {
                result.kept++;
            }
        }

        Map<Id, Datetime> statementIds = copied.get(STATEMENT);
        List<Statement_Import__c> statements = new List<Statement_Import__c>();
        for (Statement_Import__c s : [
            SELECT Id, LastModifiedDate FROM Statement_Import__c
            WHERE Id IN :statementIds.keySet() AND Family__c = :familyId AND Status__c != 'Processing' WITH SYSTEM_MODE
        ]) {
            if (unchanged(s.LastModifiedDate, statementIds.get(s.Id))) {
                statements.add(s);
            } else {
                result.kept++;
            }
        }
        List<Statement_Row__c> statementRows = statements.isEmpty()
            ? new List<Statement_Row__c>()
            : [SELECT Id FROM Statement_Row__c WHERE Import__c IN :statements AND Family__c = :familyId WITH SYSTEM_MODE];

        if (!statementRows.isEmpty()) {
            delete as system statementRows;
        }
        if (!requests.isEmpty()) {
            delete as system requests;
        }
        if (!statements.isEmpty()) {
            delete as system statements;
        }

        Map<Id, Datetime> txnIds = copied.get(TXN);
        Set<Id> blocked = new Set<Id>();
        for (Transaction_Receipt__c r : [SELECT Transaction__c FROM Transaction_Receipt__c WHERE Transaction__c IN :txnIds.keySet() WITH SYSTEM_MODE]) {
            blocked.add(r.Transaction__c);
        }
        for (Spend_Request__c r : [SELECT Transaction__c FROM Spend_Request__c WHERE Transaction__c IN :txnIds.keySet() WITH SYSTEM_MODE]) {
            blocked.add(r.Transaction__c);
        }
        for (Statement_Row__c r : [SELECT Transaction__c FROM Statement_Row__c WHERE Transaction__c IN :txnIds.keySet() WITH SYSTEM_MODE]) {
            blocked.add(r.Transaction__c);
        }
        List<Transaction__c> txns = new List<Transaction__c>();
        Map<Id, Decimal> netByAccount = new Map<Id, Decimal>();
        for (Transaction__c t : [
            SELECT Id, Account__c, Amount__c, Direction__c, Status__c, LastModifiedDate FROM Transaction__c
            WHERE Id IN :txnIds.keySet() AND Family__c = :familyId WITH SYSTEM_MODE
        ]) {
            if (blocked.contains(t.Id) || !unchanged(t.LastModifiedDate, txnIds.get(t.Id))) {
                result.kept++;
                continue;
            }
            txns.add(t);
            Decimal effect = LedgerBalances.netEffect(t);
            if (t.Account__c != null && effect != 0) {
                netByAccount.put(t.Account__c, (netByAccount.containsKey(t.Account__c) ? netByAccount.get(t.Account__c) : 0) + effect);
            }
        }
        if (!txns.isEmpty()) {
            Set<Id> accountIds = netByAccount.keySet();
            List<Financial_Account__c> accounts = [
                SELECT Id, Archived_Net__c FROM Financial_Account__c WHERE Id IN :accountIds WITH SYSTEM_MODE FOR UPDATE
            ];
            // The balance doesn't move: what leaves the ledger is carried in Archived_Net__c.
            LedgerBalances.suspended = true;
            try {
                delete as system txns;
            } finally {
                LedgerBalances.suspended = false;
            }
            for (Financial_Account__c a : accounts) {
                a.Archived_Net__c = LedgerUtil.zeroIfNull(a.Archived_Net__c) + netByAccount.get(a.Id);
            }
            update as system accounts;
        }

        List<SObject> removed = new List<SObject>();
        removed.addAll(statementRows);
        removed.addAll(requests);
        removed.addAll(statements);
        removed.addAll(txns);
        result.removed = requests.size() + statements.size() + txns.size();
        // Deleted rows still count against storage while they sit in the Recycle Bin.
        if (!removed.isEmpty()) {
            Database.emptyRecycleBin(removed);
        }
        return result;
    }

    private static Boolean unchanged(Datetime current, Datetime whenCopied) {
        return whenCopied != null && current != null && current <= whenCopied;
    }
}
