"""Live Phase 6 pilot using two disposable families, never existing family data.

Requires Salesforce CLI authenticated to VKFinance. Credentials stay in memory;
anonymous Apex files are temporary and contain no existing user's credentials.
Every created family is removed in finally; audit events intentionally remain.
"""
from pathlib import Path
import base64
import datetime
import json
import os
import re
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ORG = 'VKFinance'
SITE = os.environ.get('VKF_SITE', 'https://orgfarm-db588f31ab-dev-ed.develop.my.site.com/VKFinancePortal').rstrip('/')
API = SITE + '/sf/api/services/apexrest/vkf/v1'
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) VKF-Phase6-Pilot Chrome/130.0 Safari/537.36'
RUN = secrets.token_hex(5)
PREFIX = 'VKF Phase6 Pilot ' + RUN
TODAY = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=5, minutes=30))).date().isoformat()
FEATURES = ['IMPORTS', 'RECEIPTS', 'REQUESTS', 'GOALS', 'INSTALL', 'INSIGHTS']
families = []
tokens = []
passwords = []
checks = []
cleanup = {'completed': False}
resume_ids = []


def quote(value):
    return "'" + str(value).replace('\\', '\\\\').replace("'", "\\'") + "'"


def redact(value):
    text = str(value)
    for secret in passwords + tokens:
        if secret:
            text = text.replace(secret, '[redacted]')
    return text[:1000]


def apex(source, marker):
    with tempfile.NamedTemporaryFile(mode='w', suffix='.apex', prefix='vkf-pilot-', encoding='utf-8', delete=False) as file:
        file.write(source)
        name = file.name
    try:
        process = subprocess.run(['sf.cmd', 'apex', 'run', '--target-org', ORG, '--file', name, '--json'],
                                 cwd=ROOT, capture_output=True, encoding='utf-8', errors='replace', timeout=120)
        data = json.loads(process.stdout)
        result = data.get('result', {})
        if data.get('status') or not result.get('success'):
            raise RuntimeError(redact(data.get('message') or result.get('exceptionMessage') or result.get('compileProblem')))
        for line in result.get('logs', '').splitlines():
            if '|DEBUG|' + marker + ' ' in line:
                return json.loads(line.split('|DEBUG|' + marker + ' ', 1)[1])
        raise RuntimeError('The pilot script did not return its verification marker.')
    finally:
        Path(name).unlink(missing_ok=True)


