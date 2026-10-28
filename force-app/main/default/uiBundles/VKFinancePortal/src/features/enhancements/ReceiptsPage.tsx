import { useEffect, useState } from 'react';
import { Camera, Download, ImagePlus, Search, Trash2 } from 'lucide-react';
import { enhancementsApi, type Receipt } from '@/api/enhancements';
import { financeApi } from '@/api/endpoints';
import type { Txn } from '@/api/financeTypes';
import { errorMessages } from '@/api/vkfClient';
import { useAuth } from '@/features/auth/AuthContext';
import { useLedger } from '@/features/ledger/LedgerContext';
import { useAsync } from '@/lib/useAsync';
import { formatDate, formatMoney, monthKey } from '@/lib/format';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Panel, EmptyState } from '@/components/finance/ui';
import { FormErrors } from '@/components/forms';
import { FeatureGate } from './EnhancementsLayout';
import { Intro } from './shared';
import { prepareReceipt } from './receiptImage';

export default function ReceiptsPage() {
  return (
    <FeatureGate feature="RECEIPTS">
      <Receipts />
    </FeatureGate>
  );
}
function Receipts() {
  const { version, currency } = useLedger();
  const [month, setMonth] = useState(monthKey());
  const [search, setSearch] = useState('');
  const { data, errors, loading } = useAsync(
    () => financeApi.transactions({ month, q: search || undefined, limit: 50 }),
    [month, search, version]
  );
  const [selected, setSelected] = useState<Txn>();
  const [more, setMore] = useState<Txn[]>([]);
  const [cursor, setCursor] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [moreErrors, setMoreErrors] = useState<string[]>([]);
  useEffect(() => {
    // Reset dependent pagination when a new first page arrives, as in TransactionsPage.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setMore([]);
    setCursor(data?.nextCursor);
    setSelected(undefined);
  }, [data]);
  async function loadMore() {
    if (!cursor) return;
    setBusy(true);
    try {
      const page = await financeApi.transactions({
        month,
        q: search || undefined,
        limit: 50,
        cursor,
      });
      setMore(items => [...items, ...page.items]);
      setCursor(page.nextCursor);
      setMoreErrors([]);
    } catch (e) {
      setMoreErrors(errorMessages(e));
    } finally {
      setBusy(false);
    }
  }
  const items = [...(data?.items ?? []), ...more];
  return (
    <>
      <Intro
        eyebrow="The details, kept together"
        title="A place for every receipt"
        description="Choose a transaction to add a photo, check a receipt or download a copy. Images are compressed before upload and remain behind your family’s access controls."
      />
      <div className="mb-5 flex flex-wrap gap-3">
        <label className="grid gap-1 text-xs text-slate-500">
          Month
          <Input
            type="month"
            value={month}
            onChange={e => setMonth(e.target.value || monthKey())}
          />
        </label>
        <label className="grid min-w-56 flex-1 gap-1 text-xs text-slate-500">
          Find a transaction
          <span className="relative">
            <Search className="absolute left-3 top-3 size-4 text-slate-400" />
            <Input
              className="pl-9"
              placeholder="Merchant, note or reference"
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
          </span>
        </label>
      </div>
      <FormErrors errors={[...errors, ...moreErrors]} />
      <div className="grid items-start gap-5 xl:grid-cols-[1.1fr_1fr]">
        <Panel title="Transactions">
          <div className="max-h-[38rem] space-y-1 overflow-auto">
            {!data && loading ? (
              <Skeleton className="h-64" />
            ) : items.length === 0 ? (
              <EmptyState
                icon={<Camera />}
                title="No transactions in this view"
              >
                Choose another month or search.
              </EmptyState>
            ) : (
              items.map(txn => (
                <button
                  key={txn.id}
                  type="button"
                  onClick={() => setSelected(txn)}
                  className={`flex w-full items-center justify-between gap-4 rounded-xl p-3 text-left transition-colors ${selected?.id === txn.id ? 'bg-teal-50 ring-1 ring-teal-100' : 'hover:bg-slate-50'}`}
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-semibold text-slate-800">
                      {txn.payee || txn.categoryName || txn.type}
                    </p>
                    <p className="mt-1 text-xs text-slate-400">
                      {formatDate(txn.txnDate)} · {txn.accountName}
                    </p>
                  </div>
                  <span className="text-sm font-semibold tabular-nums">
                    {formatMoney(txn.amount, currency)}
                  </span>
                </button>
              ))
            )}
            {cursor && (
              <Button
                variant="outline"
                disabled={busy}
                className="mt-3 w-full"
                onClick={() => void loadMore()}
              >
                Load more transactions
              </Button>
            )}
          </div>
        </Panel>
        {selected ? (
          <ReceiptCollection key={selected.id} transaction={selected} />
        ) : (
          <Panel>
            <EmptyState icon={<Camera />} title="Choose a transaction">
              Its receipt photos will appear here.
            </EmptyState>
          </Panel>
        )}
      </div>
    </>
  );
}

