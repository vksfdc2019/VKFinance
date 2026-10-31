import { useEffect, useState, type FormEvent } from 'react';
import {
  ArrowUpRight,
  Check,
  CreditCard,
  Layers3,
  LockKeyhole,
  Pencil,
  Plus,
  ShieldCheck,
} from 'lucide-react';
import { financeApi } from '@/api/endpoints';
import type {
  CreditGroup,
  CreditGroupInput,
  CreditOverview,
} from '@/api/creditTypes';
import type { Account } from '@/api/financeTypes';
import { ApiError, errorMessages } from '@/api/vkfClient';
import { useAsync } from '@/lib/useAsync';
import { formatMoney } from '@/lib/format';
import { cn } from '@/lib/utils';
import { FormErrors, TextField } from '@/components/forms';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Skeleton } from '@/components/ui/skeleton';
import { Spinner } from '@/components/ui/spinner';
import { toast } from '@/components/ui/sonner';

const SEGMENTS = [
  'bg-brand-400',
  'bg-sky-400',
  'bg-violet-400',
  'bg-amber-400',
  'bg-rose-400',
];

export function SharedCreditPanel({
  currency,
  version,
  onChanged,
}: {
  currency: string;
  version: number;
  onChanged: () => void;
}) {
  const { data, errors, loading, reload, setData } = useAsync(
    () => financeApi.creditGroups(),
    [version]
  );
  const [editing, setEditing] = useState<CreditGroup | 'new' | null>(null);
  function saved(next: CreditOverview) {
    setData(next);
    setEditing(null);
    onChanged();
  }
  if (!data)
    return (
      <div className="mb-6">
        <FormErrors errors={errors} />
        {loading ? (
          <Skeleton className="h-36 rounded-2xl" />
        ) : (
          <Button variant="outline" onClick={reload}>
            Retry credit overview
          </Button>
        )}
      </div>
    );
  const groups = [...data.groups].sort((a, b) => a.name.localeCompare(b.name));
  return (
    <section
      aria-labelledby="shared-credit-heading"
      className="mb-8 overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900"
    >
      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-slate-100 p-5 dark:border-slate-800 sm:p-6">
        <div className="flex items-center gap-3">
          <div className="flex size-11 items-center justify-center rounded-2xl bg-brand-50 text-brand-700 dark:bg-brand-950/50 dark:text-brand-300">
            <Layers3 className="size-5" />
          </div>
          <div>
            <h2
              id="shared-credit-heading"
              className="text-base font-semibold text-slate-950 dark:text-white"
            >
              Shared credit limits
            </h2>
            <p className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
              One bank facility. One limit. Every linked card accounted for.
            </p>
          </div>
        </div>
        {data.canManage && (
          <Button variant="outline" onClick={() => setEditing('new')}>
            <Plus className="size-4" />
            Create shared limit
          </Button>
        )}
      </div>
      <FormErrors errors={errors} />
      <dl className="grid grid-cols-1 divide-y divide-slate-100 bg-slate-50/70 dark:divide-slate-800 dark:bg-slate-950/30 sm:grid-cols-3 sm:divide-x sm:divide-y-0">
        <Metric
          label="Total credit limit"
          value={data.totals.creditLimit}
          currency={currency}
          hint={`${data.totals.facilities} credit ${data.totals.facilities === 1 ? 'facility' : 'facilities'} · shared limits counted once`}
        />
        <Metric
          label="Visible card balances"
          value={data.totals.outstanding}
          currency={currency}
          hint="Outstanding across your visible active cards"
        />
        <Metric
          label="Available credit"
          value={data.totals.available}
          currency={currency}
          hint="Shared facilities plus independent cards"
        />
      </dl>
      {!data.totals.complete && (
        <p className="m-5 flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-xs text-amber-900 dark:bg-amber-950/30 dark:text-amber-100">
          <LockKeyhole className="size-4 shrink-0" />
          Some linked cards are outside your access. Shared limits and
          availability are withheld to protect their balances.
        </p>
      )}
      {groups.length ? (
        <div className="grid gap-4 p-4 lg:grid-cols-2 sm:p-6">
          {groups.map(group => (
            <GroupTile
              key={group.id}
              group={group}
              currency={currency}
              canManage={data.canManage}
              onEdit={() => setEditing(group)}
            />
          ))}
        </div>
      ) : (
        <div className="flex flex-col items-center px-6 py-7 text-center">
          <CreditCard className="mb-2 size-6 text-slate-400" />
          <p className="text-sm font-medium text-slate-800 dark:text-slate-100">
            Cards sharing a limit belong together
          </p>
          <p className="mt-1 max-w-md text-xs leading-5 text-slate-500 dark:text-slate-400">
            {data.canManage
              ? 'Create a group and explicitly choose the cards that draw from the same bank limit. Cards from the same bank are never grouped automatically.'
              : 'Your family administrator can link cards that share a credit facility.'}
          </p>
        </div>
      )}
      {editing && (
        <GroupDialog
          group={editing === 'new' ? undefined : editing}
          currency={currency}
          onClose={() => setEditing(null)}
          onSaved={saved}
          onRefresh={() => {
            setEditing(null);
            reload();
          }}
        />
      )}
    </section>
  );
}

