/**
 * Reads and writes Archive_Record__b, the big object that holds archived records outside the
 * 5 MB data storage. Index: family, month ('YYYY-MM'), record type, record id - so one query
 * returns a family's month. Writing the same index key again replaces the row.
 *
 * Big-object rules this class relies on: reads must come before any DML in the transaction,
 * writes can't share a transaction with ordinary DML, and Apex tests can't touch big objects -
 * tests use the in-memory rows below instead.
 */
public without sharing class ArchiveStore {
    @TestVisible
    private static List<Archive_Record__b> testRows = new List<Archive_Record__b>();

    public static void save(List<Archive_Record__b> rows) {
        if (rows.isEmpty()) {
            return;
        }
        if (Test.isRunningTest()) {
            Map<String, Archive_Record__b> byKey = new Map<String, Archive_Record__b>();
            for (Archive_Record__b r : testRows) {
                byKey.put(key(r), r);
            }
            for (Archive_Record__b r : rows) {
                byKey.put(key(r), r);
            }
            testRows = byKey.values();
            return;
        }
        Database.insertImmediate(rows);
    }

    public static List<Archive_Record__b> month(Id familyId, String monthKey) {
        String fid = String.valueOf(familyId);
        if (Test.isRunningTest()) {
            List<Archive_Record__b> result = new List<Archive_Record__b>();
            for (Archive_Record__b r : testRows) {
                if (r.Family_Id__c == fid && r.Archive_Month__c == monthKey) {
                    result.add(r);
                }
            }
            return result;
        }
        return Database.queryWithBinds(
            'SELECT Family_Id__c, Archive_Month__c, Record_Type__c, Record_Id__c, Record_Date__c, Source_Modified__c, Archived_At__c, Payload__c ' +
            'FROM Archive_Record__b WHERE Family_Id__c = :fid AND Archive_Month__c = :monthKey LIMIT 50000',
            new Map<String, Object>{ 'fid' => fid, 'monthKey' => monthKey },
            AccessLevel.SYSTEM_MODE
        );
    }

    public static List<Archive_Record__b> monthOfType(Id familyId, String monthKey, String recordType) {
        List<Archive_Record__b> result = new List<Archive_Record__b>();
        for (Archive_Record__b r : month(familyId, monthKey)) {
            if (r.Record_Type__c == recordType) {
                result.add(r);
            }
        }
        return result;
    }

    private static String key(Archive_Record__b r) {
        return r.Family_Id__c + '|' + r.Archive_Month__c + '|' + r.Record_Type__c + '|' + r.Record_Id__c;
    }
}