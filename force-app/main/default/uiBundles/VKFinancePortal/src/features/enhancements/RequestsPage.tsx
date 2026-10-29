import { useState, type FormEvent } from 'react';
import { Check, CheckCheck, Clock3, Plus, UsersRound, X } from 'lucide-react';
import { enhancementsApi, type SpendRequest } from '@/api/enhancements';
import { financeApi } from '@/api/endpoints';
import { errorMessages } from '@/api/vkfClient';
import { useAuth } from '@/features/auth/AuthContext';
import { useLedger } from '@/features/ledger/LedgerContext';
import { useAsync } from '@/lib/useAsync';
import { formatMoney, formatDate, todayIso } from '@/lib/format';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Skeleton } from '@/components/ui/skeleton';
import { Badge } from '@/components/ui/badge';
import { FormErrors } from '@/components/forms';
import { Panel, EmptyState, SegmentedControl } from '@/components/finance/ui';
import { FeatureGate } from './EnhancementsLayout';
import { Intro, NativeSelect } from './shared';

export default function RequestsPage() {
  return (
    <FeatureGate feature="REQUESTS">
      <Requests />
    </FeatureGate>
  );
}
function Requests() {
  const { version, refresh, currency } = useLedger();
  const { can, profile } = useAuth();
  const { data, errors, loading } = useAsync(
    () => enhancementsApi.requests(),
    [version]
  );
  const [creating, setCreating] = useState(false);
  const [filter, setFilter] = useState<'active' | 'all'>('active');
  const [action, setAction] = useState<{
    request: SpendRequest;
    kind: 'approve' | 'decline' | 'cancel' | 'record';
  } | null>(null);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [actionErrors, setActionErrors] = useState<string[]>([]);
  const items = data?.filter(
    r =>
      filter === 'all' ||
      (!r.expired && ['Pending', 'Approved'].includes(r.status))
  );
  const pending =
    data?.filter(r => r.status === 'Pending' && !r.expired).length ?? 0;
  async function act() {
    if (!action) return;
    setBusy(true);
    try {
      await enhancementsApi.act(
        action.request.id,
        action.kind,
        note || undefined
      );
      setAction(null);
      refresh();
    } catch (e) {
      setActionErrors(errorMessages(e));
    } finally {
      setBusy(false);
    }
  }
  const choose = (
    request: SpendRequest,
    kind: NonNullable<typeof action>['kind']
  ) => {
    setNote('');
    setActionErrors([]);
    setAction({ request, kind });
  };
  return (
    <>
      <Intro
        eyebrow="Growing independence, together"
        title="A conversation before a purchase"
        description="Children ask, parents decide, and everyone can follow what happened. Approval never moves money; recording the actual purchase is a separate step."
      >
        {can('REQUESTS:CREATE') && (
          <Button onClick={() => setCreating(true)}>
            <Plus />
            Ask to spend
          </Button>
        )}
      </Intro>
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-slate-500 dark:text-slate-400">
          <span className="font-semibold text-slate-900 dark:text-slate-100">{pending}</span>{' '}
          waiting for a decision
        </p>
        <SegmentedControl
          label="Request status"
          value={filter}
          onChange={v => setFilter(v as typeof filter)}
          options={[
            { value: 'active', label: 'Active' },
            { value: 'all', label: 'History' },
          ]}
        />
      </div>
      <FormErrors errors={errors} />
      {!data && loading ? (
        <Skeleton className="h-64 rounded-2xl" />
      ) : items?.length === 0 ? (
        <Panel>
          <EmptyState icon={<UsersRound />} title="All caught up">
            New requests and decisions will appear here.
          </EmptyState>
        </Panel>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {items?.map(r => (
            <article
              key={r.id}
              className="rounded-2xl bg-white dark:bg-slate-900 p-5 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="mb-3 flex items-center gap-2">
                    <span className="rounded-lg bg-amber-50 dark:bg-amber-950/40 p-2 text-amber-700 dark:text-amber-300">
                      {r.status === 'Recorded' ? (
                        <CheckCheck className="size-4" />
                      ) : (
                        <Clock3 className="size-4" />
                      )}
                    </span>
                    <Badge variant="outline">
                      {r.expired && ['Approved', 'Pending'].includes(r.status)
                        ? 'Expired'
                        : r.status}
                    </Badge>
                  </div>
                  <h2 className="text-lg font-semibold">{r.title}</h2>
                  <p className="mt-1 text-xs text-slate-500 dark:text-slate-400">
                    {r.childName} · {r.accountName} · {r.categoryName}
                  </p>
                </div>
                <p className="text-xl font-semibold tabular-nums">
                  {formatMoney(r.amount, currency)}
                </p>
              </div>
              {r.note && (
                <p className="mt-4 rounded-xl bg-slate-50 dark:bg-slate-800/40 p-3 text-sm text-slate-600 dark:text-slate-400">
                  {r.note}
                </p>
              )}
              {r.decisionNote && (
                <p className="mt-3 text-sm text-brand-800 dark:text-brand-200">
                  Parent’s note: {r.decisionNote}
                </p>
              )}
              <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-slate-100 dark:border-slate-800 pt-4">
                <span className="text-xs text-slate-400">
                  Valid through {formatDate(r.validUntil)}
                </span>
                <div className="flex flex-wrap gap-2">
                  {!r.expired &&
                    r.status === 'Pending' &&
                    can('REQUESTS:APPROVE') && (
                      <>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => choose(r, 'decline')}
                        >
                          <X />
                          Decline
                        </Button>
                        <Button size="sm" onClick={() => choose(r, 'approve')}>
                          <Check />
                          Approve
                        </Button>
                      </>
                    )}
                  {!r.expired && r.status === 'Approved' && (
                    <Button size="sm" onClick={() => choose(r, 'record')}>
                      Record purchase
                    </Button>
                  )}
                  {['Pending', 'Approved'].includes(r.status) &&
                    r.childId === profile?.userId &&
                    can('REQUESTS:CANCEL') && (
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => choose(r, 'cancel')}
                      >
                        Cancel
                      </Button>
                    )}
                </div>
              </div>
            </article>
          ))}
        </div>
      )}
      {creating && (
        <RequestDialog
          onClose={() => setCreating(false)}
          onSaved={() => {
            setCreating(false);
            refresh();
          }}
        />
      )}
      <Dialog
        open={!!action}
        onOpenChange={v => {
          if (!v && !busy) setAction(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {action?.kind === 'record'
                ? 'Record the actual purchase?'
                : `${action?.kind === 'approve' ? 'Approve' : action?.kind === 'decline' ? 'Decline' : 'Cancel'} this request?`}
            </DialogTitle>
            <DialogDescription>
              {action?.kind === 'record'
                ? `This posts ${formatMoney(action.request.amount, currency)} as an expense from ${action.request.accountName}. Continue only when the purchase has happened.`
                : 'The decision is saved in the request history. This action does not change account balances.'}
            </DialogDescription>
          </DialogHeader>
          <FormErrors errors={actionErrors} />
          {['approve', 'decline'].includes(action?.kind ?? '') && (
            <label className="grid gap-1.5 text-sm">
              A note for your child (optional)
              <Input
                value={note}
                maxLength={255}
                onChange={e => setNote(e.target.value)}
              />
            </label>
          )}
          <DialogFooter>
            <Button
              variant="outline"
              disabled={busy}
              onClick={() => setAction(null)}
            >
              Go back
            </Button>
            <Button disabled={busy} onClick={() => void act()}>
              {busy ? 'Saving…' : 'Confirm'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function RequestDialog({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const { profile } = useAuth();
  const { data, errors: loadErrors } = useAsync(
    () => Promise.all([financeApi.accounts(), financeApi.categories()]),
    []
  );
  const [title, setTitle] = useState('');
  const [amount, setAmount] = useState('');
  const [accountId, setAccountId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [note, setNote] = useState('');
  const [validUntil, setValidUntil] = useState('');
  const [busy, setBusy] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await enhancementsApi.request({
        title,
        amount: Number(amount),
        accountId,
        categoryId,
        note: note || undefined,
        validUntil: validUntil || undefined,
      });
      onSaved();
    } catch (error) {
      setErrors(errorMessages(error));
    } finally {
      setBusy(false);
    }
  }
  return (
    <Dialog
      open
      onOpenChange={v => {
        if (!v && !busy) onClose();
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>What would you like to buy?</DialogTitle>
          <DialogDescription>
            Tell your parent what it is for. No expense is recorded until an
            approved purchase actually happens.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-4">
          <FormErrors errors={[...loadErrors, ...errors]} />
          <label className="grid gap-1.5 text-sm">
            What is it for?
            <Input
              required
              maxLength={120}
              value={title}
              onChange={e => setTitle(e.target.value)}
              placeholder="School supplies"
            />
          </label>
          <label className="grid gap-1.5 text-sm">
            Amount
            <Input
              required
              type="number"
              min="0.01"
              step="0.01"
              value={amount}
              onChange={e => setAmount(e.target.value)}
            />
          </label>
          <label className="grid gap-1.5 text-sm">
            Your account
            <NativeSelect
              required
              value={accountId}
              onChange={e => setAccountId(e.target.value)}
            >
              <option value="">Choose your account</option>
              {data?.[0]
                .filter(
                  a =>
                    a.ownerId === profile?.userId && a.canUse && !a.isLiability
                )
                .map(a => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
            </NativeSelect>
          </label>
          <label className="grid gap-1.5 text-sm">
            Category
            <NativeSelect
              required
              value={categoryId}
              onChange={e => setCategoryId(e.target.value)}
            >
              <option value="">Choose a category</option>
              {data?.[1]
                .filter(c => c.active && c.kind === 'Expense')
                .map(c => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
            </NativeSelect>
          </label>
          <label className="grid gap-1.5 text-sm">
            A little more detail (optional)
            <Input
              maxLength={255}
              value={note}
              onChange={e => setNote(e.target.value)}
            />
          </label>
          <label className="grid gap-1.5 text-sm">
            Valid until (defaults to seven days)
            <Input
              type="date"
              min={todayIso()}
              value={validUntil}
              onChange={e => setValidUntil(e.target.value)}
            />
          </label>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={onClose}
              disabled={busy}
            >
              Cancel
            </Button>
            <Button disabled={busy} type="submit">
              {busy ? 'Sending…' : 'Send request'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
