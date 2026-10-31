/**
 * Mondays 07:00 ("VKF Security Digest"): one email to the platform owner - the user who
 * scheduled the job - covering the last 7 days across every family: sign-ins and failures,
 * lockouts, throttling, cross-family attempts, two-step and password changes, new admins,
 * admins without two-step, balance fixes, failed jobs and data storage. Email to an internal
 * user doesn't use the org's small daily single-email allowance.
 */
public without sharing class SecurityDigestJob implements Schedulable {
    @TestVisible
    private static String lastText;

    private static final Map<String, String> COUNTED = new Map<String, String>{
        'LOGIN_SUCCESS' => 'signIns',
        'LOGIN_FAILED' => 'failedSignIns',
        'ACCOUNT_LOCKED' => 'lockouts',
        'LOGIN_THROTTLED' => 'throttled',
        'RESET_THROTTLED' => 'throttled',
        'CROSS_FAMILY_ATTEMPT' => 'crossFamily',
        'STEP_UP_FAILED' => 'failedConfirmations',
        'MFA_ENABLED' => 'twoStepChanges',
        'MFA_DISABLED' => 'twoStepChanges',
        'ADMIN_MFA_RESET' => 'twoStepChanges',
        'PASSWORD_RESET' => 'passwordResets',
        'ADMIN_PASSWORD_RESET' => 'passwordResets',
        'BALANCE_DRIFT_FIXED' => 'balanceFixes',
        'BALANCE_RECONCILE_FAILED' => 'jobErrors',
        'DAILY_DUES_FAILED' => 'jobErrors'
    };

    public class Digest {
        public Datetime since;
        public Map<String, Integer> totals = new Map<String, Integer>();
        public List<FamilyLine> families = new List<FamilyLine>();
        /** Things the owner should look at, most important first. */
        public List<String> attention = new List<String>();
        public Integer failedJobs = 0;
        public Integer storageUsedMb;
        public Integer storageMaxMb;
    }

    public class FamilyLine {
        public String name;
        public String code;
        public String status;
        public Integer activeMembers = 0;
        public Map<String, Integer> counts = new Map<String, Integer>();
        public List<String> adminsWithoutTwoStep = new List<String>();
    }

    public void execute(SchedulableContext sc) {
        send();
    }

    public static Boolean send() {
        Digest d = build(Datetime.now().addDays(-7));
        lastText = renderText(d);
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(UserInfo.getUserId());
            mail.setSaveAsActivity(false);
            mail.setSenderDisplayName('VK Finance');
            mail.setSubject(
                'VK Finance weekly security digest - ' +
                (d.attention.isEmpty() ? 'all clear' : d.attention.size() + ' item' + (d.attention.size() == 1 ? '' : 's') + ' to review')
            );
            mail.setPlainTextBody(lastText);
            mail.setHtmlBody(renderHtml(d));
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            AuditService.log(null, null, 'SECURITY_DIGEST_SENT', null, null, d.attention.size() + ' item(s) to review');
            return true;
        } catch (Exception e) {
            AuditService.log(null, null, 'SECURITY_DIGEST_FAILED', null, null, e.getMessage());
            return false;
        }
    }

    public static Digest build(Datetime since) {
        Digest d = new Digest();
        d.since = since;
        for (String bucket : new Set<String>(COUNTED.values())) {
            d.totals.put(bucket, 0);
        }
        d.totals.put('newAdmins', 0);

        Map<Id, FamilyLine> lines = new Map<Id, FamilyLine>();
        for (Family__c f : [SELECT Id, Name, Family_Code__c, Status__c FROM Family__c WITH SYSTEM_MODE ORDER BY Family_Code__c]) {
            FamilyLine line = new FamilyLine();
            line.name = f.Name;
            line.code = f.Family_Code__c;
            line.status = f.Status__c;
            for (String bucket : d.totals.keySet()) {
                line.counts.put(bucket, 0);
            }
            lines.put(f.Id, line);
            d.families.add(line);
        }
        for (Portal_User__c u : [
            SELECT Family__c, First_Name__c, Last_Name__c, Role__c, MFA_Method__c
            FROM Portal_User__c
            WHERE Status__c = 'Active'
            WITH SYSTEM_MODE
        ]) {
            FamilyLine line = lines.get(u.Family__c);
            if (line == null) {
                continue;
            }
            line.activeMembers++;
            if ((u.Role__c == 'Family Admin' || u.Role__c == 'Co-Admin') && u.MFA_Method__c != MfaService.METHOD_APP) {
                line.adminsWithoutTwoStep.add(u.First_Name__c + ' ' + u.Last_Name__c);
            }
        }

        for (Id familyId : lines.keySet()) {
            countEvents(String.valueOf(familyId), since, lines.get(familyId), d);
        }
        countEvents('PLATFORM', since, null, d);

        d.failedJobs = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE CreatedDate >= :since AND JobType IN ('BatchApex', 'ScheduledApex', 'Queueable', 'Future') AND (Status = 'Failed' OR NumberOfErrors > 0)
        ];
        System.OrgLimit storage = OrgLimits.getMap().get('DataStorageMB');
        if (storage != null) {
            d.storageUsedMb = storage.getValue();
            d.storageMaxMb = storage.getLimit();
        }
        d.attention = attention(d);
        return d;
    }

    private static void countEvents(String familyKey, Datetime since, FamilyLine line, Digest d) {
        try {
            for (SObject row : Database.queryWithBinds(
                'SELECT Event_Type__c, Details__c FROM Audit_Log__b WHERE Family_Id__c = :fid AND Event_Time__c >= :since LIMIT 10000',
                new Map<String, Object>{ 'fid' => familyKey, 'since' => since },
                AccessLevel.SYSTEM_MODE
            )) {
                String type = (String) row.get('Event_Type__c');
                String bucket = COUNTED.get(type);
                String details = (String) row.get('Details__c');
                if (type == 'MEMBER_UPDATED' && details != null && (details.contains('-> Family Admin') || details.contains('-> Co-Admin'))) {
                    bucket = 'newAdmins';
                }
                if (bucket == null) {
                    continue;
                }
                d.totals.put(bucket, d.totals.get(bucket) + 1);
                if (line != null) {
                    line.counts.put(bucket, line.counts.get(bucket) + 1);
                }
            }
        } catch (Exception e) {
            // The audit store can be unavailable (e.g. in tests); the rest of the digest still goes out.
            System.debug(LoggingLevel.WARN, 'Audit read failed for ' + familyKey + ': ' + e.getMessage());
        }
    }

    private static List<String> attention(Digest d) {
        List<String> items = new List<String>();
        if (d.totals.get('crossFamily') > 0) {
            items.add(d.totals.get('crossFamily') + ' attempt(s) to open another family\'s records - all were refused.');
        }
        if (d.totals.get('lockouts') > 0) {
            items.add(d.totals.get('lockouts') + ' account lockout(s) after repeated failed attempts.');
        }
        if (d.totals.get('newAdmins') > 0) {
            items.add(d.totals.get('newAdmins') + ' member(s) were made Family Admin or Co-Admin.');
        }
        for (FamilyLine line : d.families) {
            if (line.status == 'Active' && !line.adminsWithoutTwoStep.isEmpty()) {
                items.add(line.code + ': admins without two-step verification - ' + String.join(line.adminsWithoutTwoStep, ', ') + '.');
            }
        }
        if (d.failedJobs > 0 || d.totals.get('jobErrors') > 0) {
            items.add((d.failedJobs + d.totals.get('jobErrors')) + ' background job failure(s) - check Setup > Apex Jobs.');
        }
        if (d.totals.get('balanceFixes') > 0) {
            items.add(d.totals.get('balanceFixes') + ' account balance(s) had drifted and were corrected overnight.');
        }
        if (d.storageMaxMb != null && d.storageMaxMb > 0 && d.storageUsedMb * 100 >= d.storageMaxMb * 80) {
            items.add('Data storage is ' + (d.storageUsedMb * 100 / d.storageMaxMb) + '% full (' + d.storageUsedMb + ' of ' + d.storageMaxMb + ' MB).');
        }
        return items;
    }

    private static final List<String> ORDER = new List<String>{
        'signIns', 'failedSignIns', 'lockouts', 'throttled', 'crossFamily', 'failedConfirmations', 'twoStepChanges', 'passwordResets',
        'newAdmins', 'balanceFixes'
    };
    private static final Map<String, String> LABELS = new Map<String, String>{
        'signIns' => 'Sign-ins',
        'failedSignIns' => 'Failed sign-ins',
        'lockouts' => 'Lockouts',
        'throttled' => 'Throttled requests',
        'crossFamily' => 'Cross-family attempts',
        'failedConfirmations' => 'Failed confirmations',
        'twoStepChanges' => 'Two-step changes',
        'passwordResets' => 'Password resets',
        'newAdmins' => 'New admins',
        'balanceFixes' => 'Balance fixes'
    };

    @TestVisible
    private static String renderText(Digest d) {
        List<String> lines = new List<String>{ 'VK Finance - security digest for the 7 days since ' + d.since.format('d MMM yyyy'), '' };
        lines.add(d.attention.isEmpty() ? 'Nothing needs your attention.' : 'To review:');
        for (String item : d.attention) {
            lines.add('  - ' + item);
        }
        lines.add('');
        lines.add('All families:');
        for (String key : ORDER) {
            lines.add('  ' + LABELS.get(key) + ': ' + d.totals.get(key));
        }
        for (FamilyLine f : d.families) {
            lines.add('');
            lines.add(f.code + ' ' + f.name + ' (' + f.status + ', ' + f.activeMembers + ' active members)');
            lines.add(
                '  Sign-ins ' + f.counts.get('signIns') + ', failed ' + f.counts.get('failedSignIns') + ', lockouts ' + f.counts.get('lockouts') +
                ', cross-family ' + f.counts.get('crossFamily')
            );
        }
        lines.add('');
        lines.add('Failed background jobs: ' + d.failedJobs);
        if (d.storageMaxMb != null) {
            lines.add('Data storage: ' + d.storageUsedMb + ' of ' + d.storageMaxMb + ' MB');
        }
        return String.join(lines, '\n');
    }

    private static String renderHtml(Digest d) {
        String cell = 'style="padding:6px 10px;border-bottom:1px solid #e2e8f0;text-align:left"';
        String num = 'style="padding:6px 10px;border-bottom:1px solid #e2e8f0;text-align:right;font-variant-numeric:tabular-nums"';
        String html = '<div style="font-family:Segoe UI,Arial,sans-serif;color:#0f172a;max-width:640px">';
        html += '<h2 style="margin:0 0 4px">VK Finance security digest</h2>';
        html += '<p style="margin:0 0 16px;color:#64748b">7 days since ' + d.since.format('d MMM yyyy') + '</p>';
        if (d.attention.isEmpty()) {
            html += '<p style="padding:10px 14px;background:#ecfdf5;border-radius:8px;color:#065f46">Nothing needs your attention.</p>';
        } else {
            html += '<div style="padding:10px 14px;background:#fffbeb;border-radius:8px;color:#78350f"><strong>To review</strong><ul style="margin:6px 0 0;padding-left:18px">';
            for (String item : d.attention) {
                html += '<li>' + item.escapeHtml4() + '</li>';
            }
            html += '</ul></div>';
        }
        html += '<table style="border-collapse:collapse;width:100%;margin-top:16px;font-size:14px"><tr><th ' + cell + '>Family</th><th ' + num + '>Members</th>';
        html += '<th ' + num + '>Sign-ins</th><th ' + num + '>Failed</th><th ' + num + '>Lockouts</th><th ' + num + '>Cross-family</th></tr>';
        for (FamilyLine f : d.families) {
            html += '<tr><td ' + cell + '>' + (f.code + ' ' + f.name).escapeHtml4() + (f.status == 'Active' ? '' : ' (' + f.status.escapeHtml4() + ')') + '</td>';
            html += '<td ' + num + '>' + f.activeMembers + '</td><td ' + num + '>' + f.counts.get('signIns') + '</td><td ' + num + '>' + f.counts.get('failedSignIns') + '</td>';
            html += '<td ' + num + '>' + f.counts.get('lockouts') + '</td><td ' + num + '>' + f.counts.get('crossFamily') + '</td></tr>';
        }
        html += '</table><table style="border-collapse:collapse;margin-top:16px;font-size:14px">';
        for (String key : ORDER) {
            html += '<tr><td ' + cell + '>' + LABELS.get(key) + '</td><td ' + num + '>' + d.totals.get(key) + '</td></tr>';
        }
        html += '<tr><td ' + cell + '>Failed background jobs</td><td ' + num + '>' + d.failedJobs + '</td></tr>';
        if (d.storageMaxMb != null) {
            html += '<tr><td ' + cell + '>Data storage</td><td ' + num + '>' + d.storageUsedMb + ' / ' + d.storageMaxMb + ' MB</td></tr>';
        }
        return html + '</table></div>';
    }
}