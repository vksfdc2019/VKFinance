import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import RequestsPage from './RequestsPage';
import { enhancementsApi } from '@/api/enhancements';

vi.mock('@/api/enhancements', () => ({
  enhancementsApi: { requests: vi.fn(), act: vi.fn() },
}));
vi.mock('./EnhancementsLayout', () => ({
  FeatureGate: ({ children }: { children: React.ReactNode }) => children,
}));
vi.mock('@/features/auth/AuthContext', () => ({
  useAuth: () => ({
    profile: { userId: 'parent', role: 'Family Admin' },
    can: (p: string) => p === 'REQUESTS:APPROVE',
  }),
}));
const refresh = vi.fn();
vi.mock('@/features/ledger/LedgerContext', () => ({
  useLedger: () => ({ version: 0, refresh, currency: 'INR' }),
}));

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(enhancementsApi.requests).mockResolvedValue([
    {
      id: 'r1',
      title: 'School supplies',
      amount: 250,
      childId: 'child',
      childName: 'Sam',
      accountName: 'Pocket money',
      categoryName: 'Education',
      status: 'Pending',
      validUntil: '2099-10-28',
      expired: false,
      createdAt: '2026-10-28',
    },
  ]);
});

describe('spend request confirmation', () => {
  it('requires an explicit confirmation and sends only an approval before recording any purchase', async () => {
    render(<RequestsPage />);
    fireEvent.click(await screen.findByRole('button', { name: 'Approve' }));
    expect(enhancementsApi.act).not.toHaveBeenCalled();
    expect(
      screen.getByText(/does not change account balances/i)
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Confirm' }));
    await waitFor(() =>
      expect(enhancementsApi.act).toHaveBeenCalledWith(
        'r1',
        'approve',
        undefined
      )
    );
    expect(enhancementsApi.act).toHaveBeenCalledTimes(1);
  });
});
