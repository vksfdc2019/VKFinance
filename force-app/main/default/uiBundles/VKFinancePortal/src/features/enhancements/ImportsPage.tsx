import { useEffect, useMemo, useState, type ChangeEvent } from 'react';
import {
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  CheckCircle2,
  CloudUpload,
  FileSpreadsheet,
  RefreshCw,
} from 'lucide-react';
import { enhancementsApi, type ImportBatch } from '@/api/enhancements';
import { financeApi } from '@/api/endpoints';
import type { EntryInput, EntryType } from '@/api/financeTypes';
import { errorMessages } from '@/api/vkfClient';
import { useLedger } from '@/features/ledger/LedgerContext';
import { useAsync } from '@/lib/useAsync';
import { formatMoney } from '@/lib/format';
import { Button } from '@/components/ui/button';
import { Panel } from '@/components/finance/ui';
import { FormErrors } from '@/components/forms';
import { Badge } from '@/components/ui/badge';
import { FeatureGate } from './EnhancementsLayout';
import { Intro, NativeSelect } from './shared';
import {
  needsTransferReview,
  parseCsv,
  statementAmount,
  statementDate,
} from './csv';

type Mapping = {
  date: string;
  description: string;
  amount: string;
  debit: string;
  credit: string;
  reference: string;
};
type Preview = {
  row: number;
  entry: EntryInput;
  type: EntryType | 'Skip';
  error?: string;
  warning?: string;
};
const emptyMapping: Mapping = {
  date: '',
  description: '',
  amount: '',
  debit: '',
  credit: '',
  reference: '',
};

