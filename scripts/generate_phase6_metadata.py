"""Generate additive Phase 6 object/field/permission metadata. Safe to rerun."""
from pathlib import Path
from html import escape

ROOT = Path(__file__).resolve().parents[1] / 'force-app/main/default'
NS = 'http://soap.sforce.com/2006/04/metadata'

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + text + '\n', encoding='utf-8')

def field(obj, name, kind, **opts):
    label = opts.pop('label', name.removesuffix('__c').replace('_', ' '))
    parts = [f'<fullName>{name}</fullName>', f'<label>{label}</label>']
    if kind == 'Lookup':
        target = opts.pop('target')
        parts += ['<deleteConstraint>Restrict</deleteConstraint>', f'<referenceTo>{target}</referenceTo>',
                  f'<relationshipLabel>{obj.removesuffix("__c").replace("_", " ")} {label}</relationshipLabel>',
                  f'<relationshipName>{obj.removesuffix("__c")}_{name.removesuffix("__c")}</relationshipName>']
    defaults = {'Text': {'length': 255}, 'LongTextArea': {'length': 32768, 'visibleLines': 4},
                'Number': {'precision': 12, 'scale': 0}, 'Currency': {'precision': 16, 'scale': 2},
                'Checkbox': {'defaultValue': False}}
    for k, v in (defaults.get(kind, {}) | opts).items():
        v = str(v).lower() if isinstance(v, bool) else str(v)
        parts.append(f'<{k}>{escape(v)}</{k}>')
    parts.append(f'<type>{kind}</type>')
    write(ROOT / 'objects' / obj / 'fields' / f'{name}.field-meta.xml',
          f'<CustomField xmlns="{NS}">\n    ' + '\n    '.join(parts) + '\n</CustomField>')

def obj(name, label):
    write(ROOT / 'objects' / name / f'{name}.object-meta.xml', f'''<CustomObject xmlns="{NS}">
    <deploymentStatus>Deployed</deploymentStatus>
    <externalSharingModel>Private</externalSharingModel>
    <label>{label}</label>
    <nameField><displayFormat>P6-{{00000000}}</displayFormat><label>{label} Number</label><type>AutoNumber</type></nameField>
    <pluralLabel>{label}s</pluralLabel>
    <sharingModel>Private</sharingModel>
</CustomObject>''')
    field(name, 'Family__c', 'Lookup', target='Family__c', required=True)

def common(name, label, member='Member__c'):
    obj(name, label)
    field(name, member, 'Lookup', target='Portal_User__c', required=True)

field('Family__c', 'Enhancements__c', 'Text', length=255,
      description='Comma-separated opt-in Phase 6 feature keys. Blank leaves all enhancements off.')
field('Transaction__c', 'Import_Key__c', 'Text', length=64, unique=True, externalId=True,
      description='Server-generated family/account statement fingerprint. Makes import retries idempotent.')

common('Statement_Import__c', 'Statement Import')
for name, kind, opts in [
    ('Account__c', 'Lookup', {'target':'Financial_Account__c','required':True}),
    ('File_Name__c','Text',{'length':120}), ('Status__c','Text',{'length':24}),
    ('Job_Id__c','Text',{'length':18}), ('Total__c','Number',{}),
    ('Imported__c','Number',{}), ('Duplicates__c','Number',{}), ('Failed__c','Number',{}),
    ('Error__c','Text',{'length':255})]: field('Statement_Import__c', name, kind, **opts)

obj('Statement_Row__c', 'Statement Row')
for name, kind, opts in [
    ('Import__c','Lookup',{'target':'Statement_Import__c','required':True}),
    ('Row_No__c','Number',{}), ('Entry_JSON__c','LongTextArea',{'length':4096}),
    ('Fingerprint__c','Text',{'length':64}), ('Status__c','Text',{'length':24}),
    ('Error__c','Text',{'length':255}), ('Transaction__c','Lookup',{'target':'Transaction__c'})]:
    field('Statement_Row__c',name,kind,**opts)

