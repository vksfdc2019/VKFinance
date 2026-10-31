import { render, screen, cleanup } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { AccountCard } from './AccountCard';
import type { Account } from '@/api/financeTypes';

afterEach(cleanup);
const account: Account = {
  id: 'card',
  name: 'AXIS BANK NEO',
  type: 'Credit Card',
  balance: 29613.72,
  isLiability: true,
  creditLimit: 314000,
  status: 'Active',
  isShared: false,
  canManage: true,
  canUse: true,
  card: {
    lastStatementDate: '2026-10-16',
    nextStatementDate: '2026-11-16',
    dueDate: '2026-11-05',
    cycleSpend: 29613.72,
    available: 284386.28,
    statement: {
      id: 's',
      accountId: 'card',
      cycleStart: '2026-09-17',
      cycleEnd: '2026-10-16',
      amount: 0,
      amountPaid: 0,
      minimumDue: 0,
      dueDate: '2026-11-05',
      status: 'Paid',
    },
    bill: {
      billId: 'b',
      instanceId: 'i',
      amount: 16985.59,
      amountPaid: 0,
      dueDate: '2026-11-04',
      status: 'Due',
    },
  },
};

describe('credit card bill summary', () => {
  it('shows all five details from the linked bill rather than the zero statement', () => {
    render(<AccountCard account={account} currency="INR" />);
    for (const label of [
      'Total outstanding',
      'Available amount',
      'Bill amount',
      'Total credit limit',
      'Bill due date',
    ]) {
      expect(screen.getByText(label)).toBeInTheDocument();
    }
    for (const value of [
      '₹29,613.72',
      '₹2,84,386.28',
      '₹16,985.59',
      '₹3,14,000',
      '4 Nov',
    ]) {
      expect(screen.getByText(value)).toBeInTheDocument();
    }
    expect(screen.queryByText(/Nothing to pay/)).not.toBeInTheDocument();
  });
  it('shows paid even when newer spending leaves a card balance', () => {
    render(
      <AccountCard
        account={{
          ...account,
          card: {
            ...account.card!,
            bill: {
              ...account.card!.bill!,
              amountPaid: 16985.59,
              status: 'Paid',
            },
          },
        }}
        currency="INR"
      />
    );
    expect(screen.getByText(/Bill paid/)).toBeInTheDocument();
    expect(screen.getByText('₹29,613.72')).toBeInTheDocument();
  });
  it('shows the remaining amount for partial payments', () => {
    render(
      <AccountCard
        account={{
          ...account,
          card: {
            ...account.card!,
            bill: {
              ...account.card!.bill!,
              amountPaid: 1000,
              status: 'Partially Paid',
            },
          },
        }}
        currency="INR"
      />
    );
    expect(screen.getByText(/₹15,985.59 left/)).toBeInTheDocument();
  });
  it('does not present missing bill or credit limit data as zero', () => {
    render(
      <AccountCard
        account={{
          ...account,
          creditLimit: undefined,
          card: {
            ...account.card!,
            bill: undefined,
            statement: undefined,
            available: undefined,
          },
        }}
        currency="INR"
      />
    );
    expect(screen.getByText('No bill recorded')).toBeInTheDocument();
    expect(screen.queryByText('₹0')).not.toBeInTheDocument();
    expect(screen.getByText('Total credit limit')).toBeInTheDocument();
  });
  it('retains the computed statement when there is no linked bill', () => {
    render(
      <AccountCard
        account={{ ...account, card: { ...account.card!, bill: undefined } }}
        currency="INR"
      />
    );
    expect(screen.getByText(/Nothing to pay/)).toBeInTheDocument();
    expect(screen.getByText('5 Nov')).toBeInTheDocument();
  });
});
