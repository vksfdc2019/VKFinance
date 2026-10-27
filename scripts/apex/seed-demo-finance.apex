// Seeds about four months of realistic family finances for Demo Family A (demo.admin.a),
// ending today: accounts, salary, bills, groceries, card spend and payments, SIPs, pocket
// money for Arjun (demo.son.a), and budgets for this month and last. Demo data only.
// Safe to re-run: it does nothing if the demo accounts already exist. Runs as you, so you need
// the VKF_Platform_Admin permission set (anonymous Apex cannot use system mode).
//   sf apex run --target-org VKFinance --file scripts/apex/seed-demo-finance.apex
Portal_User__c admin = [SELECT Id, Family__c FROM Portal_User__c WHERE Username__c = 'demo.admin.a'];
Portal_User__c son = [SELECT Id FROM Portal_User__c WHERE Username__c = 'demo.son.a'];
Id fid = admin.Family__c;

// Leftovers from API smoke tests.
List<Financial_Account__c> smoke = [SELECT Id FROM Financial_Account__c WHERE Family__c = :fid AND Name LIKE 'Smoke %'];
delete [SELECT Id FROM Transaction__c WHERE Account__c IN :smoke];
delete smoke;

if ([SELECT COUNT() FROM Financial_Account__c WHERE Family__c = :fid AND Name = 'HDFC Salary'] > 0) {
    System.debug(LoggingLevel.ERROR, 'VKF_SEED demo finance already present - nothing to do');
} else {
    CategoryService.seedDefaults(fid);
    Map<String, Id> cat = new Map<String, Id>();
    for (Category__c c : [SELECT Id, Name, System_Key__c FROM Category__c WHERE Family__c = :fid]) {
        cat.put(c.System_Key__c != null ? c.System_Key__c : c.Name, c.Id);
    }

    Date today = Date.today();
    Date start = today.toStartOfMonth().addMonths(-3);
    Map<String, Financial_Account__c> acct = new Map<String, Financial_Account__c>{
        'salary' => new Financial_Account__c(Name = 'HDFC Salary', Type__c = 'Savings', Institution__c = 'HDFC Bank', Last4__c = '4821', Opening_Balance__c = 185000, Color__c = 'teal', Owner_Member__c = admin.Id),
        'house' => new Financial_Account__c(Name = 'ICICI Household', Type__c = 'Current', Institution__c = 'ICICI Bank', Last4__c = '1907', Opening_Balance__c = 42000, Color__c = 'sky', Owner_Member__c = admin.Id, Is_Shared__c = true),
        'cash' => new Financial_Account__c(Name = 'Cash Wallet', Type__c = 'Cash', Opening_Balance__c = 6000, Color__c = 'emerald', Owner_Member__c = admin.Id),
        'card' => new Financial_Account__c(Name = 'Amazon Pay ICICI', Type__c = 'Credit Card', Institution__c = 'ICICI Bank', Last4__c = '3344', Opening_Balance__c = 0, Credit_Limit__c = 200000, Statement_Day__c = 12, Payment_Due_Days__c = 18, Min_Due_Pct__c = 5, Color__c = 'slate', Owner_Member__c = admin.Id),
        'arjun' => new Financial_Account__c(Name = 'Arjun Pocket Money', Type__c = 'Cash', Opening_Balance__c = 800, Color__c = 'violet', Owner_Member__c = son.Id),
        'fd' => new Financial_Account__c(Name = 'SBI Fixed Deposit', Type__c = 'Fixed Deposit', Institution__c = 'SBI', Opening_Balance__c = 300000, Color__c = 'amber', Owner_Member__c = admin.Id),
        'mf' => new Financial_Account__c(Name = 'Mutual Funds', Type__c = 'Investment', Institution__c = 'Zerodha Coin', Opening_Balance__c = 450000, Color__c = 'indigo', Owner_Member__c = admin.Id)
    };
    Integer order = 1;
    for (Financial_Account__c a : acct.values()) {
        a.Family__c = fid;
        a.Status__c = 'Active';
        a.Opening_Date__c = start;
        a.Sort_Order__c = order++;
    }
    insert acct.values();

    // day, type, low, high, account, category, payee, mode, member ('a' admin / 's' son); month -1 = every month
    List<List<Object>> plan = new List<List<Object>>{
        new List<Object>{ 1, 'Income', 145000, 145000, 'salary', 'Salary', 'Infosys Ltd', 'NEFT/IMPS', 'a', -1 },
        new List<Object>{ 2, 'Expense', 1800, 2100, 'house', 'Milk and Daily Essentials', 'Nandini Dairy', 'UPI', 'a', -1 },
        new List<Object>{ 3, 'Expense', 32000, 32000, 'salary', 'Rent', 'Mr. Raghavan (landlord)', 'NEFT/IMPS', 'a', -1 },
        new List<Object>{ 4, 'Expense', 3500, 3500, 'house', 'Society Maintenance', 'Green Meadows RWA', 'UPI', 'a', -1 },
        new List<Object>{ 6, 'Expense', 2600, 4400, 'house', 'Groceries', 'DMart', 'UPI', 'a', -1 },
        new List<Object>{ 13, 'Expense', 2800, 4600, 'house', 'Groceries', 'Reliance Fresh', 'UPI', 'a', -1 },
        new List<Object>{ 20, 'Expense', 2500, 4200, 'house', 'Groceries', 'BigBasket', 'UPI', 'a', -1 },
        new List<Object>{ 27, 'Expense', 2400, 3900, 'house', 'Groceries', 'DMart', 'UPI', 'a', -1 },
        new List<Object>{ 7, 'Expense', 999, 999, 'card', 'Internet', 'ACT Fibernet', 'Auto-debit', 'a', -1 },
        new List<Object>{ 9, 'Expense', 649, 649, 'card', 'OTT / Streaming', 'Netflix', 'Auto-debit', 'a', -1 },
        new List<Object>{ 11, 'Expense', 1900, 2900, 'house', 'Electricity', 'BESCOM', 'UPI', 'a', -1 },
        new List<Object>{ 15, 'Expense', 1100, 1100, 'house', 'Cooking Gas', 'Indane Gas', 'UPI', 'a', -1 },
        new List<Object>{ 16, 'Expense', 399, 399, 'card', 'Mobile Recharge', 'Jio', 'Credit Card', 'a', -1 },
        new List<Object>{ 8, 'Expense', 2800, 3600, 'card', 'Fuel', 'Indian Oil', 'Credit Card', 'a', -1 },
        new List<Object>{ 22, 'Expense', 2600, 3400, 'card', 'Fuel', 'HP Petrol', 'Credit Card', 'a', -1 },
        new List<Object>{ 12, 'Expense', 1400, 3200, 'card', 'Restaurants and Takeaway', 'Swiggy', 'Credit Card', 'a', -1 },
        new List<Object>{ 24, 'Expense', 1800, 3800, 'card', 'Restaurants and Takeaway', 'Meghana Foods', 'Credit Card', 'a', -1 },
        new List<Object>{ 18, 'Expense', 450, 1600, 'cash', 'Pharmacy', 'Apollo Pharmacy', 'Cash', 'a', -1 },
        new List<Object>{ 26, 'Expense', 300, 700, 'cash', 'Snacks and Beverages', 'Chai Point', 'Cash', 'a', -1 },
        new List<Object>{ 21, 'Expense', 250, 600, 'cash', 'Cab / Auto', 'Namma Yatri', 'Cash', 'a', -1 },
        new List<Object>{ 8, 'Expense', 120, 300, 'arjun', 'Snacks and Beverages', 'School canteen', 'Cash', 's', -1 },
        new List<Object>{ 17, 'Expense', 150, 350, 'arjun', 'Books and Stationery', 'Sapna Book House', 'Cash', 's', -1 },
        new List<Object>{ 25, 'Expense', 120, 280, 'arjun', 'Snacks and Beverages', 'Cafe Coffee Day', 'Cash', 's', -1 },
        new List<Object>{ 5, 'Expense', 45000, 45000, 'salary', 'School / College Fees', 'Delhi Public School', 'NEFT/IMPS', 'a', 0 },
        new List<Object>{ 19, 'Expense', 800, 800, 'cash', 'Doctor Consultation', 'Dr. Mehta Clinic', 'Cash', 'a', 0 },
        new List<Object>{ 14, 'Expense', 4500, 4500, 'card', 'Clothing and Footwear', 'Myntra', 'Credit Card', 'a', 0 },
        new List<Object>{ 16, 'Expense', 1200, 1200, 'card', 'Movies and Shows', 'PVR Cinemas', 'Credit Card', 'a', 1 },
        new List<Object>{ 23, 'Expense', 7999, 7999, 'card', 'Electronics', 'Croma', 'Credit Card', 'a', 1 },
        new List<Object>{ 28, 'Income', 5400, 5400, 'salary', 'Interest and Dividends', 'SBI FD interest', 'NEFT/IMPS', 'a', 1 },
        new List<Object>{ 13, 'Expense', 6500, 6500, 'card', 'Trips and Picnics', 'Coorg weekend', 'Credit Card', 'a', 2 },
        new List<Object>{ 20, 'Refund', 1299, 1299, 'card', 'Clothing and Footwear', 'Amazon refund', 'Credit Card', 'a', 2 },
        new List<Object>{ 9, 'Expense', 1200, 1200, 'cash', 'Doctor Consultation', 'Dr. Mehta Clinic', 'Cash', 'a', 2 },
        new List<Object>{ 10, 'Expense', 2200, 2200, 'salary', 'Lab Tests and Scans', 'Thyrocare', 'UPI', 'a', 2 },
        new List<Object>{ 5, 'Expense', 45000, 45000, 'salary', 'School / College Fees', 'Delhi Public School', 'NEFT/IMPS', 'a', 3 },
        new List<Object>{ 19, 'Expense', 5000, 5000, 'salary', 'Gifts Given', 'Diwali gifts', 'UPI', 'a', 3 },
        new List<Object>{ 20, 'Expense', 1100, 1100, 'cash', 'Religious Offerings', 'Temple', 'Cash', 'a', 3 },
        new List<Object>{ 25, 'Income', 25000, 25000, 'salary', 'Bonus and Incentives', 'Infosys Ltd (Diwali bonus)', 'NEFT/IMPS', 'a', 3 },
        new List<Object>{ 14, 'Expense', 900, 900, 'card', 'Movies and Shows', 'INOX', 'Credit Card', 'a', 3 }
    };
    // day, from, to, amount, note; month -1 = every month
    List<List<Object>> moves = new List<List<Object>>{
        new List<Object>{ 1, 'house', 'arjun', 1000, 'Pocket money', -1 },
        new List<Object>{ 2, 'salary', 'house', 25000, 'Household money', -1 },
        new List<Object>{ 2, 'salary', 'cash', 3000, 'ATM withdrawal', -1 },
        new List<Object>{ 10, 'salary', 'mf', 10000, 'Monthly SIP', -1 }
    };

    Long seed = 20261027;
    List<Transaction__c> rows = new List<Transaction__c>();
    List<List<Transaction__c>> pairs = new List<List<Transaction__c>>();
    Decimal previousCardSpend = 0;
    for (Integer m = 0; m < 4; m++) {
        Date monthStart = start.addMonths(m);
        Integer days = Date.daysInMonth(monthStart.year(), monthStart.month());
        Decimal cardSpend = 0;
        for (List<Object> p : plan) {
            Integer onlyMonth = (Integer) p[9];
            Date d = monthStart.addDays(Math.min((Integer) p[0], days) - 1);
            if ((onlyMonth != -1 && onlyMonth != m) || d > today) {
                continue;
            }
            Integer low = (Integer) p[2];
            Integer high = (Integer) p[3];
            seed = Math.mod(seed * 48271, 2147483647);
            Integer amount = high > low ? low + (Integer) Math.mod(seed, high - low + 1) : low;
            amount = high > low ? (amount / 10) * 10 : amount;
            String type = (String) p[1];
            String key = (String) p[4];
            rows.add(new Transaction__c(
                Family__c = fid, Account__c = acct.get(key).Id, Category__c = cat.get((String) p[5]), Type__c = type,
                Direction__c = type == 'Expense' ? 'Debit' : 'Credit', Amount__c = amount, Txn_Date__c = d,
                Payee__c = (String) p[6], Payment_Mode__c = (String) p[7], Member__c = (String) p[8] == 's' ? son.Id : admin.Id,
                Status__c = 'Cleared', Source__c = 'Manual'
            ));
            if (key == 'card') {
                cardSpend += type == 'Refund' ? -amount : amount;
            }
        }
        List<List<Object>> monthMoves = new List<List<Object>>(moves);
        if (m > 0 && previousCardSpend > 0) {
            monthMoves.add(new List<Object>{ 5, 'salary', 'card', previousCardSpend, 'Card bill', -1 });
        }
        for (List<Object> mv : monthMoves) {
            Date d = monthStart.addDays((Integer) mv[0] - 1);
            if (d > today) {
                continue;
            }
            Financial_Account__c fromAcct = acct.get((String) mv[1]);
            Financial_Account__c toAcct = acct.get((String) mv[2]);
            Boolean cardPay = toAcct.Type__c == 'Credit Card';
            String groupId = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
            Decimal amount = (Decimal) mv[3];
            Transaction__c outLeg = new Transaction__c(
                Family__c = fid, Account__c = fromAcct.Id, Type__c = cardPay ? 'Card Payment' : 'Transfer Out', Direction__c = 'Debit',
                Amount__c = amount, Txn_Date__c = d, Category__c = cat.get(cardPay ? 'CARD_PAYMENT' : 'TRANSFER'), Payee__c = toAcct.Name,
                Notes__c = (String) mv[4], Payment_Mode__c = 'NEFT/IMPS', Member__c = admin.Id, Transfer_Group_Id__c = groupId,
                Status__c = 'Cleared', Source__c = 'Manual'
            );
            Transaction__c inLeg = outLeg.clone(false, true);
            inLeg.Account__c = toAcct.Id;
            inLeg.Type__c = cardPay ? 'Card Payment' : 'Transfer In';
            inLeg.Direction__c = 'Credit';
            inLeg.Payee__c = fromAcct.Name;
            inLeg.Member__c = toAcct.Owner_Member__c;
            pairs.add(new List<Transaction__c>{ outLeg, inLeg });
            rows.add(outLeg);
            rows.add(inLeg);
        }
        previousCardSpend = cardSpend;
    }
    insert rows;
    List<Transaction__c> links = new List<Transaction__c>();
    for (List<Transaction__c> pair : pairs) {
        links.add(new Transaction__c(Id = pair[0].Id, Counter_Transaction__c = pair[1].Id));
        links.add(new Transaction__c(Id = pair[1].Id, Counter_Transaction__c = pair[0].Id));
    }
    update links;

    Map<String, Decimal> plannedByCategory = new Map<String, Decimal>{
        'Food and Dining' => 20000, 'Housing' => 36000, 'Utilities' => 5500, 'Transport' => 8000, 'Healthcare' => 3000,
        'Medicine' => 2000, 'Shopping' => 6000, 'Outing and Entertainment' => 4000, 'Subscriptions' => 1200,
        'Education' => 46000, 'Gifts and Donations' => 5000
    };
    for (Date month : new List<Date>{ today.toStartOfMonth().addMonths(-1), today.toStartOfMonth() }) {
        String monthKey = LedgerUtil.monthKey(month);
        Budget__c budget = new Budget__c(Name = 'Budget ' + monthKey, Family__c = fid, Month__c = month, Unique_Key__c = fid + '-' + monthKey);
        // Reuse a month that already has a (possibly empty) budget, replacing its lines.
        upsert budget Unique_Key__c;
        delete [SELECT Id FROM Budget_Line__c WHERE Budget__c = :budget.Id];
        List<Budget_Line__c> lines = new List<Budget_Line__c>();
        for (String name : plannedByCategory.keySet()) {
            lines.add(new Budget_Line__c(Budget__c = budget.Id, Family__c = fid, Category__c = cat.get(name), Planned__c = plannedByCategory.get(name)));
        }
        insert lines;
    }
    System.debug(LoggingLevel.ERROR, 'VKF_SEED demo finance: ' + acct.size() + ' accounts, ' + rows.size() + ' transactions');
}
