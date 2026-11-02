import { analyticsFixture } from './analyticsFixtures';
import type { CreditGroup, CreditOverview } from '../src/api/creditTypes';
// Deterministic local browser fixtures. Production builds use the real Salesforce SDK.
const permissions = [
  'DASHBOARD:READ',
  'BILLS:READ',
  'LOANS:READ',
  'CATEGORIES:CREATE',
  'MEMBERS:CREATE',
  'TRANSACTIONS:READ',
  'TRANSACTIONS:CREATE',
  'ACCOUNTS:READ',
  'ACCOUNTS:EDIT',
  'ACCOUNTS:CREATE',
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
  {
    id: 'card',
    name: 'AXIS BANK NEO',
    type: 'Credit Card',
    institution: 'AXIS BANK',
    balance: 29613.72,
    creditLimit: 314000,
    ownerId: 'admin',
    status: 'Active',
    canUse: true,
    canManage: true,
    isLiability: true,
    color: 'orange',
    card: {
      lastStatementDate: '2026-10-16',
      nextStatementDate: '2026-11-16',
      dueDate: '2026-11-05',
      cycleSpend: 29613.72,
      available: 284386.28,
      utilisationPct: 9.43,
      statement: {
        amount: 0,
        amountPaid: 0,
        dueDate: '2026-11-05',
        status: 'Paid',
      },
      bill: {
        billId: 'bill',
        instanceId: 'bill-instance',
        amount: 16985.59,
        amountPaid: 0,
        dueDate: '2026-11-04',
        status: 'Due',
      },
    },
  },
];

const sharedCards = [
  { id: 'shared-one', name: 'Everyday card', balance: 30000, last4: '1234' },
  { id: 'shared-two', name: 'Travel card', balance: 20000, last4: '5678' },
];
let sharedGroup: CreditGroup | null = {
  id: 'shared-pool',
  name: 'Example Bank Duo',
  issuer: 'Example Bank',
  creditLimit: 300000,
  outstanding: 50000,
  available: 250000,
  utilisationPct: 16.7,
  overLimit: 0,
  activeCardCount: 2,
  version: 1,
  cardIds: sharedCards.map(c => c.id),
  cards: sharedCards.map(c => ({ ...c, status: 'Active' })),
};
function sharedFixture() {
  return sessionStorage.getItem('vkf.fixture.shared-credit') === '1';
}
function creditOverview(): CreditOverview {
  const group = sharedFixture() ? sharedGroup : null;
  if (!sharedFixture())
    return {
      canManage: true,
      groups: [],
      totals: {
        creditLimit: 314000,
        outstanding: 29613.72,
        available: 284386.28,
        facilities: 1,
        restrictedCards: 0,
        complete: true,
      },
    };
  const independentCards = sharedCards.filter(
    c => !group?.cardIds.includes(c.id)
  );
  return {
    canManage: true,
    groups: group ? [group] : [],
    totals: {
      creditLimit: (group?.creditLimit ?? 0) + independentCards.length * 50000,
      outstanding: 50000,
      available:
        (group?.available ?? 0) +
        independentCards.reduce((v, c) => v + 50000 - c.balance, 0),
      facilities: (group ? 1 : 0) + independentCards.length,
      restrictedCards: 0,
      complete: true,
    },
  };
}
function creditAccounts() {
  return [
    ...accounts.filter(a => a.type !== 'Credit Card'),
    ...sharedCards.map((c, index) => {
      const g = sharedGroup?.cardIds.includes(c.id) ? sharedGroup : undefined;
      return {
        ...c,
        type: 'Credit Card',
        institution: 'Example Bank',
        status: 'Active',
        ownerId: 'admin',
        canUse: true,
        canManage: true,
        isLiability: true,
        color: index === 0 ? 'teal' : 'violet',
        isShared: false,
        creditLimit: g?.creditLimit ?? 50000,
        independentCreditLimit: 50000,
        creditLimitGroupId: g?.id,
        sharedCredit: g,
        sharedCreditRestricted: false,
        card: {
          lastStatementDate: '2026-10-16',
          nextStatementDate: '2026-11-16',
          dueDate: '2026-11-04',
          cycleSpend: c.balance,
          available: g?.available ?? 50000 - c.balance,
          utilisationPct: g?.utilisationPct ?? (c.balance / 50000) * 100,
          bill: {
            billId: 'sample-bill-' + index,
            instanceId: 'sample-instance-' + index,
            amount: index === 0 ? 18000 : 6500,
            amountPaid: 0,
            dueDate: '2026-11-04',
            status: 'Due',
          },
        },
      };
    }),
  ];
}

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
      else if (path === '/accounts')
        data = sharedFixture() ? creditAccounts() : accounts;
      else if (
        path === '/accounts/credit-groups' ||
        path.startsWith('/accounts/credit-groups/')
      ) {
        if (method !== 'GET' && sharedFixture()) {
          if (sharedGroup && body.expectedVersion !== sharedGroup.version) {
            status = 409;
            data = {
              code: 'CONFLICT',
              errors: ['This group changed since you opened it.'],
            };
          } else if (path.endsWith('/archive')) sharedGroup = null;
          else if (sharedGroup) {
            const chosen = sharedCards.filter(c => body.cardIds.includes(c.id));
            const owed = chosen.reduce((v, c) => v + c.balance, 0);
            sharedGroup = {
              ...sharedGroup,
              ...body,
              version: sharedGroup.version + 1,
              outstanding: owed,
              available: Math.max(0, body.creditLimit - owed),
              overLimit: Math.max(0, owed - body.creditLimit),
              utilisationPct: (owed / body.creditLimit) * 100,
              activeCardCount: chosen.length,
              cards: chosen.map(c => ({ ...c, status: 'Active' })),
            };
          }
        }
        data ??= creditOverview();
      } else if (path === '/categories') data = categories;
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
      else if (analyticsFixture(path, new URLSearchParams(url.split('?')[1] ?? '')) !== undefined)
        data = analyticsFixture(path, new URLSearchParams(url.split('?')[1] ?? ''));
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