function Metric({
  label,
  value,
  currency,
  hint,
}: {
  label: string;
  value?: number;
  currency: string;
  hint: string;
}) {
  return (
    <div className="px-5 py-4 sm:px-6">
      <dt className="text-xs text-slate-500 dark:text-slate-400">{label}</dt>
      <dd className="mt-1 text-xl font-semibold tracking-tight text-slate-950 tabular-nums dark:text-white">
        {value === undefined ? 'Restricted' : formatMoney(value, currency)}
      </dd>
      <p className="mt-1 text-[11px] leading-4 text-slate-500 dark:text-slate-400">
        {hint}
      </p>
    </div>
  );
}

function GroupTile({
  group,
  currency,
  canManage,
  onEdit,
}: {
  group: CreditGroup;
  currency: string;
  canManage: boolean;
  onEdit: () => void;
}) {
  return (
    <article
      aria-label={`${group.name} shared facility`}
      className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-slate-950 via-slate-900 to-brand-950 p-5 text-white shadow-lg shadow-slate-950/10"
    >
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -right-20 -top-20 size-60 rounded-full border-[30px] border-white/5"
      />
      <div className="relative flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[10px] font-semibold uppercase tracking-widest text-white/60">
            {group.issuer || 'Shared credit facility'}
          </p>
          <h3 className="mt-1 truncate text-lg font-semibold">{group.name}</h3>
        </div>
        {canManage && (
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={`Edit ${group.name}`}
            onClick={onEdit}
            className="text-white hover:bg-white/10 hover:text-white"
          >
            <Pencil className="size-4" />
          </Button>
        )}
      </div>
      <div className="relative mt-5 flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs text-white/65">Shared availability</p>
          <p className="mt-1 text-3xl font-semibold tracking-tight tabular-nums">
            {formatMoney(group.available, currency)}
          </p>
        </div>
        <span
          className={cn(
            'rounded-full px-2.5 py-1 text-[11px] font-medium',
            group.overLimit > 0
              ? 'bg-rose-500/20 text-rose-200'
              : 'bg-white/10 text-white/80'
          )}
        >
          {group.overLimit > 0
            ? 'Over limit'
            : `${group.utilisationPct.toFixed(1)}% used`}
        </span>
      </div>
      <div
        role="meter"
        aria-label={`${group.name} shared utilisation`}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={Math.min(100, group.utilisationPct)}
        aria-valuetext={`${group.utilisationPct}% used`}
        className="relative mt-4 h-2 overflow-hidden rounded-full bg-white/15"
      >
        <div
          className="flex h-full"
          style={{
            width: `${Math.min(100, Math.max(0, group.utilisationPct))}%`,
          }}
        >
          {group.cards.map((card, i) =>
            card.balance > 0 ? (
              <div
                key={card.id}
                className={SEGMENTS[i % SEGMENTS.length]}
                style={{
                  width: `${group.outstanding > 0 ? (card.balance / group.outstanding) * 100 : 0}%`,
                }}
              />
            ) : null
          )}
        </div>
      </div>
      <dl className="relative mt-3 grid grid-cols-2 gap-4 text-xs">
        <div>
          <dt className="text-white/60">Shared limit</dt>
          <dd className="mt-0.5 font-semibold tabular-nums">
            {formatMoney(group.creditLimit, currency)}
          </dd>
        </div>
        <div className="text-right">
          <dt className="text-white/60">Combined outstanding</dt>
          <dd className="mt-0.5 font-semibold tabular-nums">
            {formatMoney(group.outstanding, currency)}
          </dd>
        </div>
      </dl>
      {group.overLimit > 0 && (
        <p className="relative mt-3 rounded-xl bg-rose-500/15 px-3 py-2 text-xs text-rose-100">
          Outstanding exceeds the facility by{' '}
          {formatMoney(group.overLimit, currency)}. Payments will restore
          availability.
        </p>
      )}
      <ul className="relative mt-5 space-y-2 border-t border-white/10 pt-3">
        {group.cards.map((card, i) => (
          <li
            key={card.id}
            className="flex items-center justify-between gap-3 text-xs"
          >
            <span className="flex min-w-0 items-center gap-2">
              <span
                aria-hidden="true"
                className={cn(
                  'size-2 shrink-0 rounded-full',
                  SEGMENTS[i % SEGMENTS.length]
                )}
              />
              <span className="truncate">
                {card.name}
                {card.last4 ? ` · ${card.last4}` : ''}
                {card.status === 'Closed' ? ' · Closed' : ''}
              </span>
            </span>
            <span className="shrink-0 tabular-nums text-white/80">
              {formatMoney(card.balance, currency)}
            </span>
          </li>
        ))}
      </ul>
      {group.cards.some(card => card.balance < 0) && (
        <p className="relative mt-3 text-[11px] text-white/70">
          Credit balances stay with their cards and do not increase the shared
          limit.
        </p>
      )}
      <p className="relative mt-4 flex items-center gap-1.5 text-[10px] text-white/55">
        <ShieldCheck className="size-3" />
        {group.activeCardCount} active cards · balances, bills and due dates
        stay separate
      </p>
    </article>
  );
}

