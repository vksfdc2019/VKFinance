import { useState } from 'react';
import { Link } from 'react-router';
import { ArrowUpRight, Lightbulb, RefreshCw, Sparkles } from 'lucide-react';
import { enhancementsApi, type Insight } from '@/api/enhancements';
import { errorMessages } from '@/api/vkfClient';
import { useLedger } from '@/features/ledger/LedgerContext';
import { useAuth } from '@/features/auth/AuthContext';
import { useAsync } from '@/lib/useAsync';
import { formatMoney } from '@/lib/format';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { FormErrors } from '@/components/forms';
import { Panel, EmptyState } from '@/components/finance/ui';
import { FeatureGate } from './EnhancementsLayout';
import { Intro } from './shared';

export default function InsightsPage() {
  return (
    <FeatureGate feature="INSIGHTS">
      <Insights />
    </FeatureGate>
  );
}
function Insights() {
  const { version, currency } = useLedger();
  const { can } = useAuth();
  const { data, errors, loading, reload } = useAsync(
    () => enhancementsApi.insights(),
    [version]
  );
  const [busy, setBusy] = useState<string>();
  const [actionErrors, setActionErrors] = useState<string[]>([]);
  async function dismiss(insight: Insight, snooze: boolean) {
    setBusy(insight.key);
    setActionErrors([]);
    try {
      await enhancementsApi.dismiss(insight.key, snooze);
      reload();
    } catch (e) {
      setActionErrors(errorMessages(e));
    } finally {
      setBusy(undefined);
    }
  }
  return (
    <>
      <Intro
        eyebrow="A fresh perspective"
        title="Notice the little things"
        description="Understand what is changing, and decide what matters to you. Every suggestion explains its basis and uses only the records you are allowed to see."
      >
        <Button variant="outline" disabled={loading} onClick={reload}>
          <RefreshCw className={loading ? 'animate-spin' : ''} />
          Refresh
        </Button>
      </Intro>
      <FormErrors errors={[...errors, ...actionErrors]} />
      {!data && loading ? (
        <Skeleton className="h-72 rounded-3xl" />
      ) : data?.length === 0 ? (
        <Panel>
          <EmptyState
            icon={<Sparkles />}
            title="Nothing needs your attention right now"
          >
            Insights appear when there is enough spending history or an eligible
            recurring expense to review. Keep recording your everyday
            transactions.
          </EmptyState>
        </Panel>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {data?.map(item => (
            <article
              key={item.key}
              className="overflow-hidden rounded-2xl bg-white dark:bg-slate-900 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10"
            >
              <div
                className={`flex items-center gap-2 px-5 py-3 text-xs font-semibold ${item.severity === 'warning' ? 'bg-amber-50 dark:bg-amber-950/40 text-amber-800 dark:text-amber-200' : 'bg-violet-50 dark:bg-violet-950/40 text-violet-800 dark:text-violet-200'}`}
              >
                <Lightbulb className="size-4" />
                {item.kind}
              </div>
              <div className="p-5">
                <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
                  {item.title}
                </h2>
                <div className="my-5 flex flex-wrap items-end gap-5">
                  <div>
                    <p className="text-xs text-slate-400">
                      {item.baseline != null
                        ? 'Spent this month'
                        : 'Estimated monthly cost'}
                    </p>
                    <p className="mt-1 text-2xl font-semibold">
                      {formatMoney(item.actual, currency)}
                    </p>
                  </div>
                  {item.baseline != null && (
                    <div>
                      <p className="text-xs text-slate-400">Expected pace</p>
                      <p className="mt-1 text-lg font-medium text-slate-500 dark:text-slate-400">
                        {formatMoney(item.baseline, currency)}
                      </p>
                    </div>
                  )}
                </div>
                <p className="text-sm leading-relaxed text-slate-500 dark:text-slate-400">
                  {item.explanation}
                </p>
                <div className="mt-5 flex flex-wrap items-center justify-between gap-2 border-t border-slate-100 dark:border-slate-800 pt-4">
                  {!item.link.startsWith('/recurring') ||
                  can('RECURRING:READ') ? (
                    <Link
                      to={item.link}
                      className="inline-flex items-center gap-1 text-sm font-semibold text-brand-800 dark:text-brand-200"
                    >
                      Explore the details
                      <ArrowUpRight className="size-4" />
                    </Link>
                  ) : (
                    <span className="text-xs text-slate-400">
                      Ask your Family Admin to review
                    </span>
                  )}
                  <div className="flex gap-1">
                    <Button
                      size="xs"
                      variant="ghost"
                      disabled={!!busy}
                      onClick={() => void dismiss(item, true)}
                    >
                      Snooze 7 days
                    </Button>
                    <Button
                      size="xs"
                      variant="ghost"
                      disabled={!!busy}
                      onClick={() => void dismiss(item, false)}
                    >
                      Dismiss
                    </Button>
                  </div>
                </div>
              </div>
            </article>
          ))}
        </div>
      )}
      <p className="mt-6 text-xs leading-relaxed text-slate-400">
        Insights use transparent rules, not an external AI service. A recurring
        expense is a suggestion to review, not evidence of an unused
        subscription. No payment, cancellation or account change happens
        automatically.
      </p>
    </>
  );
}
