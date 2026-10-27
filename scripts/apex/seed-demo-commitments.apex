// Adds bills, loans and recurring rules to Demo Family A (run seed-demo-finance.apex first),
// then queues the daily dues job so statements and reminders appear. Run it twice: the first
// run adds bills and loans, the second adds recurring rules and starts the job (one Apex
// transaction can't do it all). Demo data only. Runs as you, so you need the
// VKF_Platform_Admin permission set.
//   sf apex run --target-org VKFinance --file scripts/apex/seed-demo-commitments.apex
Portal_User__c admin = [SELECT Id, Family__c FROM Portal_User__c WHERE Username__c = 'demo.admin.a'];
Id son = [SELECT Id FROM Portal_User__c WHERE Username__c = 'demo.son.a'].Id;
Id fid = admin.Family__c;

Boolean needBills = [SELECT COUNT() FROM Bill__c WHERE Family__c = :fid] == 0;
Boolean needRules = [SELECT COUNT() FROM Recurring_Rule__c WHERE Family__c = :fid] == 0;
if (!needBills && !needRules) {
    System.debug(LoggingLevel.ERROR, 'VKF_SEED demo commitments already present - nothing to do');
} else {
    UserContext ctx = SystemContext.forMember(admin.Id);
    Map<String, Id> acct = new Map<String, Id>();
    for (Financial_Account__c a : [SELECT Id, Name FROM Financial_Account__c WHERE Family__c = :fid]) {
        acct.put(a.Name, a.Id);
    }
    Map<String, Id> cat = new Map<String, Id>();
    for (Category__c c : [SELECT Id, Name FROM Category__c WHERE Family__c = :fid]) {
        cat.put(c.Name, c.Id);
    }
    Date today = Date.today();
    Date nextMonth = today.toStartOfMonth().addMonths(1);

    List<Map<String, Object>> bills = new List<Map<String, Object>>{
        new Map<String, Object>{ 'name' => 'BESCOM Electricity', 'categoryId' => cat.get('Electricity'), 'nextDueDate' => String.valueOf(today.addDays(3)), 'expectedAmount' => 2400, 'payFromAccountId' => acct.get('ICICI Household'), 'consumerNo' => '7781 2290 41' },
        new Map<String, Object>{ 'name' => 'ACT Fibernet', 'categoryId' => cat.get('Internet'), 'nextDueDate' => String.valueOf(today.addDays(11)), 'expectedAmount' => 999, 'payFromAccountId' => acct.get('Amazon Pay ICICI'), 'autoPay' => true },
        new Map<String, Object>{ 'name' => 'Netflix', 'categoryId' => cat.get('OTT / Streaming'), 'nextDueDate' => String.valueOf(today.addDays(2)), 'expectedAmount' => 649, 'payFromAccountId' => acct.get('Amazon Pay ICICI'), 'autoPay' => true },
        new Map<String, Object>{ 'name' => 'LIC Term Plan', 'categoryId' => cat.get('Life / Term'), 'frequency' => 'Yearly', 'nextDueDate' => String.valueOf(today.addDays(38)), 'expectedAmount' => 24500, 'payFromAccountId' => acct.get('HDFC Salary'), 'reminderDays' => 10 },
        new Map<String, Object>{ 'name' => 'BWSSB Water', 'categoryId' => cat.get('Water'), 'frequency' => 'Bi-monthly', 'nextDueDate' => String.valueOf(today.addDays(-2)), 'expectedAmount' => 380, 'payFromAccountId' => acct.get('ICICI Household') },
        new Map<String, Object>{ 'name' => 'Maths tuition', 'categoryId' => cat.get('Tuition and Coaching'), 'nextDueDate' => String.valueOf(today.addDays(6)), 'expectedAmount' => 3500, 'payFromAccountId' => acct.get('ICICI Household'), 'responsibleId' => son }
    };
    for (Map<String, Object> b : needBills ? bills : new List<Map<String, Object>>()) {
        BillService.createBill(ctx, b);
    }

    if (needBills) {
    Date carStart = Date.newInstance(today.addMonths(-15).year(), today.addMonths(-15).month(), 10);
    LoanService.createLoan(ctx, new Map<String, Object>{
        'name' => 'Car loan', 'lender' => 'HDFC Bank', 'loanType' => 'Car', 'principal' => 800000, 'annualRate' => 9.25, 'tenureMonths' => 60,
        'firstEmiDate' => String.valueOf(carStart), 'installmentsPaid' => 15, 'debitAccountId' => acct.get('HDFC Salary'), 'autoDebit' => true
    });
    Date laptopStart = Date.newInstance(today.addMonths(-5).year(), today.addMonths(-5).month(), 3);
    LoanService.createLoan(ctx, new Map<String, Object>{
        'name' => 'Laptop EMI', 'lender' => 'Bajaj Finserv', 'loanType' => 'Consumer Durable', 'principal' => 60000, 'annualRate' => 14, 'tenureMonths' => 12,
        'firstEmiDate' => String.valueOf(laptopStart), 'installmentsPaid' => 5, 'debitAccountId' => acct.get('HDFC Salary')
    });
    System.debug(LoggingLevel.ERROR, 'VKF_SEED demo commitments: 6 bills and 2 loans added - run this script once more');
    }

    List<Map<String, Object>> rules = new List<Map<String, Object>>{
        new Map<String, Object>{ 'name' => 'Salary', 'type' => 'Income', 'amount' => 145000, 'accountId' => acct.get('HDFC Salary'), 'categoryId' => cat.get('Salary'), 'payee' => 'Infosys Ltd', 'nextRunDate' => String.valueOf(nextMonth), 'mode' => 'Suggest' },
        new Map<String, Object>{ 'name' => 'Rent', 'type' => 'Expense', 'amount' => 32000, 'accountId' => acct.get('HDFC Salary'), 'categoryId' => cat.get('Rent'), 'payee' => 'Mr. Raghavan (landlord)', 'nextRunDate' => String.valueOf(nextMonth.addDays(2)), 'mode' => 'Auto-post' },
        new Map<String, Object>{ 'name' => 'Monthly SIP', 'type' => 'Transfer', 'amount' => 10000, 'accountId' => acct.get('HDFC Salary'), 'toAccountId' => acct.get('Mutual Funds'), 'nextRunDate' => String.valueOf(nextMonth.addDays(9)), 'mode' => 'Auto-post' },
        new Map<String, Object>{ 'name' => 'Arjun pocket money', 'type' => 'Transfer', 'amount' => 1000, 'accountId' => acct.get('ICICI Household'), 'toAccountId' => acct.get('Arjun Pocket Money'), 'nextRunDate' => String.valueOf(nextMonth), 'mode' => 'Auto-post' }
    };
    if (!needBills && needRules) {
        for (Map<String, Object> r : rules) {
            RecurringService.createRule(ctx, r);
        }
        Database.executeBatch(new DailyDuesBatch(), 1);
        System.debug(LoggingLevel.ERROR, 'VKF_SEED demo commitments: ' + rules.size() + ' rules added and the daily dues job started - done');
    }
}
