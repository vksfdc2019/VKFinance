// Deterministic local browser fixtures. Production builds use the real Salesforce SDK.
const permissions = [
  'DASHBOARD:READ',
  'TRANSACTIONS:READ',
  'TRANSACTIONS:CREATE',
  'ACCOUNTS:READ',
  'BUDGETS:READ',
  'REPORTS:READ',
  'RECURRING:READ',
  'NOTIFICATIONS:READ',
  'ENHANCEMENTS:READ',
  'ENHANCEMENTS:EDIT',
  'IMPORTS:READ',
  'IMPORTS:CREATE',
  'RECEIPTS:READ',
  'RECEIPTS:CREATE',
  'RECEIPTS:DELETE',
  'REQUESTS:READ',
  'REQUESTS:APPROVE',
  'GOALS:READ',
  'GOALS:CREATE',
  'GOALS:EDIT',
  'GOALS:DELETE',
  'INSIGHTS:READ',
];
const enabled = [
  'IMPORTS',
  'RECEIPTS',
  'REQUESTS',
  'GOALS',
  'INSTALL',
  'INSIGHTS',
];
const profile = {
  userId: 'admin',
  firstName: 'Vamsee',
  lastName: 'Krishna',
  username: 'preview',
  role: 'Family Admin',
  status: 'Active',
  familyId: 'family',
  familyName: 'Krishna Family',
  familyCode: 'VK001',
  currencyCode: 'INR',
  mustChangePassword: false,
  mfaEnabled: false,
  sessionScope: 'FULL',
  idleTimeoutMinutes: 30,
  permissions,
};
const accounts = [
  {
    id: 'a1',
    name: 'Holiday savings',
    type: 'Savings',
    balance: 72000,
    ownerId: 'admin',
    ownerName: 'Vamsee',
    status: 'Active',
    canUse: true,
    canManage: true,
    isLiability: false,
    color: 'teal',
  },
  {
    id: 'a2',
    name: 'Emergency fund',
    type: 'Savings',
    balance: 145000,
    ownerId: 'admin',
    status: 'Active',
    canUse: true,
    canManage: true,
    isLiability: false,
    color: 'sky',
  },
];
const categories = [
  {
    id: 'c1',
    name: 'Groceries',
    kind: 'Expense',
    active: true,
    color: 'teal',
    icon: 'shopping-basket',
  },
  {
    id: 'c2',
    name: 'Salary',
    kind: 'Income',
    active: true,
    color: 'sky',
    icon: 'wallet',
  },
];
let goals = [
  {
    id: 'g1',
    title: 'A family holiday',
    target: 120000,
    progress: 72000,
    percent: 60,
    accountId: 'a1',
    accountName: 'Holiday savings',
    targetDate: '2027-05-01',
    color: 'teal',
    monthlyNeeded: 8000,
    canEdit: true,
  },
  {
    id: 'g2',
    title: 'A little peace of mind',
    target: 200000,
    progress: 145000,
    percent: 72.5,
    accountId: 'a2',
    accountName: 'Emergency fund',
    targetDate: '2027-04-01',
    color: 'sky',
    monthlyNeeded: 11000,
    canEdit: true,
  },
];
let requests = [
  {
    id: 'r1',
    title: 'New art supplies',
    amount: 850,
    childId: 'child',
    childName: 'Anaya',
    accountName: 'Pocket money',
    categoryName: 'Education',
    status: 'Pending',
    note: 'For the school art exhibition next week.',
    validUntil: '2099-11-05',
    expired: false,
    createdAt: '2026-10-28',
  },
];
let insights = [
  {
    key: 'PACE:sample',
    kind: 'Spending pace',
    title: 'Dining out is running ahead',
    explanation:
      'Spending is above the same-day pace implied by the previous three complete months. A planned one-off purchase can explain this.',
    actual: 8400,
    baseline: 5200,
    link: '/reports/category',
    severity: 'warning',
  },
  {
    key: 'REPEAT:sample',
    kind: 'Recurring review',
    title: 'Still using your streaming plan?',
    explanation:
      'This active recurring expense is a candidate for review. The app cannot determine whether you use the service; nothing is cancelled automatically.',
    actual: 799,
    link: '/recurring',
    severity: 'info',
  },
];
let batches: Record<string, unknown>[] = [];
let appearance: { personal?: unknown; family?: unknown; locked?: boolean } = {};
export async function createDataSDK() {
  return {
    fetch: async (url: string, options: RequestInit) => {
      const path = url.replace('/services/apexrest/vkf/v1', '').split('?')[0];
      const method = options.method;
      const body = options.body ? JSON.parse(String(options.body)) : {};
      let data: unknown;
      let status = 200;
      if (path === '/auth/session' || path === '/profile/me')
        data = { ...profile, appearance };
      else if (path === '/profile/appearance') {
        appearance = {
          ...appearance,
          personal: method === 'DELETE' ? undefined : body,
        };
        data = appearance;
      } else if (path === '/family/appearance') {
        appearance =
          method === 'DELETE'
            ? { ...appearance, family: undefined, locked: false }
            : { ...appearance, family: body, locked: body.locked === true };
        data = appearance;
      } else if (path === '/notifications') data = { items: [], unread: 0 };
      else if (path === '/accounts') data = accounts;
      else if (path === '/categories') data = categories;
      else if (path === '/enhancements/settings')
        data = {
          enabled: method === 'PATCH' ? body.enabled : enabled,
          available: enabled,
          canManage: true,
        };
      else if (path === '/enhancements/goals') {
        if (method === 'POST') {
          const goal = {
            ...goals[0],
            ...body,
            id: 'g' + Date.now(),
            progress: 0,
            percent: 0,
          };
          goals = [...goals, goal];
          data = goal;
          status = 201;
        } else data = goals;
      } else if (/\/enhancements\/goals\//.test(path)) {
        const id = path.split('/').pop();
        goals = goals.filter(g => g.id !== id);
        data = null;
        status = 204;
      } else if (path === '/enhancements/requests') data = requests;
      else if (/\/enhancements\/requests\//.test(path)) {
        requests = requests.map(r => ({
          ...r,
          status: path.endsWith('approve') ? 'Approved' : 'Declined',
        }));
        data = requests[0];
      } else if (path === '/enhancements/insights') data = insights;
      else if (path === '/enhancements/insights/dismiss') {
        insights = insights.filter(i => i.key !== body.key);
        status = 204;
      } else if (path === '/enhancements/imports') {
        if (method === 'POST') {
          const batch = {
            id: 'i1',
            fileName: body.fileName,
            accountId: body.accountId,
            status: 'Draft',
            total: body.rows.length,
            imported: 0,
            duplicates: 0,
            failed: 0,
            rows: [],
          };
          batches = [batch];
          data = batch;
          status = 201;
        } else data = batches;
      } else if (/\/enhancements\/imports\//.test(path)) {
        if (path.endsWith('/commit'))
          batches = batches.map(b => ({
            ...b,
            status: 'Completed',
            imported: b.total,
          }));
        data = batches[0];
      } else if (path === '/transactions')
        data = {
          items: [],
          totals: { income: 0, expenses: 0, transfers: 0, count: 0 },
        };
      else {
        status = 404;
        data = {
          code: 'NOT_FOUND',
          errors: ['Preview fixture not available.'],
        };
      }
      return new Response(status === 204 ? null : JSON.stringify(data), {
        status,
        headers: { 'Content-Type': 'application/json' },
      });
    },
  };
}