common('Transaction_Receipt__c', 'Transaction Receipt')
for name, kind, opts in [
    ('Transaction__c','Lookup',{'target':'Transaction__c','required':True}),
    ('File_Name__c','Text',{'length':120}), ('Mime_Type__c','Text',{'length':32}),
    ('Bytes__c','Number',{}), ('Attachment_Id__c','Text',{'length':18}), ('Content_Version_Id__c','Text',{'length':18}),
    ('Content_Document_Id__c','Text',{'length':18}), ('Dedupe_Key__c','Text',{'length':64,'unique':True})]:
    field('Transaction_Receipt__c',name,kind,**opts)

common('Spend_Request__c','Spend Request', 'Child__c')
for name, kind, opts in [
    ('Title__c','Text',{'length':120}), ('Amount__c','Currency',{}),
    ('Account__c','Lookup',{'target':'Financial_Account__c','required':True}),
    ('Category__c','Lookup',{'target':'Category__c','required':True}),
    ('Status__c','Text',{'length':24}), ('Note__c','Text',{'length':255}),
    ('Decision_Note__c','Text',{'length':255}), ('Decided_By__c','Lookup',{'target':'Portal_User__c'}),
    ('Decided_At__c','DateTime',{}), ('Valid_Until__c','Date',{}),
    ('Transaction__c','Lookup',{'target':'Transaction__c'})]: field('Spend_Request__c',name,kind,**opts)

common('Savings_Goal__c','Savings Goal')
for name, kind, opts in [
    ('Title__c','Text',{'length':80}), ('Target__c','Currency',{}), ('Baseline__c','Currency',{}),
    ('Target_Date__c','Date',{}), ('Account__c','Lookup',{'target':'Financial_Account__c','required':True}),
    ('Status__c','Text',{'length':24}), ('Account_Key__c','Text',{'length':64,'unique':True}),
    ('Color__c','Text',{'length':20})]: field('Savings_Goal__c',name,kind,**opts)

common('Insight_Preference__c','Insight Preference')
for name, kind, opts in [
    ('Insight_Key__c','Text',{'length':120}), ('Unique_Key__c','Text',{'length':64,'unique':True}),
    ('Hidden_Until__c','Date',{})]: field('Insight_Preference__c',name,kind,**opts)

role_names = {'FA':'Family Admin','CA':'Co-Admin','MB':'Member','CH':'Child','VW':'Viewer'}
grants = {
    'ENHANCEMENTS':{'FA':'READ,EDIT','CA':'READ','MB':'READ','CH':'READ','VW':'READ'},
    'IMPORTS':{'FA':'READ,CREATE','CA':'READ,CREATE','MB':'READ,CREATE'},
    'RECEIPTS':{'FA':'READ,CREATE,DELETE','CA':'READ,CREATE,DELETE','MB':'READ,CREATE,DELETE','CH':'READ,CREATE,DELETE','VW':'READ'},
    'REQUESTS':{'FA':'READ,APPROVE','CA':'READ,APPROVE','CH':'READ,CREATE,CANCEL'},
    'GOALS':{'FA':'READ,CREATE,EDIT,DELETE','CA':'READ,CREATE,EDIT,DELETE','MB':'READ,CREATE,EDIT,DELETE','CH':'READ,CREATE,EDIT,DELETE','VW':'READ'},
    'INSIGHTS':{r:'READ' for r in role_names},
}
for feature, members in grants.items():
    for short, actions in members.items():
        vals={'Role__c':role_names[short],'Feature__c':feature,'Actions__c':actions,'Scope__c':'OWN'}
        body='\n'.join(f'    <values><field>{k}</field><value xsi:type="xsd:string">{escape(v)}</value></values>' for k,v in vals.items())
        write(ROOT/'customMetadata'/f'Role_Permission.{short}_{feature}.md-meta.xml',f'''<CustomMetadata xmlns="{NS}" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>{role_names[short]} - {feature}</label><protected>false</protected>
{body}
</CustomMetadata>''')

