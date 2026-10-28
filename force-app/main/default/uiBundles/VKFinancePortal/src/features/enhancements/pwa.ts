/** Scope install assets to the application path; never take control of a parent Salesforce site. */
export function appBasePath(pathname: string, configured?: string): string {
  const value = configured || pathname.split('/enhancements')[0] || '/';
  if (!value.startsWith('/') || value.startsWith('//') || /[?#]/.test(value))
    throw new Error('The application path is invalid.');
  return value.replace(/\/+$/, '') + '/';
}

export async function prepareInstall(basePath: string): Promise<void> {
  if (!window.isSecureContext || !('serviceWorker' in navigator))
    throw new Error(
      'This browser does not support the install setup. Use its Add to Home Screen or shortcut option.'
    );
  const base = new URL(basePath, window.location.origin);
  // Salesforce serves manifest files with a generic MIME type. Chromium parses
  // this valid JSON, so validate its contents and same-app URLs directly.
  const manifest = new URL('manifest.json', base);
  const worker = new URL('vkf-sw.js', base);
  const response = await fetch(manifest, {
    cache: 'no-store',
    credentials: 'omit',
  });
  if (!response.ok)
    throw new Error(
      'Install assets are not available at this hosting path. Your administrator needs to verify the published manifest and service-worker URLs. You can still use the normal portal.'
    );
  let data: { name?: string; start_url?: string } | null;
  try {
    data = await response.json();
  } catch {
    throw new Error(
      'The published install manifest is not valid JSON. Ask your administrator to check the hosting path.'
    );
  }
  if (
    !data ||
    typeof data !== 'object' ||
    data.name !== 'VK Finance' ||
    !data.start_url ||
    new URL(data.start_url, manifest).origin !== location.origin ||
    !new URL(data.start_url, manifest).pathname.startsWith(base.pathname)
  )
    throw new Error(
      'The published install manifest has an unexpected application scope.'
    );
  const script = await fetch(worker, {
    cache: 'no-store',
    credentials: 'omit',
  });
  if (
    !script.ok ||
    !/(?:javascript|ecmascript)/i.test(script.headers.get('content-type') ?? '')
  )
    throw new Error(
      'The service-worker script is not served as JavaScript at this application path. Ask your administrator to check hosting.'
    );
  const offline = await fetch(new URL('vkf-offline.html', base), {
    cache: 'no-store',
    credentials: 'omit',
  });
  if (
    !offline.ok ||
    !(await offline.text()).includes('name="vkf-offline" content="public-only"')
  )
    throw new Error(
      'The public offline notice is unavailable at this hosting path. Ask your administrator to check the published assets.'
    );
  let link = document.querySelector<HTMLLinkElement>('link[data-vkf-manifest]');
  if (!link) {
    link = document.createElement('link');
    link.rel = 'manifest';
    link.dataset.vkfManifest = 'true';
    document.head.append(link);
  }
  link.href = manifest.href;
  await navigator.serviceWorker.register(worker.href, {
    scope: base.pathname,
    updateViaCache: 'none',
  });
}