def call(method, path, body=None, token=None, expect=(200, 201, 204)):
    headers = {'User-Agent': UA, 'Accept': 'application/json', 'Cache-Control': 'no-store'}
    if body is not None:
        headers['Content-Type'] = 'application/json'
    if token:
        headers['X-VKF-Session'] = token
    request = urllib.request.Request(API + path, data=None if body is None else json.dumps(body).encode(), method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            status, content = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, content = error.code, error.read()
    try:
        payload = json.loads(content) if content else None
    except Exception:
        payload = {'code': 'NON_JSON_RESPONSE'}
    if status not in expect:
        raise RuntimeError(redact(f'{method} {path}: HTTP {status}; {payload}'))
    return payload


def verify(name, function):
    try:
        details = function()
        checks.append({'name': name, 'passed': True, 'details': details})
        print('PASS ' + name, flush=True)
        return details
    except Exception as error:
        checks.append({'name': name, 'passed': False, 'error': redact(error)})
        print('FAIL ' + name + ': ' + redact(error), flush=True)
        return None


def bootstrap(letter):
    username = 'p6.' + RUN + '.' + letter.lower()
    password = 'Z7!m' + secrets.token_hex(12)
    passwords.append(password)
    if resume_ids:
        family_id = resume_ids[0 if letter == 'A' else 1]
        source = f"""
Portal_User__c pilotUser = IdentitySelector.byUsername({quote(username)});
System.assertEquals({quote(family_id)}, String.valueOf(pilotUser.Family__c), 'Pilot membership mismatch');
System.assertEquals({quote(PREFIX + ' ' + letter)}, [SELECT Name FROM Family__c WHERE Id = :pilotUser.Family__c].Name, 'Pilot name mismatch');
String temporaryPassword = FamilyOnboardingService.resetPassword({quote(username)});
AuthService.LoginResult initial = AuthService.login({quote(username)}, temporaryPassword, {quote(UA)});
UserContext context = SessionService.require(initial.token, {quote(UA)}, true);
AuthService.firstLogin(context, {quote(password)}, {quote(UA)});
SessionService.revokeAll(pilotUser.Id, 'Pilot bootstrap complete', null);
System.debug('VKF_PILOT_BOOTSTRAP ' + JSON.serialize(new Map<String,Object>{{'familyId'=>pilotUser.Family__c,'userId'=>pilotUser.Id,'username'=>pilotUser.Username__c}}));
"""
    else:
        source = f"""
MemberService.MemberInput input = new MemberService.MemberInput();
input.firstName = 'Pilot'; input.lastName = {quote(letter)}; input.username = {quote(username)};
FamilyOnboardingService.Result created = FamilyOnboardingService.onboard({quote(PREFIX + ' ' + letter)}, 'INR', 'Asia/Kolkata', 6, input);
AuthService.LoginResult initial = AuthService.login(created.username, created.temporaryPassword, {quote(UA)});
UserContext context = SessionService.require(initial.token, {quote(UA)}, true);
AuthService.firstLogin(context, {quote(password)}, {quote(UA)});
SessionService.revokeAll(created.adminId, 'Pilot bootstrap complete', null);
System.debug('VKF_PILOT_BOOTSTRAP ' + JSON.serialize(new Map<String,Object>{{'familyId'=>created.familyId,'userId'=>created.adminId,'username'=>created.username}}));
"""
    info = apex(source, 'VKF_PILOT_BOOTSTRAP')
    info['password'] = password
    families.append(info)
    login = call('POST', '/auth/login', {'username': username, 'password': password})
    if login.get('mfaRequired'):
        raise RuntimeError('An unexpected MFA requirement applies to the disposable identity.')
    token = login['token']
    tokens.append(token)
    info['token'] = token
    assert login['profile']['familyId'] == info['familyId']
    settings = call('GET', '/enhancements/settings', token=token)
    if not resume_ids:
        assert settings['enabled'] == [], 'A newly created family must start with all features disabled.'
    call('PATCH', '/enhancements/settings', {'enabled': FEATURES, 'currentPassword': password}, token)
    return info


def balance(token, account_id):
    return next(item['balance'] for item in call('GET', '/accounts', token=token) if item['id'] == account_id)


def remove_fixtures():
    ids = [f['familyId'] for f in families]
    if not ids:
        return {'completed': True, 'familiesRemoved': 0}
    if not all(re.fullmatch(r'[a-zA-Z0-9]{15,18}', value) for value in ids):
        raise RuntimeError('Invalid pilot family identifier; cleanup refused.')
    for token in tokens:
        try:
            call('POST', '/auth/logout', {}, token)
        except Exception:
            pass
    source = f"""
Set<Id> familyIds = new Set<Id>{{{','.join(quote(value) for value in ids)}}};
List<Family__c> targets = [SELECT Id, Name FROM Family__c WHERE Id IN :familyIds];
System.assertEquals(familyIds.size(), targets.size(), 'Pilot family verification failed');
for (Family__c family : targets) System.assert(family.Name.startsWith({quote(PREFIX)}), 'Refusing to delete a non-pilot family');
Map<String,Object> binds = new Map<String,Object>{{'familyIds'=>familyIds}};
List<SObject> photos = Database.queryWithBinds('SELECT Id, Content_Document_Id__c FROM Transaction_Receipt__c WHERE Family__c IN :familyIds', binds, AccessLevel.SYSTEM_MODE);
Set<Id> documentIds = new Set<Id>();
for (SObject photo : photos) if (photo.get('Content_Document_Id__c') != null) documentIds.add((Id) photo.get('Content_Document_Id__c'));
if (!photos.isEmpty()) Database.delete(photos, true, AccessLevel.SYSTEM_MODE);
if (!documentIds.isEmpty()) Database.delete(Database.queryWithBinds('SELECT Id FROM ContentDocument WHERE Id IN :ids', new Map<String,Object>{{'ids'=>documentIds}}, AccessLevel.SYSTEM_MODE), true, AccessLevel.SYSTEM_MODE);
List<String> objects = new List<String>{{'Insight_Preference__c','Spend_Request__c','Savings_Goal__c','Statement_Row__c','Statement_Import__c',
    'Notification__c','Recurring_Rule__c','Card_Statement__c','Transaction__c','EMI_Installment__c','Loan__c','Bill_Instance__c','Bill__c',
    'Budget_Line__c','Budget__c','Monthly_Summary__c','Financial_Account__c','Portal_Session__c','Auth_Token__c'}};
Integer deletedRows = photos.size();
for (String objectName : objects) {{
    List<SObject> rows = Database.queryWithBinds('SELECT Id FROM ' + objectName + ' WHERE Family__c IN :familyIds', binds, AccessLevel.SYSTEM_MODE);
    if (!rows.isEmpty()) {{ deletedRows += rows.size(); Database.delete(rows, true, AccessLevel.SYSTEM_MODE); }}
}}
// Password history is master-detail and is removed with its pilot member.
Database.delete(Database.queryWithBinds('SELECT Id FROM Portal_User__c WHERE Family__c IN :familyIds', binds, AccessLevel.SYSTEM_MODE), true, AccessLevel.SYSTEM_MODE);
List<SObject> categories = Database.queryWithBinds('SELECT Id, Parent_Category__c FROM Category__c WHERE Family__c IN :familyIds', binds, AccessLevel.SYSTEM_MODE);
for (SObject category : categories) category.put('Parent_Category__c', null);
if (!categories.isEmpty()) {{ Database.update(categories, true, AccessLevel.SYSTEM_MODE); Database.delete(categories, true, AccessLevel.SYSTEM_MODE); }}
Database.delete(targets, true, AccessLevel.SYSTEM_MODE);
System.debug('VKF_PILOT_CLEANUP ' + JSON.serialize(new Map<String,Object>{{'completed'=>true,'familiesRemoved'=>targets.size(),'operationalRowsRemoved'=>deletedRows}}));
"""
    return apex(source.replace('AccessLevel.SYSTEM_MODE', 'AccessLevel.USER_MODE'), 'VKF_PILOT_CLEANUP')


def main():
    global cleanup
    try:
        print('Creating two isolated pilot families and signing in through the live guest API.', flush=True)
        a = bootstrap('A')
        b = bootstrap('B')
        ta, tb = a['token'], b['token']
        categories = call('GET', '/categories', token=ta)
        expense = next(c['id'] for c in categories if c['name'] == 'Groceries')
        income = next(c['id'] for c in categories if c['name'] == 'Salary')
        account = call('POST', '/accounts', {'name': 'Pilot bank', 'type': 'Savings', 'openingBalance': 1000}, ta)['id']
        txn = call('POST', '/transactions', {'type': 'Expense', 'amount': 12.5, 'date': TODAY, 'accountId': account, 'categoryId': expense, 'payee': 'Pilot receipt purchase'}, ta)['id']

        def import_check():
            entry = {'type': 'Expense', 'amount': 7.25, 'date': TODAY, 'categoryId': expense, 'payee': 'Pilot imported purchase', 'referenceNo': RUN}
            batch = call('POST', '/enhancements/imports', {'accountId': account, 'fileName': 'pilot.csv', 'rows': [entry, entry]}, ta)
            assert balance(ta, account) == 987.5, 'Staging moved money.'
            call('POST', '/enhancements/imports/' + batch['id'] + '/commit', {}, ta)
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                detail = call('GET', '/enhancements/imports/' + batch['id'], token=ta)
                if detail['status'] != 'Processing':
                    break
                time.sleep(3)
            assert detail['status'] == 'Completed', detail
            assert detail['imported'] == 1 and detail['duplicates'] == 1, detail
            assert balance(ta, account) == 980.25, 'Imported balance is wrong.'
            call('POST', '/enhancements/imports/' + batch['id'] + '/commit', {}, ta)
            assert balance(ta, account) == 980.25, 'Retry posted twice.'
            call('GET', '/enhancements/imports/' + batch['id'], token=tb, expect=(404,))
            return {'imported': 1, 'duplicates': 1, 'safeRetry': True, 'crossFamilyDenied': True}
        verify('Real guest-triggered statement batch, duplicate handling and isolation', import_check)

        def receipts_check():
            image = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOioAAAAASUVORK5CYII='
            body = {'fileName': 'pilot-receipt.png', 'mimeType': 'image/png', 'data': image}
            photo = call('POST', '/enhancements/transactions/' + txn + '/receipts', body, ta)
            assert call('POST', '/enhancements/transactions/' + txn + '/receipts', body, ta)['id'] == photo['id']
            assert call('GET', '/enhancements/receipts/' + photo['id'], token=ta)['data'] == image
            call('GET', '/enhancements/receipts/' + photo['id'], token=tb, expect=(404,))
            call('POST', '/enhancements/transactions/' + txn + '/receipts', body, tb, expect=(404,))
            assert len(call('GET', '/enhancements/transactions/' + txn + '/receipts', token=ta)) == 1
            mapping = apex(f"""Transaction_Receipt__c receipt = [SELECT Attachment_Id__c, Family__c FROM Transaction_Receipt__c WHERE Id = {quote(photo['id'])}];
System.assertEquals({quote(a['familyId'])}, String.valueOf(receipt.Family__c));
System.debug('VKF_PILOT_PHOTO ' + JSON.serialize(new Map<String,Object>{{'attachmentId'=>receipt.Attachment_Id__c}}));""", 'VKF_PILOT_PHOTO')
            origin = urllib.parse.urlsplit(SITE)
            for prefix in [SITE, origin.scheme + '://' + origin.netloc]:
                url = prefix + '/servlet/servlet.FileDownload?file=' + mapping['attachmentId']
                try:
                    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=30) as response:
                        raw = response.read(4096)
                except urllib.error.HTTPError:
                    raw = b''
                assert not raw.startswith(base64.b64decode(image)[:12]), 'The standard attachment URL exposed the receipt without a VK session.'
            call('DELETE', '/enhancements/receipts/' + photo['id'], token=ta)
            assert call('GET', '/enhancements/transactions/' + txn + '/receipts', token=ta) == []
            return {'guestUpload': True, 'privateDownload': True, 'deduplicated': True, 'crossFamilyDenied': True, 'anonymousDirectDownloadDenied': True, 'deleted': True}
        verify('Guest receipt upload, protected download and cross-family denial', receipts_check)

        def goals_check():
            starting = balance(ta, account)
            goal = call('POST', '/enhancements/goals', {'title': 'Pilot savings', 'target': 2000, 'accountId': account, 'includeExisting': True}, ta)
            assert goal['progress'] == starting
            assert call('GET', '/enhancements/goals', token=tb) == []
            call('PATCH', '/enhancements/goals/' + goal['id'], {'title': 'Forbidden', 'target': 2000}, tb, expect=(404,))
            call('POST', '/transactions', {'type': 'Income', 'amount': 20, 'date': TODAY, 'accountId': account, 'categoryId': income, 'payee': 'Pilot savings contribution'}, ta)
            assert call('GET', '/enhancements/goals', token=ta)[0]['progress'] == round(starting + 20, 2)
            return {'ledgerProgress': True, 'crossFamilyDenied': True}
        verify('Savings goal progress and isolation', goals_check)

        def requests_check():
            child_username = 'p6.' + RUN + '.child'
            prior = next((member for member in call('GET', '/family/members', token=ta) if member['username'] == child_username), None)
            if prior:
                temporary = call('POST', '/family/members/' + prior['id'] + '/reset-password', {'currentPassword': a['password']}, ta)['temporaryPassword']
            else:
                temporary = call('POST', '/family/members', {'firstName': 'PilotChild', 'lastName': 'Test', 'username': child_username, 'role': 'Child', 'relationship': 'Other'}, ta)['temporaryPassword']
            initial = call('POST', '/auth/login', {'username': child_username, 'password': temporary})
            tokens.append(initial['token'])
            password = 'Child!A7' + secrets.token_hex(12)
            passwords.append(password)
            signed_in = call('POST', '/auth/first-login', {'newPassword': password}, initial['token'])
            tc = signed_in['token']; tokens.append(tc)
            child_id = signed_in['profile']['userId']
            cash = call('POST', '/accounts', {'name': 'Pilot child cash', 'type': 'Cash', 'openingBalance': 100, 'ownerId': child_id}, ta)['id']
            request = call('POST', '/enhancements/requests', {'title': 'Pilot notebook', 'amount': 9.99, 'accountId': cash, 'categoryId': expense}, tc)
            call('POST', '/enhancements/requests/' + request['id'] + '/approve', {}, ta)
            assert balance(ta, cash) == 100, 'Approval posted an expense.'
            call('POST', '/enhancements/requests/' + request['id'] + '/approve', {}, tb, expect=(404,))
            call('POST', '/enhancements/requests/' + request['id'] + '/record', {}, tc)
            call('POST', '/enhancements/requests/' + request['id'] + '/record', {}, tc)
            assert balance(ta, cash) == 90.01, 'Recording was not idempotent.'
            return {'approvalWithoutPosting': True, 'explicitPurchase': True, 'safeRetry': True, 'crossFamilyDenied': True}
        verify('Child approval and explicit idempotent purchase recording', requests_check)

        def insights_check():
            call('POST', '/recurring', {'name': 'Pilot subscription', 'type': 'Expense', 'amount': 11, 'accountId': account, 'categoryId': expense,
                'frequency': 'Monthly', 'mode': 'Suggest', 'nextRunDate': (datetime.date.fromisoformat(TODAY) + datetime.timedelta(days=7)).isoformat()}, ta)
            items = call('GET', '/enhancements/insights', token=ta)
            item = next(i for i in items if 'Pilot subscription' in i['title'])
            assert call('GET', '/enhancements/insights', token=tb) == []
            call('POST', '/enhancements/insights/dismiss', {'key': item['key'], 'snooze': True}, ta)
            assert not any(i['key'] == item['key'] for i in call('GET', '/enhancements/insights', token=ta))
            return {'scopedSuggestion': True, 'personalSnooze': True}
        verify('Live insights scope and snooze', insights_check)

        if '--browser' in sys.argv:
            def browser_check():
                result = subprocess.run(['node', 'scripts/security/check-phase6-browser.mjs'], cwd=ROOT,
                    input=json.dumps({'site': SITE, 'token': ta, 'userAgent': UA}), capture_output=True, encoding='utf-8', timeout=180)
                if result.returncode:
                    raise RuntimeError(redact(result.stderr))
                return json.loads(result.stdout)
            verify('Authenticated live mobile browser: goals, receipt photos and install setup', browser_check)
    except Exception as error:
        checks.append({'name': 'Pilot setup or orchestration', 'passed': False, 'error': redact(error)})
        print('FAIL pilot setup: ' + redact(error), flush=True)
    finally:
        print('Removing disposable pilot families and their operational records.', flush=True)
        try:
            cleanup = remove_fixtures()
        except Exception as error:
            cleanup = {'completed': False, 'error': redact(error), 'pilotFamilyIds': [f['familyId'] for f in families], 'pilotPrefix': PREFIX}
        report = {'date': TODAY, 'checkedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'site': SITE,
                  'checks': checks, 'cleanup': cleanup, 'nativePhoneInstallation': 'Requires a real Android/iOS device; not claimed by API checks.'}
        path = ROOT / 'docs/phase6/Pilot_Checks.json'
        path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(json.dumps({'passed': sum(c['passed'] for c in checks), 'failed': sum(not c['passed'] for c in checks), 'cleanup': cleanup, 'report': str(path.relative_to(ROOT))}), flush=True)


if __name__ == '__main__':
    if '--resume' in sys.argv:
        previous = json.loads((ROOT / 'docs/phase6/Pilot_Checks.json').read_text(encoding='utf-8'))['cleanup']
        match = re.fullmatch(r'VKF Phase6 Pilot ([0-9a-f]{10})', previous.get('pilotPrefix', ''))
        if previous.get('completed') or not match or len(previous.get('pilotFamilyIds', [])) != 2:
            raise RuntimeError('No verified incomplete pilot is available to resume.')
        RUN = match.group(1); PREFIX = previous['pilotPrefix']; resume_ids = previous['pilotFamilyIds']
    main()
