"""Exercise shared credit on the published portal using one disposable family.

Credentials stay in memory. Cleanup verifies the exact generated family ID and name.
This never groups or changes an existing family's cards. Requires VKF_Platform_Admin.
"""
from pathlib import Path
import datetime
import json
import secrets
import subprocess
import tempfile
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ORG = 'VKFINANCE'
SITE = 'https://orgfarm-db588f31ab-dev-ed.develop.my.site.com/VKFinancePortal'
API = SITE + '/sf/api/services/apexrest/vkf/v1'
UA = 'Mozilla/5.0 VKF-Shared-Credit-Pilot Chrome/130.0 Safari/537.36'
RUN = secrets.token_hex(5)
NAME = 'VKF Shared Credit Pilot ' + RUN
username = 'credit.pilot.' + RUN
password = 'Z7!h' + secrets.token_hex(12)
private_values = [password]
family_id = None
token = None
checks = []
cleanup = {'completed': False}


def quote(value):
    return "'" + str(value).replace('\\', '\\\\').replace("'", "\\'") + "'"


def safe(value):
    text = str(value)
    for secret in private_values:
        text = text.replace(secret, '[redacted]')
    return text[:800]


def apex(source, marker):
    with tempfile.NamedTemporaryFile(mode='w', suffix='.apex', encoding='utf-8') as f:
        f.write(source)
        f.flush()
        process = subprocess.run(['sf', 'apex', 'run', '--target-org', ORG, '--file', f.name, '--json'],
                                 cwd=ROOT, capture_output=True, text=True, timeout=180)
    data = json.loads(process.stdout)
    result = data.get('result', {})
    if data.get('status') or not result.get('success'):
        raise RuntimeError(safe(data.get('message') or result.get('exceptionMessage') or result.get('compileProblem')))
    for line in result.get('logs', '').splitlines():
        if '|DEBUG|' + marker + ' ' in line:
            return json.loads(line.split('|DEBUG|' + marker + ' ', 1)[1])
    raise RuntimeError('Missing pilot result marker.')