function GroupDialog({
  group,
  currency,
  onClose,
  onSaved,
  onRefresh,
}: {
  group?: CreditGroup;
  currency: string;
  onClose: () => void;
  onSaved: (next: CreditOverview) => void;
  onRefresh: () => void;
}) {
  const [name, setName] = useState(group?.name ?? '');
  const [issuer, setIssuer] = useState(group?.issuer ?? '');
  const [limit, setLimit] = useState(group ? String(group.creditLimit) : '');
  const [selected, setSelected] = useState<string[]>(group?.cardIds ?? []);
  const [accounts, setAccounts] = useState<Account[]>();
  const [errors, setErrors] = useState<string[]>([]);
  const [conflict, setConflict] = useState(false);
  const [saving, setSaving] = useState(false);
  const [archiving, setArchiving] = useState(false);
  useEffect(() => {
    financeApi
      .accounts(true)
      .then(setAccounts)
      .catch((e: unknown) => setErrors(errorMessages(e)));
  }, []);
  const cards = (accounts ?? []).filter(
    a =>
      a.type === 'Credit Card' &&
      (a.status === 'Active' || group?.cardIds.includes(a.id))
  );
  const chosen = cards.filter(a => selected.includes(a.id));
  const used = chosen.reduce((sum, a) => sum + Math.max(0, a.balance), 0);
  const parsed = Number(limit.replace(/[, ]/g, ''));
  async function submit(e: FormEvent) {
    e.preventDefault();
    setErrors([]);
    setSaving(true);
    try {
      let result: CreditOverview;
      if (archiving && group)
        result = await financeApi.archiveCreditGroup(group.id, group.version);
      else {
        const input: CreditGroupInput = {
          name: name.trim(),
          issuer: issuer.trim() || null,
          creditLimit: parsed,
          cardIds: selected,
          expectedVersion: group?.version,
        };
        if (!Number.isFinite(parsed) || parsed < 0.01)
          throw new Error('Enter a shared limit of at least 0.01.');
        result = group
          ? await financeApi.updateCreditGroup(group.id, input)
          : await financeApi.createCreditGroup(input);
      }
      toast.success(
        archiving
          ? 'Group archived. Card balances are unchanged.'
          : 'Shared credit limit saved'
      );
      onSaved(result);
    } catch (error) {
      setErrors(
        error instanceof ApiError
          ? errorMessages(error)
          : [
              error instanceof Error
                ? error.message
                : 'Could not save the group.',
            ]
      );
      setConflict(error instanceof ApiError && error.status === 409);
    } finally {
      setSaving(false);
    }
  }
  return (
    <Dialog open onOpenChange={open => !open && !saving && onClose()}>
      <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-xl">
        <form onSubmit={submit} className="space-y-5" noValidate>
          <DialogHeader>
            <DialogTitle>
              {archiving
                ? 'Return cards to independent limits?'
                : group
                  ? `Edit ${group.name}`
                  : 'Create a shared credit limit'}
            </DialogTitle>
            <DialogDescription>
              {archiving
                ? 'This archives the group and unlinks its cards. Each card returns to its saved independent limit. Balances, bills and payment history stay intact.'
                : 'Choose cards that the bank confirms share one credit facility. Grouping changes the limit display, never the money.'}
            </DialogDescription>
          </DialogHeader>
          {!archiving && (
            <>
              <div className="grid gap-3 sm:grid-cols-2">
                <TextField
                  id="credit-group-name"
                  label="Group name"
                  value={name}
                  maxLength={80}
                  placeholder="e.g. My Axis credit facility"
                  onChange={e => setName(e.target.value)}
                />
                <TextField
                  id="credit-group-issuer"
                  label="Bank / issuer"
                  value={issuer}
                  maxLength={80}
                  placeholder="e.g. Axis Bank"
                  onChange={e => setIssuer(e.target.value)}
                />
              </div>
              <TextField
                id="credit-group-limit"
                label="Shared credit limit"
                value={limit}
                inputMode="decimal"
                placeholder="3,00,000"
                onChange={e => setLimit(e.target.value)}
              />
              <fieldset>
                <legend className="mb-2 text-sm font-medium">
                  Cards sharing this facility
                </legend>
                <div className="max-h-60 space-y-2 overflow-y-auto">
                  {accounts ? (
                    cards.map(card => {
                      const unavailable =
                        !!card.creditLimitGroupId &&
                        card.creditLimitGroupId !== group?.id;
                      const checked = selected.includes(card.id);
                      return (
                        <label
                          key={card.id}
                          className={cn(
                            'flex cursor-pointer items-center gap-3 rounded-xl border p-3 transition-colors',
                            checked
                              ? 'border-brand-500 bg-brand-50 dark:bg-brand-950/30'
                              : 'border-slate-200 dark:border-slate-800',
                            unavailable && 'cursor-not-allowed opacity-50'
                          )}
                        >
                          <input
                            type="checkbox"
                            aria-label={`Include ${card.name}`}
                            checked={checked}
                            disabled={unavailable || saving}
                            onChange={e =>
                              setSelected(
                                e.target.checked
                                  ? [...selected, card.id]
                                  : selected.filter(id => id !== card.id)
                              )
                            }
                            className="size-4 shrink-0 accent-brand-600"
                          />
                          <span className="min-w-0 flex-1">
                            <span className="block truncate text-sm font-medium">
                              {card.name}
                            </span>
                            <span className="block text-xs text-slate-500 dark:text-slate-400">
                              {unavailable
                                ? 'Already in another shared facility'
                                : `${card.institution || 'Credit card'}${card.last4 ? ` · ${card.last4}` : ''}${card.status === 'Closed' ? ' · Closed' : ''}`}
                            </span>
                          </span>
                          <span className="shrink-0 text-sm tabular-nums">
                            {formatMoney(card.balance, currency)}
                          </span>
                          {checked && (
                            <Check className="size-4 shrink-0 text-brand-600 dark:text-brand-400" />
                          )}
                        </label>
                      );
                    })
                  ) : (
                    <Skeleton className="h-24 rounded-xl" />
                  )}
                </div>
              </fieldset>
              <div className="rounded-2xl bg-slate-950 dark:bg-slate-700 p-4 text-white">
                <p className="flex items-center gap-1.5 text-xs text-white/60">
                  <ArrowUpRight className="size-3.5" />
                  Preview · {chosen.length} selected cards
                </p>
                <div className="mt-2 flex flex-wrap items-baseline justify-between gap-2">
                  <span className="text-xs text-white/70">
                    Available across this facility
                  </span>
                  <span className="text-xl font-semibold tabular-nums">
                    {Number.isFinite(parsed) && parsed > 0
                      ? formatMoney(Math.max(0, parsed - used), currency)
                      : '—'}
                  </span>
                </div>
                <p className="mt-1 text-[11px] text-white/60">
                  Combined outstanding {formatMoney(used, currency)}. Credit
                  balances on one card do not increase another card’s spending
                  power.
                </p>
              </div>
            </>
          )}
          <FormErrors errors={errors} />
          {conflict && (
            <Button type="button" variant="outline" onClick={onRefresh}>
              Refresh groups and review
            </Button>
          )}
          <DialogFooter className="gap-2">
            {group && !archiving && (
              <Button
                type="button"
                variant="ghost"
                className="mr-auto text-rose-600 dark:text-rose-400"
                disabled={saving}
                onClick={() => setArchiving(true)}
              >
                Archive group
              </Button>
            )}
            <Button
              type="button"
              variant="outline"
              disabled={saving}
              onClick={archiving ? () => setArchiving(false) : onClose}
            >
              {archiving ? 'Back' : 'Cancel'}
            </Button>
            <Button
              type="submit"
              disabled={
                saving ||
                (!archiving && (!accounts || !selected.length || !name.trim()))
              }
            >
              {saving && <Spinner />}
              {archiving ? 'Archive and unlink cards' : 'Save shared limit'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