function ReceiptCollection({ transaction }: { transaction: Txn }) {
  const { can } = useAuth();
  const { data, errors, loading, reload } = useAsync(
    () => enhancementsApi.receipts(transaction.id),
    [transaction.id]
  );
  const [busy, setBusy] = useState(false);
  const [actionErrors, setActionErrors] = useState<string[]>([]);
  const [photo, setPhoto] = useState<Receipt>();
  const [url, setUrl] = useState('');
  const [removing, setRemoving] = useState<Receipt>();
  useEffect(() => {
    return () => {
      if (url) URL.revokeObjectURL(url);
    };
  }, [url]);
  async function upload(file?: File) {
    if (!file) return;
    setBusy(true);
    setActionErrors([]);
    try {
      await enhancementsApi.upload(transaction.id, await prepareReceipt(file));
      reload();
    } catch (e) {
      setActionErrors(
        e instanceof Error && !(e as { code?: string }).code
          ? [e.message]
          : errorMessages(e)
      );
    } finally {
      setBusy(false);
    }
  }
  async function view(receipt: Receipt) {
    setBusy(true);
    setActionErrors([]);
    try {
      const result = await enhancementsApi.photo(receipt.id);
      const bytes = Uint8Array.from(atob(result.data ?? ''), ch =>
        ch.charCodeAt(0)
      );
      setUrl(URL.createObjectURL(new Blob([bytes], { type: result.mimeType })));
      setPhoto(result);
    } catch (e) {
      setActionErrors(errorMessages(e));
    } finally {
      setBusy(false);
    }
  }
  async function remove() {
    if (!removing) return;
    setBusy(true);
    try {
      await enhancementsApi.removePhoto(removing.id);
      setRemoving(undefined);
      reload();
    } catch (e) {
      setActionErrors(errorMessages(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <Panel
      title="Receipt photos"
      description={`${transaction.payee || transaction.categoryName || transaction.type} · ${data?.length ?? 0} / 5 photos`}
    >
      <FormErrors errors={[...errors, ...actionErrors]} />
      {loading && !data ? (
        <Skeleton className="h-40" />
      ) : data?.length === 0 ? (
        <div className="rounded-xl bg-violet-50/60 py-8 text-center">
          <Camera className="mx-auto mb-2 size-8 text-violet-400" />
          <p className="text-sm text-slate-500">
            The story behind this purchase starts here.
          </p>
        </div>
      ) : (
        <ul className="space-y-2">
          {data?.map(receipt => (
            <li
              key={receipt.id}
              className="flex items-center gap-3 rounded-xl border border-slate-100 p-3"
            >
              <Camera className="size-5 shrink-0 text-violet-500" />
              <button
                type="button"
                disabled={busy}
                onClick={() => void view(receipt)}
                className="min-w-0 flex-1 text-left"
              >
                <p className="truncate text-sm font-medium text-slate-800">
                  {receipt.fileName}
                </p>
                <p className="mt-1 text-xs text-slate-400">
                  {Math.ceil(receipt.bytes / 1024)} KB ·{' '}
                  {formatDate(receipt.createdAt.slice(0, 10))}
                </p>
              </button>
              {transaction.canEdit && can('RECEIPTS:DELETE') && (
                <Button
                  aria-label={`Remove ${receipt.fileName}`}
                  variant="ghost"
                  size="icon-sm"
                  disabled={busy}
                  onClick={() => setRemoving(receipt)}
                >
                  <Trash2 className="size-4" />
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
      {transaction.canEdit &&
        can('RECEIPTS:CREATE') &&
        (data?.length ?? 0) < 5 && (
          <label
            className={`mt-5 flex cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed border-violet-200 bg-violet-50/40 p-4 text-sm font-medium text-violet-800 ${busy ? 'pointer-events-none opacity-50' : 'hover:bg-violet-50'}`}
          >
            <ImagePlus className="size-4" />
            {busy ? 'Processing photo…' : 'Take or choose a photo'}
            <input
              aria-label="Attach receipt photo"
              className="sr-only"
              type="file"
              accept="image/jpeg,image/png,image/webp"
              disabled={busy}
              onChange={e => {
                void upload(e.target.files?.[0]);
                e.target.value = '';
              }}
            />
          </label>
        )}
      <p className="mt-4 text-xs leading-relaxed text-slate-400">
        JPEG, PNG or WebP. Photos are resized to 1,600 pixels and compressed to
        fit the upload limit. Do not include full card numbers or other payment
        secrets.
      </p>
      <Dialog
        open={!!photo}
        onOpenChange={v => {
          if (!v) {
            setPhoto(undefined);
            setUrl('');
          }
        }}
      >
        <DialogContent className="max-h-[90svh] overflow-auto sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>{photo?.fileName}</DialogTitle>
            <DialogDescription>
              Private receipt photo for this transaction.
            </DialogDescription>
          </DialogHeader>
          {url && (
            <>
              <img
                src={url}
                alt={`Receipt: ${photo?.fileName}`}
                className="max-h-[65svh] w-full rounded-xl bg-slate-50 object-contain"
              />
              <Button asChild variant="outline">
                <a href={url} download={photo?.fileName}>
                  <Download />
                  Download photo
                </a>
              </Button>
            </>
          )}
        </DialogContent>
      </Dialog>
      <Dialog
        open={!!removing}
        onOpenChange={v => {
          if (!v && !busy) setRemoving(undefined);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Remove this receipt?</DialogTitle>
            <DialogDescription>
              The photo is deleted. The transaction and its balance effect
              remain unchanged.
            </DialogDescription>
          </DialogHeader>
          <FormErrors errors={actionErrors} />
          <DialogFooter>
            <Button
              variant="outline"
              disabled={busy}
              onClick={() => setRemoving(undefined)}
            >
              Keep photo
            </Button>
            <Button disabled={busy} onClick={() => void remove()}>
              Remove photo
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Panel>
  );
}
