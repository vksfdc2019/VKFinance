/**
 * Writes each archived family-month to its own Google Sheet ("VKFinance Archive/FAM-0001/
 * FAM-0001 2026-07"), one tab per record type plus the month's audit trail, and keeps
 * Archive_Log__c up to date. The sheet is rebuilt from the big object every time, so re-runs
 * never duplicate rows.
 *
 * Order inside one transaction matters: big-object reads, then Google callouts, then DML.
 */
public without sharing class ArchiveExporter {
    /** Tab title -> [payload key, column heading] pairs, in sheet order. */
    public static final Map<String, List<String>> TABS = new Map<String, List<String>>{
        'Transactions' => new List<String>{
            'number:No', 'date:Date', 'type:Type', 'direction:Direction', 'amount:Amount', 'status:Status', 'account:Account',
            'category:Category', 'member:Member', 'payee:Payee', 'notes:Notes', 'paymentMode:Payment mode', 'reference:Reference',
            'source:Source', 'transferGroup:Transfer group', 'createdAt:Recorded at'
        },
        'Accounts' => new List<String>{
            'name:Account', 'type:Type', 'institution:Institution', 'last4:Last 4', 'status:Status', 'owner:Owner', 'shared:Shared',
            'openingBalance:Opening balance', 'monthEndBalance:Balance at month end', 'creditLimit:Credit limit',
            'creditLimitGroupId:Shared facility ID', 'creditLimitGroup:Shared facility', 'independentCreditLimit:Saved independent limit'
        },
        'Members' => new List<String>{
            'name:Name', 'username:Username', 'email:Email', 'role:Role', 'relationship:Relationship', 'status:Status',
            'viewerScope:Viewer scope', 'lastLogin:Last sign-in', 'twoStep:Two-step on'
        },
        'Bill payments' => new List<String>{ 'bill:Bill', 'dueDate:Due', 'amountDue:Amount due', 'amountPaid:Paid', 'status:Status', 'paidOn:Paid on' },
        'EMIs' => new List<String>{
            'loan:Loan', 'installment:No', 'dueDate:Due', 'emi:EMI', 'principal:Principal', 'interest:Interest',
            'openingBalance:Opening', 'closingBalance:Closing', 'status:Status', 'paidOn:Paid on'
        },
        'Spend requests' => new List<String>{
            'title:Title', 'amount:Amount', 'status:Status', 'child:Child', 'account:Account', 'category:Category', 'validUntil:Valid until',
            'decidedAt:Decided at', 'decidedBy:Decided by', 'decisionNote:Decision note', 'note:Note', 'createdAt:Asked at'
        },
        'Statement imports' => new List<String>{
            'number:No', 'fileName:File', 'status:Status', 'account:Account', 'member:Member', 'total:Rows', 'imported:Imported',
            'duplicates:Duplicates', 'failed:Failed', 'error:Note', 'createdAt:Uploaded at'
        },
        'Sessions' => new List<String>{
            'member:Member', 'status:Status', 'scope:Scope', 'startedAt:Signed in', 'lastActivity:Last activity', 'endedAt:Ended',
            'expiresAt:Expires', 'endReason:End reason', 'device:Device'
        },
        'Notifications' => new List<String>{
            'title:Title', 'message:Message', 'type:Type', 'severity:Severity', 'recipient:Recipient', 'link:Link', 'createdAt:Sent at'
        }
    };

    public static final Map<String, String> TAB_FOR_TYPE = new Map<String, String>{
        ArchiveService.TXN => 'Transactions', ArchiveService.ACCOUNT => 'Accounts', ArchiveService.MEMBER => 'Members',
        ArchiveService.BILL => 'Bill payments', ArchiveService.EMI => 'EMIs', ArchiveService.REQUEST => 'Spend requests',
        ArchiveService.STATEMENT => 'Statement imports', ArchiveService.SESSION => 'Sessions', ArchiveService.NOTICE => 'Notifications'
    };

    static {
        // Setup snapshots (bills, loans, budgets, categories, recurring, goals, card statements).
        for (ArchiveService.Snapshot def : ArchiveService.SNAPSHOTS) {
            List<String> cols = new List<String>();
            for (String col : def.columns) {
                List<String> parts = col.split(':');
                cols.add(parts[0] + ':' + parts[1]);
            }
            TABS.put(def.tab, cols);
            TAB_FOR_TYPE.put(def.type, def.tab);
        }
    }

    public static final List<String> AUDIT_COLUMNS = new List<String>{ 'Time', 'Event', 'Actor', 'Object', 'Record', 'Details' };

    /** Months of a family whose sheet is missing or older than the latest copy. */
    public static Set<String> pendingExport(Id familyId) {
        Set<String> result = new Set<String>();
        if (!ArchiveService.googleCopy()) {
            return result;
        }
        for (Archive_Log__c log : [
            SELECT Month__c, Copied_At__c, Exported_At__c FROM Archive_Log__c WHERE Family__c = :familyId WITH SYSTEM_MODE ORDER BY Month__c
        ]) {
            if (log.Exported_At__c == null || (log.Copied_At__c != null && log.Exported_At__c < log.Copied_At__c)) {
                result.add(ArchiveService.monthKey(log.Month__c));
            }
        }
        return result;
    }

    /** Sheet tabs for one month: the header row first, rows sorted by date. */
    public static Map<String, List<List<Object>>> layout(List<Archive_Record__b> records, List<SObject> audit) {
        Map<String, List<Archive_Record__b>> byTab = new Map<String, List<Archive_Record__b>>();
        for (Archive_Record__b r : records) {
            String tab = TAB_FOR_TYPE.get(r.Record_Type__c);
            if (tab == null) {
                continue;
            }
            if (!byTab.containsKey(tab)) {
                byTab.put(tab, new List<Archive_Record__b>());
            }
            byTab.get(tab).add(r);
        }
        Map<String, List<List<Object>>> result = new Map<String, List<List<Object>>>();
        for (String tab : TABS.keySet()) {
            List<Archive_Record__b> rows = byTab.get(tab);
            if (rows == null || rows.isEmpty()) {
                continue;
            }
            List<SortableRecord> sortable = new List<SortableRecord>();
            for (Archive_Record__b r : rows) {
                sortable.add(new SortableRecord(r));
            }
            sortable.sort();
            List<String> keys = new List<String>();
            List<Object> header = new List<Object>();
            for (String col : TABS.get(tab)) {
                keys.add(col.substringBefore(':'));
                header.add(col.substringAfter(':'));
            }
            List<List<Object>> values = new List<List<Object>>{ header };
            for (SortableRecord s : sortable) {
                Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(s.record.Payload__c);
                List<Object> line = new List<Object>();
                for (String k : keys) {
                    line.add(cell(payload.get(k)));
                }
                values.add(line);
            }
            result.put(tab, values);
        }
        if (audit != null && !audit.isEmpty()) {
            List<Object> header = new List<Object>();
            header.addAll(AUDIT_COLUMNS);
            List<List<Object>> values = new List<List<Object>>{ header };
            for (SObject a : audit) {
                values.add(new List<Object>{
                    cell(a.get('Event_Time__c')), cell(a.get('Event_Type__c')), cell(a.get('Actor_Id__c')),
                    cell(a.get('Object_Name__c')), cell(a.get('Record_Id__c')), cell(a.get('Details__c'))
                });
            }
            result.put('Audit', values);
        }
        return result;
    }

    private static Object cell(Object value) {
        if (value == null) {
            return '';
        }
        if (value instanceof Boolean) {
            return (Boolean) value ? 'Yes' : 'No';
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).format('yyyy-MM-dd HH:mm');
        }
        if (value instanceof Date) {
            return String.valueOf(value);
        }
        if (value instanceof Decimal || value instanceof Integer || value instanceof Double || value instanceof Long) {
            return value;
        }
        // Values are written RAW, so text starting with = stays text. Long notes are trimmed for readability.
        return String.valueOf(value).left(5000);
    }

    private class SortableRecord implements Comparable {
        Archive_Record__b record;
        SortableRecord(Archive_Record__b record) {
            this.record = record;
        }
        public Integer compareTo(Object other) {
            Archive_Record__b o = ((SortableRecord) other).record;
            if (record.Record_Date__c == o.Record_Date__c) {
                return record.Record_Id__c < o.Record_Id__c ? -1 : 1;
            }
            if (record.Record_Date__c == null) {
                return 1;
            }
            if (o.Record_Date__c == null) {
                return -1;
            }
            return record.Record_Date__c < o.Record_Date__c ? -1 : 1;
        }
    }

    public class MonthData {
        public String monthKey;
        public List<Archive_Record__b> records;
        public List<SObject> audit;
        public Map<String, Integer> counts = new Map<String, Integer>();
    }

    /**
     * Copies the given months to Google (when the policy asks for it) and records the result.
     * touched = months that gained records in this run (their Copied_At__c moves forward).
     */
    public static void export(Id familyId, List<String> monthKeys, Set<String> touched) {
        Family__c family = [SELECT Id, Name, Family_Code__c, Archived_Through__c FROM Family__c WHERE Id = :familyId WITH SYSTEM_MODE];

        // 1. Reads (big objects must be read before any DML).
        List<MonthData> months = new List<MonthData>();
        for (String key : monthKeys) {
            MonthData m = new MonthData();
            m.monthKey = key;
            m.records = ArchiveStore.month(familyId, key);
            for (Archive_Record__b r : m.records) {
                m.counts.put(r.Record_Type__c, (m.counts.containsKey(r.Record_Type__c) ? m.counts.get(r.Record_Type__c) : 0) + 1);
            }
            m.audit = audit(familyId, key);
            months.add(m);
        }
        Map<String, Archive_Log__c> logs = new Map<String, Archive_Log__c>();
        Set<String> logKeys = new Set<String>();
        for (String key : monthKeys) {
            logKeys.add(ArchiveService.logKey(familyId, key));
        }
        for (Archive_Log__c log : [
            SELECT Id, Unique_Key__c, Status__c, Sheet_Id__c, Copied_At__c, Exported_At__c FROM Archive_Log__c
            WHERE Unique_Key__c IN :logKeys WITH SYSTEM_MODE
        ]) {
            logs.put(log.Unique_Key__c, log);
        }

        // 2. Google callouts.
        Datetime now = Datetime.now();
        Map<String, String> sheetIds = new Map<String, String>();
        Map<String, String> errors = new Map<String, String>();
        Set<String> exported = new Set<String>();
        if (ArchiveService.googleCopy()) {
            GoogleSheetsClient google = new GoogleSheetsClient();
            String code = String.isBlank(family.Family_Code__c) ? family.Name : family.Family_Code__c;
            String familyFolder;
            for (MonthData m : months) {
                String key = ArchiveService.logKey(familyId, m.monthKey);
                try {
                    if (familyFolder == null) {
                        familyFolder = google.folder(code, google.folder(ArchiveService.folderName(), 'root'));
                    }
                    Archive_Log__c log = logs.get(key);
                    String sheetId = log == null ? null : log.Sheet_Id__c;
                    Map<String, Integer> tabs = sheetId == null ? null : google.tabs(sheetId);
                    if (tabs == null) {
                        sheetId = google.createSpreadsheet(code + ' ' + m.monthKey, familyFolder);
                        tabs = google.tabs(sheetId);
                    }
                    Map<String, List<List<Object>>> data = layout(m.records, m.audit);
                    if (!data.isEmpty()) {
                        Integer expected = 0;
                        for (List<List<Object>> rows : data.values()) {
                            expected += rows.size();
                        }
                        Integer written = google.replace(sheetId, tabs, data);
                        if (written != expected) {
                            throw new GoogleSheetsClient.GoogleException('Google wrote ' + written + ' of ' + expected + ' rows.');
                        }
                    }
                    sheetIds.put(key, sheetId);
                    exported.add(key);
                } catch (Exception e) {
                    errors.put(key, e.getMessage().left(3900));
                }
            }
        }

        // 3. DML.
        List<Archive_Log__c> upserts = new List<Archive_Log__c>();
        Date cut = ArchiveService.cutoff(Date.today());
        Date lockThrough = family.Archived_Through__c;
        for (MonthData m : months) {
            String key = ArchiveService.logKey(familyId, m.monthKey);
            Archive_Log__c existing = logs.get(key);
            Archive_Log__c log = new Archive_Log__c(Unique_Key__c = key, Family__c = familyId, Month__c = ArchiveService.monthStart(m.monthKey));
            log.Records__c = m.records.size();
            log.Counts__c = JSON.serialize(m.counts);
            if (touched.contains(m.monthKey) || existing == null) {
                log.Copied_At__c = now;
                log.Status__c = 'Copied';
            }
            if (exported.contains(key)) {
                log.Exported_At__c = now;
                log.Sheet_Id__c = sheetIds.get(key);
                log.Sheet_Url__c = GoogleSheetsClient.sheetUrl(sheetIds.get(key));
                log.Error__c = null;
            } else if (errors.containsKey(key)) {
                log.Error__c = errors.get(key);
            }
            upserts.add(log);
            Date monthStart = ArchiveService.monthStart(m.monthKey);
            if (monthStart < cut && m.counts.containsKey(ArchiveService.TXN)) {
                Date monthEnd = LedgerUtil.monthEnd(monthStart);
                if (lockThrough == null || monthEnd > lockThrough) {
                    lockThrough = monthEnd;
                }
            }
        }
        Database.upsert(upserts, Archive_Log__c.Unique_Key__c, true, AccessLevel.SYSTEM_MODE);
        if (lockThrough != family.Archived_Through__c) {
            update as system new Family__c(Id = familyId, Archived_Through__c = lockThrough);
        }
        AuditService.log(familyId, null, 'ARCHIVE_COPIED', 'Family__c', familyId, JSON.serialize(new Map<String, Object>{
            'months' => monthKeys, 'exported' => exported.size(), 'failed' => errors.size()
        }));
    }

    /** The month's audit trail (already a big object, so it's only copied to the sheet). */
    private static List<SObject> audit(Id familyId, String monthKey) {
        if (Test.isRunningTest()) {
            return new List<SObject>();
        }
        Date start = ArchiveService.monthStart(monthKey);
        try {
            return Database.queryWithBinds(
                'SELECT Event_Time__c, Event_Type__c, Actor_Id__c, Object_Name__c, Record_Id__c, Details__c FROM Audit_Log__b ' +
                'WHERE Family_Id__c = :fid AND Event_Time__c >= :since AND Event_Time__c < :until LIMIT 10000',
                new Map<String, Object>{
                    'fid' => String.valueOf(familyId),
                    'since' => Datetime.newInstance(start, Time.newInstance(0, 0, 0, 0)),
                    'until' => Datetime.newInstance(start.addMonths(1), Time.newInstance(0, 0, 0, 0))
                },
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            return new List<SObject>();
        }
    }
}
