// Deterministic preview data for the Analytics and Money position pages (local browser checks only).
const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const today = new Date();
const monthStart = new Date(today.getFullYear(), today.getMonth(), 1);
const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0);
const key = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
const dayIn = (n: number) => iso(new Date(today.getFullYear(), today.getMonth(), n));

function series(months: number) {
  return Array.from({ length: months }, (_, i) => {
    const d = new Date(today.getFullYear(), today.getMonth() - (months - 1 - i), 1);
    const income = 145000 + (i % 3) * 4000;
    const emis = 42500;
    const spending = 38000 + ((i * 7919) % 17000);
    const bills = 7200 + ((i * 31) % 2400);
    const saved = income - emis - spending - bills;
    return {
      month: key(d),
      periodStart: iso(d),
      periodEnd: iso(new Date(d.getFullYear(), d.getMonth() + 1, 0)),
      income,
      spending,
      bills,
      emis,
      saved,
      savingsRate: Math.round((saved / income) * 1000) / 10,
    };
  });
}

const accounts = [
  { id: 'p1', name: 'SBI Salary', type: 'Savings', institution: 'SBI', last4: '4412', balance: 186400, isLiability: false, color: 'sky' },
  { id: 'p2', name: 'HDFC Current', type: 'Current', institution: 'HDFC Bank', last4: '0198', balance: 42800, isLiability: false, color: 'indigo' },
  { id: 'p3', name: 'Paytm wallet', type: 'UPI Wallet', balance: 3200, isLiability: false },
  { id: 'p4', name: 'Cash', type: 'Cash', balance: 6500, isLiability: false },
  { id: 'p5', name: 'SBI FD 7.1%', type: 'Fixed Deposit', institution: 'SBI', balance: 300000, isLiability: false },
  { id: 'p6', name: 'Mutual funds', type: 'Investment', balance: 245000, isLiability: false },
  { id: 'p7', name: 'HDFC Regalia', type: 'Credit Card', institution: 'HDFC Bank', last4: '4321', balance: 48200, creditLimit: 300000, isLiability: true, cardNetwork: 'Visa' },
  { id: 'p8', name: 'Axis Flipkart', type: 'Credit Card', institution: 'Axis Bank', last4: '7781', balance: 21900, creditLimit: 150000, isLiability: true, cardNetwork: 'Mastercard' },
];

const categories = [
  { categoryId: 'c1', name: 'Groceries', color: '#059669', icon: 'shopping-cart', amount: 14200 },
  { categoryId: 'c2', name: 'Dining out', color: '#ea580c', icon: 'utensils', amount: 7800 },
  { categoryId: 'c3', name: 'Fuel', color: '#2563eb', icon: 'fuel', amount: 5400 },
  { categoryId: 'c4', name: 'Shopping', color: '#c026d3', icon: 'shopping-bag', amount: 6900 },
  { categoryId: 'c5', name: 'Kids & school', color: '#7c3aed', icon: 'graduation-cap', amount: 4100 },
  { categoryId: 'c6', name: 'Health', color: '#e11d48', icon: 'heart-pulse', amount: 2600 },
  { categoryId: 'c7', name: 'Travel', color: '#0891b2', icon: 'plane', amount: 1900 },
  { categoryId: 'c8', name: 'Gifts', color: '#d97706', icon: 'gift', amount: 900 },
];

