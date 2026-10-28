import { createContext, useContext, useState, type FormEvent } from 'react';
import { Link, NavLink, Outlet } from 'react-router';
import {
  ArrowRight,
  Camera,
  Check,
  CloudUpload,
  Download,
  Lightbulb,
  LockKeyhole,
  Settings2,
  ShieldCheck,
  Sparkles,
  Sprout,
  UsersRound,
  type LucideIcon,
} from 'lucide-react';
import {
  enhancementsApi,
  type EnhancementSettings,
  type Feature,
} from '@/api/enhancements';
import { useAuth } from '@/features/auth/AuthContext';
import { useAsync } from '@/lib/useAsync';
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
import { FormErrors } from '@/components/forms';
import { Skeleton } from '@/components/ui/skeleton';
import { errorMessages } from '@/api/vkfClient';
import { cn } from '@/lib/utils';

export const modules: {
  key: Feature;
  path: string;
  title: string;
  description: string;
  icon: LucideIcon;
  permission?: string;
  gradient: string;
}[] = [
  {
    key: 'IMPORTS',
    path: 'imports',
    title: 'Statement import',
    description:
      'From bank statement to an organized ledger, with a review before anything is recorded.',
    icon: CloudUpload,
    permission: 'IMPORTS:READ',
    gradient: 'from-sky-50 to-blue-50',
  },
  {
    key: 'RECEIPTS',
    path: 'receipts',
    title: 'Receipt collection',
    description:
      'Keep the photo and the payment together. Private, searchable, and easy to find.',
    icon: Camera,
    permission: 'RECEIPTS:READ',
    gradient: 'from-violet-50 to-fuchsia-50',
  },
  {
    key: 'REQUESTS',
    path: 'requests',
    title: 'Spend requests',
    description:
      'A little independence, with a parent in the loop. Ask, discuss, then decide.',
    icon: UsersRound,
    permission: 'REQUESTS:READ',
    gradient: 'from-amber-50 to-orange-50',
  },
  {
    key: 'GOALS',
    path: 'goals',
    title: 'Savings goals',
    description:
      'Give your savings a purpose. Watch a holiday, a home, or a dream get closer.',
    icon: Sprout,
    permission: 'GOALS:READ',
    gradient: 'from-emerald-50 to-teal-50',
  },
  {
    key: 'INSTALL',
    path: 'install',
    title: 'Finance, on your phone',
    description:
      'Keep your family’s finances one tap away, with a home-screen shortcut.',
    icon: Download,
    gradient: 'from-cyan-50 to-sky-50',
  },
  {
    key: 'INSIGHTS',
    path: 'insights',
    title: 'Smart insights',
    description:
      'A fresh perspective on spending patterns, with clear reasons behind every suggestion.',
    icon: Lightbulb,
    permission: 'INSIGHTS:READ',
    gradient: 'from-rose-50 to-amber-50',
  },
];

const SettingsContext = createContext<{
  settings: EnhancementSettings;
  reload: () => void;
} | null>(null);
export function useEnhancements() {
  const value = useContext(SettingsContext);
  if (!value) throw new Error('Enhancement context missing');
  return value;
}

export default function EnhancementsLayout() {
  const { profile, can } = useAuth();
  const { data, loading, errors, reload } = useAsync(
    () => enhancementsApi.settings(),
    [profile?.userId]
  );
  if (!data)
    return (
      <>
        <FormErrors errors={errors} />
        {loading && <Skeleton className="h-80 rounded-3xl" />}
      </>
    );
  return (
    <SettingsContext.Provider value={{ settings: data, reload }}>
      <div className="mb-6 flex flex-wrap items-center gap-2 text-sm">
        <Link className="font-semibold text-teal-800" to="/enhancements">
          Discover
        </Link>
        <span className="text-slate-300">/</span>
        <nav aria-label="Enhancements" className="flex flex-wrap gap-1">
          {modules
            .filter(m => !m.permission || can(m.permission))
            .filter(m => data.enabled.includes(m.key))
            .map(m => (
              <NavLink
                key={m.key}
                to={m.path}
                className={({ isActive }) =>
                  cn(
                    'rounded-full px-3 py-1.5 text-xs transition-colors',
                    isActive
                      ? 'bg-teal-100 font-semibold text-teal-900'
                      : 'text-slate-500 hover:bg-white'
                  )
                }
              >
                {m.title}
              </NavLink>
            ))}
        </nav>
      </div>
      <Outlet />
    </SettingsContext.Provider>
  );
}

export function FeatureGate({
  feature,
  children,
}: {
  feature: Feature;
  children: React.ReactNode;
}) {
  const { settings } = useEnhancements();
  const { can } = useAuth();
  const item = modules.find(m => m.key === feature)!;
  if (
    !settings.enabled.includes(feature) ||
    (item.permission && !can(item.permission))
  )
    return (
      <div className="rounded-3xl bg-white p-12 text-center shadow-sm ring-1 ring-slate-900/5">
        <LockKeyhole className="mx-auto mb-4 size-10 text-teal-600" />
        <h1 className="text-xl font-semibold">This feature is not available</h1>
        <p className="mt-2 text-sm text-slate-500">
          Your Family Admin can enable optional features. Your role also
          determines access.
        </p>
        <Button asChild variant="outline" className="mt-6">
          <Link to="/enhancements">Back to Discover</Link>
        </Button>
      </div>
    );
  return children;
}