if __name__ == '__main__':
    # Internal support needs visibility and cleanup rights on the new records.
    # Portal guests keep their original class-only permission set.
    import re
    admin_path = ROOT/'permissionsets/VKF_Platform_Admin.permissionset-meta.xml'
    admin_text = admin_path.read_text(encoding='utf-8')
    admin_text = re.sub(r'    <!-- Phase 6 support fields -->.*?    <!-- End Phase 6 support fields -->\n', '', admin_text, flags=re.S)
    admin_text = re.sub(r'    <!-- Phase 6 support objects -->.*?    <!-- End Phase 6 support objects -->\n', '', admin_text, flags=re.S)
    new_objects = ['Statement_Import__c','Statement_Row__c','Transaction_Receipt__c','Spend_Request__c','Savings_Goal__c','Insight_Preference__c']
    import xml.etree.ElementTree as ET
    ns = {'m': NS}
    readable_fields = ['Family__c.Enhancements__c','Transaction__c.Import_Key__c']
    for object_name in new_objects:
        for path in sorted((ROOT/'objects'/object_name/'fields').glob('*.xml')):
            definition = ET.parse(path).getroot()
            if definition.findtext('m:required',namespaces=ns) != 'true':
                readable_fields.append(object_name+'.'+definition.findtext('m:fullName',namespaces=ns))
    field_block = '    <!-- Phase 6 support fields -->\n' + ''.join(
        f'    <fieldPermissions><editable>false</editable><field>{name}</field><readable>true</readable></fieldPermissions>\n'
        for name in readable_fields) + '    <!-- End Phase 6 support fields -->\n'
    admin_text = admin_text.replace('    <hasActivationRequired>',field_block+'    <hasActivationRequired>',1)
    object_block = '    <!-- Phase 6 support objects -->\n' + ''.join(
        f'    <objectPermissions><allowCreate>false</allowCreate><allowDelete>true</allowDelete><allowEdit>true</allowEdit><allowRead>true</allowRead><modifyAllRecords>true</modifyAllRecords><object>{name}</object><viewAllRecords>true</viewAllRecords></objectPermissions>\n'
        for name in new_objects) + '    <!-- End Phase 6 support objects -->\n'
    admin_text = admin_text.replace('    <tabSettings>',object_block+'    <tabSettings>',1)
    admin_path.write_text(admin_text,encoding='utf-8')
    classes = ['EnhancementService','SpendRequestService','SavingsGoalService','StatementImportService',
               'StatementImportWorker','ReceiptService','SmartInsightService','VkfEnhancementsResource','EnhancementMaintenanceJob',
               'Phase6ServiceTest','Phase6ImportTest','Phase6ReceiptTest','Phase6ResourceTest']
    for name in classes:
        write(ROOT/'classes'/f'{name}.cls-meta.xml', f'<ApexClass xmlns="{NS}"><apiVersion>68.0</apiVersion><status>Active</status></ApexClass>')
    types = {'ApexClass':classes,
             'CustomObject':['Statement_Import__c','Statement_Row__c','Transaction_Receipt__c','Spend_Request__c','Savings_Goal__c','Insight_Preference__c'],
             'CustomField':['Family__c.Enhancements__c','Transaction__c.Import_Key__c'],
             'CustomMetadata':[f'Role_Permission.{r}_{feature}' for feature, roles in grants.items() for r in roles],
             'PermissionSet':['VKF_Guest_Api_Access','VKF_Platform_Admin']}
    manifest='\n'.join('    <types>'+''.join(f'<members>{v}</members>' for v in members)+f'<name>{kind}</name></types>' for kind,members in types.items())
    write(ROOT.parents[2]/'manifest'/'phase6.xml',f'<Package xmlns="{NS}">\n{manifest}\n<version>68.0</version>\n</Package>')
    print('Generated additive Phase 6 objects, fields and role grants. Existing grant records were not changed.')
