// Read-only release verification. The trusted service reads new configuration
// in system mode; anonymous Apex retains the caller's field permissions.
Integer enabledFamilies = 0;
Integer familyCount = 0;
for (Family__c family : [SELECT Id FROM Family__c]) {
    familyCount++;
    UserContext context = new UserContext(new Portal_User__c(Family__c = family.Id), null, 'FULL');
    if (!EnhancementService.enabledFor(context).isEmpty()) enabledFamilies++;
}
System.debug('VKF_PHASE6_RELEASE ' + JSON.serialize(new Map<String, Object>{
    'families' => familyCount,
    'familiesWithEnabledEnhancements' => enabledFamilies,
    'roleGrants' => [SELECT COUNT() FROM Role_Permission__mdt WHERE Feature__c = 'ENHANCEMENTS'],
    'maintenanceSchedules' => [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'VKF Enhancement Maintenance']
}));