def call(method, path, body=None, expected=(200, 201, 204)):
    headers = {'User-Agent': UA, 'Accept': 'application/json', 'Cache-Control': 'no-store'}
    if token:
        headers['X-VKF-Session'] = token
    if body is not None:
        headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(API + path, method=method, headers=headers,
                                     data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            status, content = response.status, response.read()
    except urllib.error.HTTPError as e:
        status, content = e.code, e.read()
    data = json.loads(content) if content else None
    if status not in expected:
        raise RuntimeError(safe(f'{method} {path}: HTTP {status}; {data}'))
    return data


def passed(name):
    checks.append({'name': name, 'passed': True})
    print('PASS ' + name, flush=True)


def remove_family():
    if family_id is None:
        return {'completed': True, 'familiesRemoved': 0}
    return apex(f"""
Id fid = {quote(family_id)};
Family__c target = [SELECT Id, Name FROM Family__c WHERE Id = :fid];
Assert.areEqual({quote(NAME)}, target.Name, 'Cleanup only the exact disposable family.');
List<Financial_Account__c> accounts = [SELECT Id, Credit_Limit_Group__c FROM Financial_Account__c WHERE Family__c = :fid];
for (Financial_Account__c account : accounts) account.Credit_Limit_Group__c = null;
if (!accounts.isEmpty()) update accounts;
delete [SELECT Id FROM Transaction__c WHERE Family__c = :fid];
delete [SELECT Id FROM Credit_Limit_Group__c WHERE Family__c = :fid];
delete [SELECT Id FROM Card_Statement__c WHERE Family__c = :fid];
delete accounts;
delete [SELECT Id FROM Notification__c WHERE Family__c = :fid];
delete [SELECT Id FROM Portal_Session__c WHERE Family__c = :fid];
delete [SELECT Id FROM Auth_Token__c WHERE Family__c = :fid];
delete [SELECT Id FROM Portal_User__c WHERE Family__c = :fid];
List<Category__c> categories = [SELECT Id, Parent_Category__c FROM Category__c WHERE Family__c = :fid];
for (Category__c category : categories) category.Parent_Category__c = null;
if (!categories.isEmpty()) {{ update categories; delete categories; }}
delete target;
System.debug('VKF_SHARED_CLEANUP ' + JSON.serialize(new Map<String,Object>{{'completed'=>true,'familiesRemoved'=>1}}));
""", 'VKF_SHARED_CLEANUP')


def main():
    global family_id, token, cleanup
    failed = None
    try:
        created = apex(f"""
Assert.isTrue(FeatureManagement.checkPermission('VKF_Platform_Admin'));
MemberService.MemberInput input = new MemberService.MemberInput();
input.firstName = 'Shared'; input.lastName = 'Pilot'; input.username = {quote(username)};
FamilyOnboardingService.Result created = FamilyOnboardingService.onboard({quote(NAME)}, 'INR', 'Asia/Kolkata', 3, input);
AuthService.LoginResult initial = AuthService.login(created.username, created.temporaryPassword, {quote(UA)});
UserContext context = SessionService.require(initial.token, {quote(UA)}, true);
AuthService.firstLogin(context, {quote(password)}, {quote(UA)});
SessionService.revokeAll(created.adminId, 'Shared-credit bootstrap complete', null);
System.debug('VKF_SHARED_BOOTSTRAP ' + JSON.serialize(new Map<String,Object>{{'familyId'=>created.familyId}}));
""", 'VKF_SHARED_BOOTSTRAP')
        family_id = created['familyId']
        login = call('POST', '/auth/login', {'username': username, 'password': password})
        token = login['token']
        private_values.append(token)
        bank = call('POST', '/accounts', {'name': 'Pilot bank', 'type': 'Savings', 'openingBalance': 100000})
        cards = [call('POST', '/accounts', {'name': name, 'type': 'Credit Card', 'openingBalance': balance,
                 'creditLimit': 200000, 'statementDay': 15, 'institution': 'Example Bank'})
                 for name, balance in [('Pilot everyday card', 30000), ('Pilot travel card', 20000)]]
        body = {'name': 'Pilot shared facility', 'issuer': 'Example Bank', 'creditLimit': 300000, 'cardIds': [c['id'] for c in cards]}
        view = call('POST', '/accounts/credit-groups', body)
        group = view['groups'][0]
        assert group['available'] == 250000 and view['totals']['creditLimit'] == 300000
        for card in call('GET', '/accounts'):
            if card['id'] in body['cardIds']:
                assert card['card']['available'] == 250000
        passed('Guest API creates one shared facility and counts its limit once')
        today = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=5, minutes=30))).date().isoformat()
        payment = call('POST', '/transfers', {'fromAccountId': bank['id'], 'toAccountId': cards[0]['id'], 'amount': 1000, 'date': today})
        assert call('GET', '/accounts/credit-groups')['groups'][0]['available'] == 251000
        call('DELETE', '/transactions/' + payment['inLeg']['id'])
        assert call('GET', '/accounts/credit-groups')['groups'][0]['available'] == 250000
        passed('Payment and void update shared availability without stored balance drift')
        reduced = call('PATCH', '/accounts/credit-groups/' + group['id'], {**body, 'creditLimit': 40000, 'expectedVersion': group['version']})['groups'][0]
        assert reduced['available'] == 0 and reduced['overLimit'] == 10000
        call('PATCH', '/accounts/credit-groups/' + group['id'], {**body, 'expectedVersion': group['version']}, expected=(409,))
        group = call('PATCH', '/accounts/credit-groups/' + group['id'], {**body, 'expectedVersion': reduced['version']})['groups'][0]
        passed('Over-limit display and stale-editor protection work on the live API')
        browser = subprocess.run(['node', 'scripts/security/check-shared-credit-browser.mjs'], cwd=ROOT,
            input=json.dumps({'site': SITE, 'token': token, 'userAgent': UA}), capture_output=True, text=True, timeout=180)
        if browser.returncode:
            raise RuntimeError(safe(browser.stderr))
        assert json.loads(browser.stdout)['liveSharedLimitEdited']
        passed('Authenticated live phone browser can edit the shared facility')
        group = call('GET', '/accounts/credit-groups')['groups'][0]
        assert group['creditLimit'] == 350000 and group['available'] == 300000
        archived = call('POST', '/accounts/credit-groups/' + group['id'] + '/archive', {'expectedVersion': group['version']})
        assert archived['groups'] == [] and archived['totals']['creditLimit'] == 400000
        balances = {a['id']: a['balance'] for a in call('GET', '/accounts')}
        assert balances[cards[0]['id']] == 30000 and balances[cards[1]['id']] == 20000 and balances[bank['id']] == 100000
        passed('Archiving restores independent limits and preserves balances')
    except Exception as error:
        failed = safe(error)
        print('FAIL ' + failed, flush=True)
    finally:
        try:
            cleanup = remove_family()
        except Exception as error:
            cleanup = {'completed': False, 'error': safe(error), 'pilotFamilyId': family_id, 'pilotFamilyName': NAME}
        report = {'targetOrg': ORG, 'site': SITE, 'checks': checks, 'error': failed, 'cleanup': cleanup}
        output = ROOT / 'docs/shared-credit-limits/Live_Pilot.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({'checksPassed': len(checks), 'cleanup': cleanup}), flush=True)
    if failed or not cleanup.get('completed'):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
