import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { SharedCreditPanel } from './SharedCreditPanel';
import { AccountCard } from './AccountCard';
import { financeApi } from '@/api/endpoints';
import { ApiError } from '@/api/vkfClient';
import type { CreditGroup, CreditOverview } from '@/api/creditTypes';
import type { Account } from '@/api/financeTypes';
vi.mock('@/api/endpoints', () => ({
  financeApi: {
    creditGroups: vi.fn(),
    accounts: vi.fn(),
    createCreditGroup: vi.fn(),
    updateCreditGroup: vi.fn(),
    archiveCreditGroup: vi.fn(),
  },
}));
afterEach(cleanup);
const changed = vi.fn();
const group: CreditGroup = {
  id: 'pool',
  name: 'Example Bank Duo',
  issuer: 'Example Bank',
  creditLimit: 300000,
  outstanding: 50000,
  available: 250000,
  utilisationPct: 16.7,
  overLimit: 0,
  activeCardCount: 2,
  version: 1,
  cardIds: ['one', 'two'],
  cards: [
    { id: 'one', name: 'Everyday card', balance: 30000, status: 'Active' },
    { id: 'two', name: 'Travel card', balance: 20000, status: 'Active' },
  ],
};
const overview: CreditOverview = {
  canManage: true,
  groups: [group],
  totals: {
    creditLimit: 300000,
    outstanding: 50000,
    available: 250000,
    facilities: 1,
    restrictedCards: 0,
    complete: true,
  },
};
const independent: CreditOverview = {
  canManage: true,
  groups: [],
  totals: {
    creditLimit: 100000,
    outstanding: 50000,
    available: 50000,
    facilities: 2,
    restrictedCards: 0,
    complete: true,
  },
};
const cards: Account[] = group.cards.map(card => ({
  ...card,
  type: 'Credit Card',
  isLiability: true,
  isShared: false,
  creditLimit: 50000,
  independentCreditLimit: 50000,
  canManage: true,
  canUse: true,
}));
beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(financeApi.creditGroups).mockResolvedValue(overview);
  vi.mocked(financeApi.accounts).mockResolvedValue(cards);
  vi.mocked(financeApi.createCreditGroup).mockResolvedValue(overview);
  vi.mocked(financeApi.updateCreditGroup).mockResolvedValue(overview);
  vi.mocked(financeApi.archiveCreditGroup).mockResolvedValue(independent);
});
describe('shared credit facilities', () => {
  it('shows a shared facility once and each card contribution', async () => {
    render(
      <SharedCreditPanel currency="INR" version={0} onChanged={changed} />
    );
    const tile = await screen.findByRole('article', {
      name: 'Example Bank Duo shared facility',
    });
    expect(within(tile).getByText('₹2,50,000')).toBeInTheDocument();
    expect(screen.getByText(/1 credit facility/)).toBeInTheDocument();
    expect(within(tile).getByText('Everyday card')).toBeInTheDocument();
    expect(within(tile).getByText('Travel card')).toBeInTheDocument();
    expect(screen.queryByText('₹6,00,000')).not.toBeInTheDocument();
  });
  it('previews and saves explicit membership only after confirmation', async () => {
    vi.mocked(financeApi.creditGroups).mockResolvedValue(independent);
    render(
      <SharedCreditPanel currency="INR" version={0} onChanged={changed} />
    );
    fireEvent.click(
      await screen.findByRole('button', { name: 'Create shared limit' })
    );
    fireEvent.change(screen.getByLabelText('Group name'), {
      target: { value: 'New facility' },
    });
    fireEvent.change(screen.getByLabelText('Bank / issuer'), {
      target: { value: 'Example Bank' },
    });
    fireEvent.change(screen.getByLabelText('Shared credit limit'), {
      target: { value: '3,00,000' },
    });
    fireEvent.click(await screen.findByLabelText('Include Everyday card'));
    fireEvent.click(screen.getByLabelText('Include Travel card'));
    expect(
      within(screen.getByRole('dialog')).getByText('₹2,50,000')
    ).toBeInTheDocument();
    expect(financeApi.createCreditGroup).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Save shared limit' }));
    await waitFor(() =>
      expect(financeApi.createCreditGroup).toHaveBeenCalledWith(
        expect.objectContaining({
          name: 'New facility',
          issuer: 'Example Bank',
          creditLimit: 300000,
          cardIds: ['one', 'two'],
        })
      )
    );
    await waitFor(() => expect(changed).toHaveBeenCalledTimes(1));
  });
  it('keeps stale edits open and offers an explicit refresh', async () => {
    vi.mocked(financeApi.updateCreditGroup).mockRejectedValue(
      new ApiError(409, 'CONFLICT', ['This group changed since you opened it.'])
    );
    render(
      <SharedCreditPanel currency="INR" version={0} onChanged={changed} />
    );
    fireEvent.click(
      await screen.findByRole('button', { name: 'Edit Example Bank Duo' })
    );
    await screen.findByLabelText('Include Everyday card');
    fireEvent.change(screen.getByLabelText('Shared credit limit'), {
      target: { value: '400000' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Save shared limit' }));
    expect(
      await screen.findByText('This group changed since you opened it.')
    ).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: 'Refresh groups and review' })
    ).toBeVisible();
    expect(changed).not.toHaveBeenCalled();
  });
  it('requires separate confirmation before archiving', async () => {
    render(
      <SharedCreditPanel currency="INR" version={0} onChanged={changed} />
    );
    fireEvent.click(
      await screen.findByRole('button', { name: 'Edit Example Bank Duo' })
    );
    fireEvent.click(screen.getByRole('button', { name: 'Archive group' }));
    expect(financeApi.archiveCreditGroup).not.toHaveBeenCalled();
    expect(
      screen.getByText(/Balances, bills and payment history stay intact/)
    ).toBeInTheDocument();
    fireEvent.click(
      screen.getByRole('button', { name: 'Archive and unlink cards' })
    );
    await waitFor(() =>
      expect(financeApi.archiveCreditGroup).toHaveBeenCalledWith('pool', 1)
    );
  });
  it('withholds private totals and does not fall back to independent availability', async () => {
    vi.mocked(financeApi.creditGroups).mockResolvedValue({
      canManage: false,
      groups: [],
      totals: {
        outstanding: 30000,
        facilities: 0,
        restrictedCards: 1,
        complete: false,
      },
    });
    render(
      <SharedCreditPanel currency="INR" version={0} onChanged={changed} />
    );
    expect(await screen.findAllByText('Restricted')).toHaveLength(2);
    expect(screen.queryByText('Example Bank Duo')).not.toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: 'Create shared limit' })
    ).not.toBeInTheDocument();
    render(
      <AccountCard
        account={{
          ...cards[0],
          creditLimitGroupId: 'pool',
          sharedCreditRestricted: true,
          card: { available: 123456, utilisationPct: 55 },
        }}
        currency="INR"
      />
    );
    expect(screen.queryByText('₹1,23,456')).not.toBeInTheDocument();
    expect(screen.queryByText(/55%/)).not.toBeInTheDocument();
  });
  it('uses shared availability while retaining individual outstanding', () => {
    render(
      <AccountCard
        account={{
          ...cards[0],
          creditLimitGroupId: 'pool',
          sharedCredit: group,
          card: { available: 20000, utilisationPct: 60 },
        }}
        currency="INR"
      />
    );
    for (const value of ['₹2,50,000', '₹3,00,000', '₹30,000'])
      expect(screen.getByText(value)).toBeInTheDocument();
    expect(screen.queryByText('₹20,000')).not.toBeInTheDocument();
    expect(screen.getByText(/of shared limit used/)).toBeInTheDocument();
  });
});
