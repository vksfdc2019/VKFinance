import { useState, type FormEvent } from 'react';
import { Archive, Check, Plus, Sprout, TrendingUp } from 'lucide-react';
import { enhancementsApi, type Goal } from '@/api/enhancements';
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
import { FormErrors } from '@/components/forms';
import { Panel, EmptyState } from '@/components/finance/ui';
import { FeatureGate } from './EnhancementsLayout';
import { Intro, NativeSelect } from './shared';

export default function GoalsPage() {
  return (
    <FeatureGate feature="GOALS">
      <Goals />
    </FeatureGate>
  );
}
function Goals() {
  const { version, refresh, currency } = useLedger();
  const { can } = useAuth();
  const { data, errors, loading } = useAsync(
    () => enhancementsApi.goals(),
    [version]
  );
  const [editing, setEditing] = useState<Goal | 'new' | null>(null);
  const [archiving, setArchiving] = useState<Goal | null>(null);
  const [busy, setBusy] = useState(false);
  const [actionErrors, setActionErrors] = useState<string[]>([]);
  async function archive() {
    if (!archiving) return;
    setBusy(true);
    try {
      await enhancementsApi.archiveGoal(archiving.id);
      setArchiving(null);
      refresh();
    } catch (e) {
      setActionErrors(errorMessages(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Intro
        eyebrow="A little closer, every day"
        title="Give your savings a purpose"
        description="Each goal follows a dedicated account’s balance. Add money through your normal ledger and your progress updates automatically."
      >
        {can('GOALS:CREATE') && (
          <Button onClick={() => setEditing('new')}>
            <Plus />
            Create a goal
          </Button>
        )}
      </Intro>
      <FormErrors errors={errors} />
      {!data && loading ? (
        <Skeleton className="h-72 rounded-3xl" />
      ) : data?.length === 0 ? (
        <Panel>
          <EmptyState icon={<Sprout />} title="Every dream starts somewhere">
            Choose an account, set a target, and watch your first goal take
            shape.
          </EmptyState>
        </Panel>
      ) : (
        <div className="grid gap-5 md:grid-cols-2">
          {data?.map(goal => (
            <article
              key={goal.id}
              className="relative overflow-hidden rounded-3xl bg-white dark:bg-slate-900 p-6 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10"
            >
              <div className="absolute right-0 top-0 size-32 rounded-bl-full bg-gradient-to-bl from-brand-50 dark:from-brand-950/40 to-white dark:to-slate-900" />
              <div className="relative flex items-start justify-between gap-4">
                <div>
                  <span className="inline-flex rounded-xl bg-brand-50 dark:bg-brand-950/40 p-3 text-brand-700 dark:text-brand-300">
                    <Sprout className="size-6" />
                  </span>
                  <h2 className="mt-4 text-xl font-semibold text-slate-900 dark:text-slate-100">
                    {goal.title}
                  </h2>
                  <p className="mt-1 text-xs text-slate-500 dark:text-slate-400">
                    {goal.accountName}
                    {goal.targetDate ? ` · ${formatDate(goal.targetDate)}` : ''}
                  </p>
                </div>
                <div className="relative size-20 shrink-0">
                  <svg
                    viewBox="0 0 80 80"
                    className="size-20 -rotate-90"
                    aria-hidden
                  >
                    <circle
                      cx="40"
                      cy="40"
                      r="34"
                      fill="none"
                      className="stroke-slate-100 dark:stroke-slate-800"
                      strokeWidth="6"
                    />
                    <circle
                      cx="40"
                      cy="40"
                      r="34"
                      fill="none"
                      className="stroke-brand-700 dark:stroke-brand-400"
                      strokeWidth="6"
                      strokeLinecap="round"
                      strokeDasharray={`${(213.63 * goal.percent) / 100} 213.63`}
                    />
                  </svg>
                  <span className="absolute inset-0 flex items-center justify-center text-sm font-bold text-brand-900 dark:text-brand-100">
                    {goal.percent >= 100 ? (
                      <Check className="size-6" />
                    ) : (
                      `${Math.round(goal.percent)}%`
                    )}
                  </span>
                </div>
              </div>
              <p className="mt-7 text-3xl font-semibold tracking-tight text-slate-900 dark:text-slate-100">
                {formatMoney(goal.progress, currency)}
              </p>
              <p className="mt-1 text-sm text-slate-500 dark:text-slate-400">
                of {formatMoney(goal.target, currency)} saved
              </p>
              <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 dark:border-slate-800 pt-4">
                <p className="flex items-center gap-1.5 text-xs text-slate-500 dark:text-slate-400">
                  <TrendingUp className="size-3.5 text-brand-600 dark:text-brand-400" />
                  {goal.percent >= 100
                    ? 'You reached your target!'
                    : goal.monthlyNeeded != null
                      ? `${formatMoney(goal.monthlyNeeded, currency)} / month to your target`
                      : 'Progress follows your account balance'}
                </p>
                {goal.canEdit && (
                  <div className="flex gap-1">
                    <Button
                      size="xs"
                      variant="ghost"
                      onClick={() => setEditing(goal)}
                    >
                      Edit
                    </Button>
                    <Button
                      size="xs"
                      variant="ghost"
                      aria-label={`Archive ${goal.title}`}
                      onClick={() => {
                        setActionErrors([]);
                        setArchiving(goal);
                      }}
                    >
                      <Archive className="size-3.5" />
                    </Button>
                  </div>
                )}
              </div>
            </article>
          ))}
        </div>
      )}
      <p className="mt-5 text-xs leading-relaxed text-slate-400">
        One active goal per account prevents double counting. Spending or moving
        money out of that account reduces your progress. A goal does not reserve
        or transfer funds.
      </p>
      {editing && (
        <GoalDialog
          goal={editing === 'new' ? undefined : editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            refresh();
          }}
        />
      )}
      <Dialog
        open={!!archiving}
        onOpenChange={v => {
          if (!v && !busy) setArchiving(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Archive {archiving?.title}?</DialogTitle>
            <DialogDescription>
              Your account and money stay as they are. This frees the account
              for a future goal.
            </DialogDescription>
          </DialogHeader>
          <FormErrors errors={actionErrors} />
          <DialogFooter>
            <Button
              variant="outline"
              disabled={busy}
              onClick={() => setArchiving(null)}
            >
              Keep goal
            </Button>
            <Button disabled={busy} onClick={() => void archive()}>
              Archive goal
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function GoalDialog({
  goal,
  onClose,
  onSaved,
}: {
  goal?: Goal;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { profile } = useAuth();
  const { currency } = useLedger();
  const { data: accounts, errors: accountErrors } = useAsync(
    () => financeApi.accounts(),
    []
  );
  const [title, setTitle] = useState(goal?.title ?? '');
  const [target, setTarget] = useState(String(goal?.target ?? ''));
  const [accountId, setAccountId] = useState(goal?.accountId ?? '');
  const [targetDate, setTargetDate] = useState(goal?.targetDate ?? '');
  const [includeExisting, setIncludeExisting] = useState(true);
  const [busy, setBusy] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const admin =
    profile?.role === 'Family Admin' || profile?.role === 'Co-Admin';
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await enhancementsApi.saveGoal(
        {
          title,
          target: Number(target),
          accountId,
          targetDate: targetDate || undefined,
          includeExisting,
        },
        goal?.id
      );
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
          <DialogTitle>
            {goal ? 'Refine your goal' : 'What are you saving for?'}
          </DialogTitle>
          <DialogDescription>
            Choose one account dedicated to this goal. Its ledger balance does
            the tracking.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-4">
          <FormErrors errors={[...accountErrors, ...errors]} />
          <label className="grid gap-1.5 text-sm font-medium">
            Goal name
            <Input
              value={title}
              maxLength={80}
              required
              placeholder="A family holiday"
              onChange={e => setTitle(e.target.value)}
            />
          </label>
          <label className="grid gap-1.5 text-sm font-medium">
            Target amount
            <Input
              type="number"
              min="0.01"
              max="9999999999.99"
              step="0.01"
              required
              value={target}
              onChange={e => setTarget(e.target.value)}
            />
          </label>
          <label className="grid gap-1.5 text-sm font-medium">
            Dedicated account
            <NativeSelect
              required
              value={accountId}
              disabled={!!goal}
              onChange={e => setAccountId(e.target.value)}
            >
              <option value="">Choose an account</option>
              {accounts
                ?.filter(
                  a =>
                    a.canUse &&
                    !a.isLiability &&
                    (admin || a.ownerId === profile?.userId)
                )
                .map(a => (
                  <option key={a.id} value={a.id}>
                    {a.name} · {formatMoney(a.balance, currency)}
                  </option>
                ))}
            </NativeSelect>
          </label>
          <label className="grid gap-1.5 text-sm font-medium">
            Target date (optional)
            <Input
              type="date"
              min={todayIso()}
              value={targetDate}
              onChange={e => setTargetDate(e.target.value)}
            />
          </label>
          {!goal && (
            <label className="flex items-start gap-2 text-sm text-slate-600 dark:text-slate-400">
              <input
                className="mt-1 accent-brand-700"
                type="checkbox"
                checked={includeExisting}
                onChange={e => setIncludeExisting(e.target.checked)}
              />
              Include the account’s existing savings. Otherwise, track growth
              from today’s balance.
            </label>
          )}
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={onClose}
              disabled={busy}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={busy}>
              {busy ? 'Saving…' : 'Save goal'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
