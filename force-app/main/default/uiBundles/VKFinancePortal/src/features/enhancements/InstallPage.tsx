import { useEffect, useState } from 'react';
import {
  CheckCircle2,
  Download,
  Globe,
  ShieldCheck,
  Smartphone,
  WifiOff,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Panel } from '@/components/finance/ui';
import { FormErrors } from '@/components/forms';
import { FeatureGate } from './EnhancementsLayout';
import { Intro } from './shared';
import { appBasePath, prepareInstall } from './pwa';

interface InstallPrompt extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}
export default function InstallPage() {
  return (
    <FeatureGate feature="INSTALL">
      <Install />
    </FeatureGate>
  );
}
function Install() {
  const [prompt, setPrompt] = useState<InstallPrompt>();
  const [busy, setBusy] = useState(false);
  const [prepared, setPrepared] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [installed, setInstalled] = useState(
    () =>
      window.matchMedia('(display-mode: standalone)').matches ||
      !!(navigator as Navigator & { standalone?: boolean }).standalone
  );
  const [online, setOnline] = useState(navigator.onLine);
  useEffect(() => {
    const offer = (e: Event) => {
      e.preventDefault();
      setPrompt(e as InstallPrompt);
    };
    const done = () => {
      setInstalled(true);
      setPrompt(undefined);
    };
    const status = () => setOnline(navigator.onLine);
    window.addEventListener('beforeinstallprompt', offer);
    window.addEventListener('appinstalled', done);
    window.addEventListener('online', status);
    window.addEventListener('offline', status);
    return () => {
      window.removeEventListener('beforeinstallprompt', offer);
      window.removeEventListener('appinstalled', done);
      window.removeEventListener('online', status);
      window.removeEventListener('offline', status);
    };
  }, []);
  async function enable() {
    setBusy(true);
    setErrors([]);
    try {
      const configured = (globalThis as { SFDC_ENV?: { basePath?: string } })
        .SFDC_ENV?.basePath;
      await prepareInstall(appBasePath(location.pathname, configured));
      setPrepared(true);
    } catch (e) {
      setErrors([
        e instanceof Error
          ? e.message
          : 'Install setup is unavailable in this browser.',
      ]);
    } finally {
      setBusy(false);
    }
  }
  async function install() {
    if (!prompt) return;
    setBusy(true);
    try {
      await prompt.prompt();
      const result = await prompt.userChoice;
      if (result.outcome === 'accepted') setInstalled(true);
      setPrompt(undefined);
    } catch {
      setErrors([
        'The installation could not finish. Try your browser’s installation menu.',
      ]);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Intro
        eyebrow="Your finances, one tap away"
        title="Make room on your home screen"
        description="A familiar place for your family’s finances, without searching through browser tabs. Keep using the same account and the same secure sign-in."
      />
      <div className="grid items-start gap-6 lg:grid-cols-[1fr_1.1fr]">
        <div className="relative flex min-h-96 items-center justify-center overflow-hidden rounded-3xl bg-gradient-to-br from-teal-900 via-teal-800 to-emerald-700 p-8">
          <div
            aria-hidden
            className="absolute size-80 rounded-full border-[35px] border-white/5"
          />
          <div className="relative w-56 rounded-[2.5rem] border-[7px] border-teal-950 bg-slate-50 px-4 pb-6 pt-3 shadow-2xl">
            <div className="mx-auto mb-7 h-4 w-20 rounded-full bg-teal-950" />
            <div className="mx-auto flex size-16 items-center justify-center rounded-2xl bg-teal-800 text-xl font-bold text-white shadow-lg shadow-teal-800/20">
              VK
            </div>
            <p className="mt-3 text-center text-sm font-semibold text-slate-800">
              VK Finance
            </p>
            <div className="mt-7 rounded-2xl bg-white p-4 shadow-sm">
              <span className="text-[10px] text-slate-400">
                A little clarity, every day
              </span>
              <p className="mt-2 text-lg font-semibold text-teal-900">
                Your family.
                <br />
                Your future.
              </p>
              <div className="mt-4 h-2 rounded-full bg-teal-100">
                <div className="h-2 w-2/3 rounded-full bg-teal-600" />
              </div>
            </div>
          </div>
        </div>
        <Panel
          title={installed ? 'You’re already at home' : 'Keep VK Finance close'}
        >
          <FormErrors errors={errors} />
          <div className="space-y-5">
            {[
              [
                Smartphone,
                'Built for your phone',
                'A home-screen entry and a focused app window on supported browsers.',
              ],
              [
                ShieldCheck,
                'The same secure access',
                'Installation keeps your existing sign-in, MFA and family permissions.',
              ],
              [
                Globe,
                'Connected when it matters',
                'Financial pages and changes require the network. Account data and receipt photos are never stored in the offline cache.',
              ],
            ].map(([Icon, title, description]) => {
              const Component = Icon as typeof Smartphone;
              return (
                <div key={String(title)} className="flex gap-3">
                  <span className="mt-0.5 rounded-xl bg-teal-50 p-2.5 text-teal-700">
                    <Component className="size-5" />
                  </span>
                  <div>
                    <h2 className="text-sm font-semibold">{String(title)}</h2>
                    <p className="mt-1 text-sm leading-relaxed text-slate-500">
                      {String(description)}
                    </p>
                  </div>
                </div>
              );
            })}
          </div>
          <div className="mt-7 border-t border-slate-100 pt-5">
            {!online && (
              <p className="mb-4 flex items-center gap-2 text-sm text-amber-800">
                <WifiOff className="size-4" />
                Reconnect before setting up installation.
              </p>
            )}
            {installed ? (
              <p className="flex items-center gap-2 text-sm font-semibold text-teal-800">
                <CheckCircle2 className="size-5" />
                Installed on this device
              </p>
            ) : prompt ? (
              <Button disabled={busy || !online} onClick={() => void install()}>
                <Download />
                Install VK Finance
              </Button>
            ) : (
              <>
                <Button
                  disabled={busy || !online || prepared}
                  onClick={() => void enable()}
                >
                  <Download />
                  {busy
                    ? 'Checking browser support…'
                    : prepared
                      ? 'Install setup ready'
                      : 'Set up home-screen installation'}
                </Button>
                <p className="mt-4 text-xs leading-relaxed text-slate-500">
                  On iPhone or iPad, open the portal in Safari, use Share, then
                  Add to Home Screen. On Android or desktop, look for Install
                  app in the browser menu. Availability depends on the published
                  site and browser.
                </p>
              </>
            )}
          </div>
        </Panel>
      </div>
    </>
  );
}