export function analyticsFixture(path: string, query: URLSearchParams): unknown {
  if (path === '/dashboard/analytics') {
    const s = series(Number(query.get('months') ?? 12));
    const days = [];
    for (let d = new Date(monthStart); d <= monthEnd; d.setDate(d.getDate() + 1)) {
      const n = d.getDate();
      days.push({ day: iso(d), amount: d > today ? 0 : n % 6 === 0 ? 0 : ((n * 2311) % 4200) + (n % 7 === 0 ? 6000 : 300) });
    }
    return {
      month: key(today), periodStart: iso(monthStart), periodEnd: iso(monthEnd), currencyCode: 'INR', members: [],
      series: s, current: s[s.length - 1], days,
      payees: [
        { name: 'BigBasket', amount: 9800, count: 6 }, { name: 'Swiggy', amount: 5200, count: 11 }, { name: 'Indian Oil', amount: 5400, count: 4 },
        { name: 'Amazon', amount: 4700, count: 3 }, { name: 'Apollo Pharmacy', amount: 2600, count: 2 }, { name: 'DMart', amount: 2400, count: 2 },
      ],
    };
  }
  if (path === '/dashboard') {
    const s = series(6);
    return {
      month: key(today), currencyCode: 'INR', wholeFamily: true, members: [],
      kpis: { income: 145000, expenses: 90000, net: 55000, savingsRate: 37.9, prevIncome: 141000, prevExpenses: 86000, essential: 52000, discretionary: 38000 },
      netWorth: { assets: 783900, liabilities: 70100 + 1342000, net: 783900 - 70100 - 1342000 },
      byCategory: categories, trend: s.map((f) => ({ month: f.month, income: f.income, expenses: f.spending + f.bills })),
      accounts, recent: [], upcoming: [],
    };
  }
  if (path.startsWith('/budgets/')) {
    return {
      month: key(today), exists: true, totalPlanned: 52000,
      lines: categories.slice(0, 6).map((c, i) => ({ categoryId: c.categoryId, name: c.name, icon: c.icon, color: c.color, planned: [15000, 6000, 6000, 8000, 5000, 4000][i], spent: c.amount })),
    };
  }
  if (path === '/dashboard/position') {
    const loan = (id: string, name: string, lender: string, principal: number, outstanding: number, emi: number, left: number, rate: number) => ({
      id, name, lender, loanType: 'Home', principal, annualRate: rate, rateType: 'Floating', tenureMonths: 180, firstEmiDate: dayIn(5), emi, outstanding,
      installmentsPaid: 180 - left, installmentsLeft: left, repaidPct: Math.round(((principal - outstanding) / principal) * 1000) / 10, interestRemaining: 640000,
      loanAccountId: id + 'a', autoDebit: true, status: 'Active', canPay: true, loanAccountNumberMasked: '•••• 2290',
    });
    return {
      month: key(today), periodStart: iso(monthStart), periodEnd: iso(monthEnd), asOf: iso(today), isCurrent: true, currencyCode: 'INR',
      summary: { liquid: 238900, cardAvailable: 379900, owed: 1412100, duesRemaining: 61400, leftAfterDues: 177500, moneyIn: 145000, moneyOut: 63000 },
      bank: {
        available: 238900, locked: 545000, moneyIn: 145000, moneyOut: 63000, lowestBalance: 3200,
        accounts: accounts.filter((a) => !a.isLiability).map((a, i) => ({ ...a, liquid: i < 4, moneyIn: i === 0 ? 145000 : 0, moneyOut: i === 0 ? 58000 : i === 1 ? 5000 : 0, maturityDate: i === 4 ? dayIn(28) : undefined, maturityAmount: i === 4 ? 321500 : undefined })),
      },
      cards: {
        totalLimit: 450000, used: 70100, available: 379900, utilisationPct: 15.6, spent: 31200, paid: 18500, dueNow: 24800, minimumDue: 1240, nextDueDate: dayIn(18), overdueCount: 0,
        cards: [
          { id: 'p7', name: 'HDFC Regalia', institution: 'HDFC Bank', last4: '4321', network: 'Visa', color: 'violet', creditLimit: 300000, used: 48200, available: 251800, utilisationPct: 16.1, spent: 21400, paid: 18500, statementAmount: 24800, minimumDue: 1240, amountPaid: 0, dueRemaining: 24800, dueDate: dayIn(18), lateFeeAfter: dayIn(21), statementStatus: 'Unpaid' },
          { id: 'p8', name: 'Axis Flipkart', institution: 'Axis Bank', last4: '7781', network: 'Mastercard', color: 'rose', creditLimit: 150000, used: 21900, available: 128100, utilisationPct: 14.6, spent: 9800, paid: 0, dueRemaining: 0, nextStatementDate: dayIn(25) },
        ],
      },
      bills: {
        due: 9100, paid: 6600, remaining: 2500, overdue: 0, count: 4, paidCount: 2, overdueCount: 0,
        items: [
          { id: 'i1', billId: 'b1', billName: 'Electricity (TSSPDCL)', categoryName: 'Electricity', icon: 'zap', color: '#d97706', dueDate: dayIn(6), amountDue: 3400, amountPaid: 3400, status: 'Paid', autoPay: false, daysLeft: -1, canPay: false },
          { id: 'i2', billId: 'b2', billName: 'Airtel Fiber', categoryName: 'Internet', icon: 'wifi', color: '#2563eb', dueDate: dayIn(8), amountDue: 1179, amountPaid: 0, status: 'Due', autoPay: false, daysLeft: 3, canPay: true },
          { id: 'i3', billId: 'b3', billName: 'Society maintenance', categoryName: 'Housing', icon: 'home', color: '#0f766e', dueDate: dayIn(10), amountDue: 3200, amountPaid: 3200, status: 'Paid', autoPay: true, daysLeft: 5, canPay: false },
          { id: 'i4', billId: 'b4', billName: 'Jio postpaid', categoryName: 'Mobile', icon: 'smartphone', color: '#e11d48', dueDate: dayIn(20), amountDue: 1321, amountPaid: 0, status: 'Upcoming', autoPay: false, daysLeft: 15, canPay: true },
        ],
      },
      loans: {
        borrowed: 2600000, outstanding: 1342000, repaid: 1258000, repaidPct: 48.4, monthlyEmi: 42500, emiDue: 42500, emiPaid: 8400, emiRemaining: 34100, interestRemaining: 640000, activeCount: 2, overdueCount: 0,
        loans: [
          { loan: loan('l1', 'Home loan', 'SBI', 2000000, 1180000, 34100, 98, 8.5), emiThisMonth: 34100, paidThisMonth: 0, dueThisMonth: dayIn(5), monthStatus: 'Due' },
          { loan: loan('l2', 'Car loan', 'HDFC Bank', 600000, 162000, 8400, 21, 9.2), emiThisMonth: 8400, paidThisMonth: 8400, dueThisMonth: dayIn(3), monthStatus: 'Paid' },
        ],
      },
    };
  }
  return undefined;
}