export function EnhancementsHome() {
  const { settings, reload } = useEnhancements();
  const { can } = useAuth();
  const [configure, setConfigure] = useState(false);
  return (
    <>
      <section className="relative mb-8 overflow-hidden rounded-3xl bg-gradient-to-br from-teal-950 via-teal-900 to-emerald-800 p-7 text-white shadow-lg shadow-teal-950/10 sm:p-10">
        <div
          aria-hidden
          className="pointer-events-none absolute -right-16 -top-28 size-80 rounded-full border-[40px] border-white/5"
        />
        <div className="relative max-w-xl">
          <span className="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-xs font-medium text-teal-100">
            <Sparkles className="size-3.5" /> More possibilities, at your pace
          </span>
          <h1 className="mt-5 text-3xl font-semibold tracking-tight sm:text-4xl">
            Small steps.
            <br />A brighter financial future.
          </h1>
          <p className="mt-4 text-sm leading-relaxed text-teal-100/85">
            Thoughtful tools for the moments beyond everyday bookkeeping. Choose
            what works for your family, and make it your own.
          </p>
          {settings.canManage && (
            <Button
              className="mt-6 bg-white text-teal-950 hover:bg-teal-50"
              onClick={() => setConfigure(true)}
            >
              <Settings2 />
              Choose your family’s features
            </Button>
          )}
        </div>
      </section>
      <div className="mb-5 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-slate-900">
          Explore your possibilities
        </h2>
        <span className="inline-flex items-center gap-1.5 text-xs text-slate-500">
          <ShieldCheck className="size-4 text-teal-600" /> Family-scoped access
        </span>
      </div>
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {modules
          .filter(m => !m.permission || can(m.permission))
          .map(({ key, path, title, description, icon: Icon, gradient }) => {
            const active = settings.enabled.includes(key);
            return (
              <article
                key={key}
                className="group flex flex-col overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-900/5 transition-shadow hover:shadow-md"
              >
                <div
                  className={cn(
                    'flex h-28 items-center justify-between bg-gradient-to-br px-6',
                    gradient
                  )}
                >
                  <div className="flex size-14 items-center justify-center rounded-2xl bg-white/85 text-teal-800 shadow-sm">
                    <Icon className="size-7" />
                  </div>
                  <span
                    className={cn(
                      'rounded-full px-2.5 py-1 text-[11px] font-semibold',
                      active
                        ? 'bg-white/90 text-teal-800'
                        : 'bg-white/70 text-slate-500'
                    )}
                  >
                    {active ? 'Enabled' : 'Optional'}
                  </span>
                </div>
                <div className="flex flex-1 flex-col p-6">
                  <h3 className="text-base font-semibold text-slate-900">
                    {title}
                  </h3>
                  <p className="mt-2 flex-1 text-sm leading-relaxed text-slate-500">
                    {description}
                  </p>
                  {active ? (
                    <Link
                      to={path}
                      className="mt-5 inline-flex items-center gap-2 text-sm font-semibold text-teal-800"
                    >
                      Explore{' '}
                      <ArrowRight className="size-4 transition-transform group-hover:translate-x-1" />
                    </Link>
                  ) : (
                    <p className="mt-5 text-xs text-slate-400">
                      {settings.canManage
                        ? 'Enable in family feature settings'
                        : 'Ask your Family Admin to enable'}
                    </p>
                  )}
                </div>
              </article>
            );
          })}
      </div>
      {configure && (
        <ConfigureDialog
          onClose={() => setConfigure(false)}
          onSaved={() => {
            setConfigure(false);
            reload();
          }}
        />
      )}
    </>
  );
}

function ConfigureDialog({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const { settings } = useEnhancements();
  const { profile } = useAuth();
  const [enabled, setEnabled] = useState<Feature[]>(settings.enabled);
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [errors, setErrors] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      await enhancementsApi.configure(enabled, password, code || undefined);
      onSaved();
    } catch (e) {
      setErrors(errorMessages(e));
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
      <DialogContent className="max-h-[90svh] overflow-auto">
        <DialogHeader>
          <DialogTitle>Your family’s toolkit</DialogTitle>
          <DialogDescription>
            Enable features as you need them. Turning one off preserves its
            records and closes its API access.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-4">
          <FormErrors errors={errors} />
          <div className="grid gap-2">
            {modules.map(m => (
              <label
                key={m.key}
                className="flex cursor-pointer items-center gap-3 rounded-xl border border-slate-200 p-3"
              >
                <input
                  type="checkbox"
                  className="size-4 accent-teal-700"
                  checked={enabled.includes(m.key)}
                  onChange={e =>
                    setEnabled(
                      e.target.checked
                        ? [...enabled, m.key]
                        : enabled.filter(k => k !== m.key)
                    )
                  }
                />
                <m.icon className="size-4 text-teal-700" />
                <span className="text-sm font-medium">{m.title}</span>
                {enabled.includes(m.key) && (
                  <Check className="ml-auto size-4 text-teal-600" />
                )}
              </label>
            ))}
          </div>
          <label className="grid gap-1.5 text-sm font-medium">
            Your current password
            <Input
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={e => setPassword(e.target.value)}
            />
          </label>
          {profile?.mfaEnabled && (
            <label className="grid gap-1.5 text-sm font-medium">
              Authenticator or recovery code
              <Input
                autoComplete="one-time-code"
                value={code}
                onChange={e => setCode(e.target.value)}
                required
              />
            </label>
          )}
          <DialogFooter>
            <Button
              variant="outline"
              type="button"
              onClick={onClose}
              disabled={busy}
            >
              Cancel
            </Button>
            <Button disabled={busy} type="submit">
              {busy ? 'Saving…' : 'Save preferences'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