export default function ImportsPage() {
  return (
    <FeatureGate feature="IMPORTS">
      <Imports />
    </FeatureGate>
  );
}
function Imports() {
  const { version, refresh, currency } = useLedger();
  const { data: choices, errors: choiceErrors } = useAsync(
    () => Promise.all([financeApi.accounts(), financeApi.categories()]),
    []
  );
  const history = useAsync(() => enhancementsApi.imports(), [version]);
  const reloadHistory = history.reload;
  const [fileName, setFileName] = useState('');
  const [csv, setCsv] = useState<ReturnType<typeof parseCsv>>();
  const [mapping, setMapping] = useState<Mapping>(emptyMapping);
  const [accountId, setAccountId] = useState('');
  const [mode, setMode] = useState<'signed' | 'columns'>('signed');
  const [positiveDebits, setPositiveDebits] = useState(false);
  const [dateFormat, setDateFormat] = useState<'DMY' | 'MDY' | 'ISO'>('DMY');
  const [expenseCategory, setExpenseCategory] = useState('');
  const [incomeCategory, setIncomeCategory] = useState('');
  const [preview, setPreview] = useState<Preview[]>();
  const [visible, setVisible] = useState(50);
  const [errors, setErrors] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [batch, setBatch] = useState<ImportBatch>();
  const account = choices?.[0].find(a => a.id === accountId);
  const stage = batch ? 4 : preview ? 3 : csv ? 2 : 1;
  const accepted = useMemo(
    () => preview?.filter(r => r.type !== 'Skip') ?? [],
    [preview]
  );
  const invalid = accepted.some(
    r => r.error || !(r.type === 'Income' ? incomeCategory : expenseCategory)
  );

  useEffect(() => {
    if (batch?.status !== 'Processing') return;
    let cancelled = false;
    const timer = setInterval(() => {
      void enhancementsApi
        .import(batch.id)
        .then(result => {
          if (cancelled) return;
          setBatch(result);
          if (result.status !== 'Processing') {
            refresh();
            reloadHistory();
          }
        })
        .catch(error => {
          if (!cancelled) setErrors(errorMessages(error));
        });
    }, 3000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [batch?.id, batch?.status, refresh, reloadHistory]);

  function reset() {
    setCsv(undefined);
    setPreview(undefined);
    setBatch(undefined);
    setFileName('');
    setErrors([]);
    setVisible(50);
  }
  async function upload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setErrors([]);
    try {
      if (file.size > 1_000_000)
        throw new Error('Choose a CSV file up to 1 MB.');
      const parsed = parseCsv(await file.text());
      setCsv(parsed);
      setFileName(file.name.slice(0, 120));
      setPreview(undefined);
      const find = (pattern: RegExp) =>
        parsed.headers.find(h => pattern.test(h)) ?? '';
      const next = {
        date: find(/^(transaction\s*date|txn\s*date|date|value\s*date)$/i),
        description: find(
          /^(description|narration|particulars|payee|merchant)$/i
        ),
        amount: find(/^(amount|transaction\s*amount)$/i),
        debit: find(/^(debit|withdrawal|withdrawals|debit\s*amount)$/i),
        credit: find(/^(credit|deposit|deposits|credit\s*amount)$/i),
        reference: find(
          /^(reference|reference\s*no|ref\s*no|transaction\s*id)$/i
        ),
      };
      setMapping(next);
      setMode(next.amount ? 'signed' : 'columns');
      const dateIndex = parsed.headers.indexOf(next.date);
      setDateFormat(
        dateIndex >= 0 && /^\d{4}[-/.]/.test(parsed.rows[0][dateIndex])
          ? 'ISO'
          : 'DMY'
      );
    } catch (e) {
      setErrors([
        e instanceof Error ? e.message : 'This statement could not be read.',
      ]);
    }
    event.target.value = '';
  }
  function review() {
    if (
      !csv ||
      !account ||
      !mapping.date ||
      !mapping.description ||
      (mode === 'signed' ? !mapping.amount : !mapping.debit || !mapping.credit)
    ) {
      setErrors(['Choose an account and map the required columns.']);
      return;
    }
    const cell = (row: string[], column: string) =>
      column ? (row[csv.headers.indexOf(column)] ?? '') : '';
    setErrors([]);
    setPreview(
      csv.rows.map((row, i) => {
        const description = cell(row, mapping.description);
        try {
          let amount: number;
          if (mode === 'signed') {
            const parsed = statementAmount(cell(row, mapping.amount));
            if (parsed === undefined || parsed === 0)
              throw new Error('Amount must be nonzero.');
            amount = positiveDebits ? -parsed : parsed;
          } else {
            const debit = statementAmount(cell(row, mapping.debit)) ?? 0,
              credit = statementAmount(cell(row, mapping.credit)) ?? 0;
            if (
              (debit && credit) ||
              (!debit && !credit) ||
              debit < 0 ||
              credit < 0
            )
              throw new Error(
                'Use exactly one positive debit or credit per row.'
              );
            amount = credit - debit;
          }
          const type: EntryType =
            amount < 0
              ? 'Expense'
              : account.type === 'Credit Card'
                ? 'Refund'
                : 'Income';
          const warning = needsTransferReview(description)
            ? 'Possible transfer, card payment or EMI. Record it with the existing payment workflow.'
            : account.type === 'Credit Card' && amount > 0
              ? 'Review this card credit. Payments belong in the transfer workflow; only a true refund should be imported.'
              : undefined;
          const reference = cell(row, mapping.reference);
          if (description.length > 120 || reference.length > 60)
            throw new Error(
              'Description exceeds 120 characters or reference exceeds 60. Shorten the source cell.'
            );
          const entry: EntryInput = {
            type,
            amount: Math.abs(amount),
            date: statementDate(cell(row, mapping.date), dateFormat),
            accountId,
            payee: description,
            referenceNo: reference || undefined,
          };
          return {
            row: i + 2,
            entry,
            type: warning ? ('Skip' as const) : type,
            warning,
          };
        } catch (e) {
          return {
            row: i + 2,
            entry: { payee: description },
            type: 'Skip' as const,
            error: e instanceof Error ? e.message : 'Invalid row',
          };
        }
      })
    );
  }
  async function save() {
    if (!accepted.length || invalid) return;
    setBusy(true);
    setErrors([]);
    try {
      const rows = accepted.map(r => ({
        ...r.entry,
        type: r.type as EntryType,
        categoryId: r.type === 'Income' ? incomeCategory : expenseCategory,
      }));
      const created = await enhancementsApi.stage(accountId, fileName, rows);
      setBatch(await enhancementsApi.import(created.id));
      history.reload();
    } catch (e) {
      setErrors(errorMessages(e));
    } finally {
      setBusy(false);
    }
  }
  async function run(action: 'commit' | 'cancel') {
    if (!batch) return;
    setBusy(true);
    setErrors([]);
    try {
      setBatch(
        await (action === 'commit'
          ? enhancementsApi.commit(batch.id)
          : enhancementsApi.cancelImport(batch.id))
      );
      history.reload();
    } catch (e) {
      setErrors(errorMessages(e));
    } finally {
      setBusy(false);
    }
  }
  async function open(item: ImportBatch) {
    setErrors([]);
    setBusy(true);
    try {
      setBatch(await enhancementsApi.import(item.id));
    } catch (e) {
      setErrors(errorMessages(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Intro
        eyebrow="Less typing. More clarity."
        title="Your statement, organized"
        description="Upload a CSV, match its columns and review the entries. Nothing reaches your ledger until you explicitly start the import."
      />
      <ol className="mb-6 grid grid-cols-4 gap-2">
        {['Upload', 'Match columns', 'Review', 'Import'].map((label, i) => (
          <li
            key={label}
            className={`flex items-center gap-2 rounded-xl px-3 py-3 text-xs font-semibold ${stage === i + 1 ? 'bg-teal-900 text-white' : 'bg-white text-slate-400'}`}
          >
            <span
              className={`flex size-5 shrink-0 items-center justify-center rounded-full ${stage === i + 1 ? 'bg-white/15' : 'bg-slate-100'}`}
            >
              {i + 1}
            </span>
            <span className="hidden sm:inline">{label}</span>
          </li>
        ))}
      </ol>
      <FormErrors errors={[...choiceErrors, ...errors]} />
      {!csv && !batch && (
        <Panel>
          <label className="flex min-h-64 cursor-pointer flex-col items-center justify-center rounded-2xl border-2 border-dashed border-teal-200 bg-teal-50/30 p-6 text-center transition-colors hover:bg-teal-50">
            <span className="mb-4 rounded-2xl bg-white p-4 text-teal-700 shadow-sm">
              <CloudUpload className="size-8" />
            </span>
            <span className="text-lg font-semibold text-slate-900">
              Choose a bank or card CSV
            </span>
            <span className="mt-2 text-sm text-slate-500">
              Up to 500 rows · 1 MB · No bank password needed
            </span>
            <input
              className="mt-5 max-w-full text-sm file:mr-3 file:rounded-lg file:border-0 file:bg-teal-800 file:px-4 file:py-2 file:text-white"
              aria-label="Upload statement CSV"
              type="file"
              accept=".csv,text/csv"
              onChange={e => void upload(e)}
            />
          </label>
        </Panel>
      )}
      {csv && !preview && !batch && (
        <Panel
          title={fileName}
          description={`${csv.rows.length} rows found. Check the column mapping against your bank’s export.`}
        >
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="grid gap-1.5 text-sm font-medium">
              Account
              <NativeSelect
                required
                value={accountId}
                onChange={e => setAccountId(e.target.value)}
              >
                <option value="">Choose an account</option>
                {choices?.[0]
                  .filter(a => a.canUse && a.type !== 'Loan')
                  .map(a => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
              </NativeSelect>
            </label>
            <label className="grid gap-1.5 text-sm font-medium">
              Date format
              <NativeSelect
                value={dateFormat}
                onChange={e =>
                  setDateFormat(e.target.value as typeof dateFormat)
                }
              >
                <option value="DMY">DD/MM/YYYY</option>
                <option value="MDY">MM/DD/YYYY</option>
                <option value="ISO">YYYY-MM-DD</option>
              </NativeSelect>
            </label>
            <label className="grid gap-1.5 text-sm font-medium">
              Amount layout
              <NativeSelect
                value={mode}
                onChange={e => setMode(e.target.value as typeof mode)}
              >
                <option value="signed">Signed amount (negative = debit)</option>
                <option value="columns">Separate debit / credit columns</option>
              </NativeSelect>
            </label>
            {mode === 'signed' && (
              <label className="grid gap-1.5 text-sm font-medium">
                Amount sign convention
                <NativeSelect
                  value={positiveDebits ? 'debit' : 'credit'}
                  onChange={e => setPositiveDebits(e.target.value === 'debit')}
                >
                  <option value="credit">
                    Positive = money in; negative = money out
                  </option>
                  <option value="debit">
                    Positive = charges; negative = credits (some cards)
                  </option>
                </NativeSelect>
              </label>
            )}
            {(
              [
                'date',
                'description',
                ...(mode === 'signed' ? ['amount'] : ['debit', 'credit']),
                'reference',
              ] as (keyof Mapping)[]
            ).map(key => (
              <label
                key={key}
                className="grid gap-1.5 text-sm font-medium capitalize"
              >
                {key} column{key === 'reference' ? ' (optional)' : ''}
                <NativeSelect
                  value={mapping[key]}
                  onChange={e =>
                    setMapping({ ...mapping, [key]: e.target.value })
                  }
                >
                  <option value="">Choose a column</option>
                  {csv.headers.map(header => (
                    <option key={header}>{header}</option>
                  ))}
                </NativeSelect>
              </label>
            ))}
          </div>
          <div className="mt-5 rounded-xl bg-amber-50 p-3 text-xs leading-relaxed text-amber-900">
            <AlertTriangle className="mb-1 size-4" />
            Confirm your bank’s debit/credit convention. Transfers, loan
            repayments and card payments need their existing workflows to keep
            reports accurate.
          </div>
          <div className="mt-5 flex justify-between">
            <Button variant="ghost" onClick={reset}>
              <ArrowLeft />
              Choose another file
            </Button>
            <Button onClick={review}>
              Review entries
              <ArrowRight />
            </Button>
          </div>
        </Panel>
      )}
      {preview && !batch && (
        <Panel
          title="Review before recording"
          description={`${accepted.length} selected · ${preview.length - accepted.length} skipped. Matching statement fingerprints are skipped by the server.`}
        >
          <div className="mb-5 grid gap-3 sm:grid-cols-2">
            {(['Expense', 'Income'] as const).map(kind => (
              <label key={kind} className="grid gap-1.5 text-sm font-medium">
                {kind === 'Expense'
                  ? 'Expense / refund category'
                  : 'Income category'}
                <NativeSelect
                  value={kind === 'Expense' ? expenseCategory : incomeCategory}
                  onChange={e =>
                    kind === 'Expense'
                      ? setExpenseCategory(e.target.value)
                      : setIncomeCategory(e.target.value)
                  }
                >
                  <option value="">Choose a category</option>
                  {choices?.[1]
                    .filter(c => c.active && c.kind === kind)
                    .map(c => (
                      <option key={c.id} value={c.id}>
                        {c.name}
                      </option>
                    ))}
                </NativeSelect>
              </label>
            ))}
          </div>
          <div className="overflow-auto">
            <table className="w-full min-w-[650px] text-left text-xs">
              <thead className="border-b border-slate-200 text-slate-500">
                <tr>
                  {[
                    'Row',
                    'Date',
                    'Description / review',
                    'Amount',
                    'Classification',
                  ].map(h => (
                    <th key={h} className="p-2 font-medium">
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {preview.slice(0, visible).map((r, i) => (
                  <tr key={r.row} className="border-b border-slate-100">
                    <td className="p-2 text-slate-400">{r.row}</td>
                    <td className="p-2 whitespace-nowrap">
                      {r.entry.date ?? '—'}
                    </td>
                    <td className="max-w-xs p-2">
                      <p>{r.entry.payee}</p>
                      {(r.error || r.warning) && (
                        <p className="mt-1 text-amber-800">
                          {r.error || r.warning}
                        </p>
                      )}
                    </td>
                    <td className="p-2 whitespace-nowrap">
                      {r.entry.amount != null
                        ? formatMoney(r.entry.amount, currency)
                        : '—'}
                    </td>
                    <td className="p-2">
                      <NativeSelect
                        aria-label={`Classification for row ${r.row}`}
                        value={r.type}
                        disabled={!!r.error}
                        onChange={e =>
                          setPreview(
                            preview.map((item, index) =>
                              index === i
                                ? {
                                    ...item,
                                    type: e.target.value as Preview['type'],
                                  }
                                : item
                            )
                          )
                        }
                      >
                        <option>Skip</option>
                        <option>Expense</option>
                        {account?.type !== 'Credit Card' && (
                          <option>Income</option>
                        )}
                        <option>Refund</option>
                      </NativeSelect>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {visible < preview.length && (
            <Button
              className="mt-3"
              variant="outline"
              onClick={() => setVisible(v => v + 50)}
            >
              Show more rows
            </Button>
          )}
          <p className="mt-4 text-xs text-slate-500">
            Use the existing transfer/card/loan payment actions for skipped
            money movements. Identical imported date, amount, type, reference
            and description are treated conservatively as duplicates.
          </p>
          <div className="mt-5 flex justify-between gap-3">
            <Button
              variant="ghost"
              disabled={busy}
              onClick={() => setPreview(undefined)}
            >
              <ArrowLeft />
              Back to mapping
            </Button>
            <Button
              disabled={busy || !accepted.length || invalid}
              onClick={() => void save()}
            >
              {busy
                ? 'Saving review…'
                : `Save ${accepted.length} reviewed rows`}
            </Button>
          </div>
        </Panel>
      )}
      {batch && (
        <Panel
          title={batch.fileName}
          action={<Badge variant="outline">{batch.status}</Badge>}
        >
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {[
              ['Reviewed', batch.total],
              ['Imported', batch.imported],
              ['Duplicates', batch.duplicates],
              ['To review', batch.failed],
            ].map(([label, count]) => (
              <div key={String(label)} className="rounded-xl bg-slate-50 p-4">
                <p className="text-xs text-slate-500">{label}</p>
                <p className="mt-2 text-2xl font-semibold">{count ?? 0}</p>
              </div>
            ))}
          </div>
          {batch.status === 'Draft' && (
            <p className="mt-5 text-sm text-slate-600">
              Your reviewed rows are saved. Start the import to record them in
              the ledger.
            </p>
          )}
          {batch.status === 'Processing' && (
            <p className="mt-5 flex items-center gap-2 text-sm text-teal-800">
              <RefreshCw className="size-4 animate-spin" />
              Processing securely in the background. You can leave this page and
              return later.
            </p>
          )}
          {batch.status === 'Completed' && (
            <p className="mt-5 flex items-center gap-2 text-sm text-teal-800">
              <CheckCircle2 className="size-4" />
              Finished. Your ledger and balances now include the imported
              entries.
            </p>
          )}
          {batch.error && (
            <p className="mt-4 text-sm text-amber-800">{batch.error}</p>
          )}
          {batch.rows
            ?.filter(r => r.status === 'Failed')
            .map(r => (
              <p key={r.id} className="mt-2 text-xs text-rose-700">
                Row {r.row}: {r.error}
              </p>
            ))}
          <div className="mt-5 flex flex-wrap gap-2">
            {['Draft', 'Partial'].includes(batch.status) && (
              <>
                <Button disabled={busy} onClick={() => void run('commit')}>
                  {batch.status === 'Draft'
                    ? 'Start import'
                    : 'Retry failed rows'}
                </Button>
                <Button
                  disabled={busy}
                  variant="outline"
                  onClick={() => void run('cancel')}
                >
                  Cancel pending work
                </Button>
              </>
            )}
            <Button variant="ghost" disabled={busy} onClick={reset}>
              Back to imports
            </Button>
          </div>
        </Panel>
      )}
      <div className="mt-7">
        <h2 className="mb-3 text-sm font-semibold text-slate-800">
          Recent imports
        </h2>
        <FormErrors errors={history.errors} />
        <div className="space-y-2">
          {history.data?.map(item => (
            <button
              type="button"
              key={item.id}
              disabled={busy}
              onClick={() => void open(item)}
              className="flex w-full items-center gap-3 rounded-xl bg-white p-4 text-left shadow-sm ring-1 ring-slate-900/5 hover:bg-slate-50"
            >
              <FileSpreadsheet className="size-5 text-teal-700" />
              <span className="min-w-0 flex-1 truncate text-sm font-medium">
                {item.fileName}
              </span>
              <span className="text-xs text-slate-500">{item.total} rows</span>
              <Badge variant="outline">{item.status}</Badge>
              <ArrowRight className="size-4 text-slate-400" />
            </button>
          ))}
        </div>
      </div>
    </>
  );
}
