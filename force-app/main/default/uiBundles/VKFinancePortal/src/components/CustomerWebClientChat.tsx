/**
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * For full license text, see the LICENSE.txt file
 */

import { useEffect } from "react";
import type { CustomerWebClientChatProps, WindowWithCwcProperties } from "../types/chat";

/**
 * React wrapper that embeds the Customer Web Client (Embedded Messaging) chat
 * widget into an external site. It dynamically loads the site's
 * `embeddedservice_bootstrap` script and calls `init` with the org, deployment,
 * site, and SCRT2 configuration. Renders nothing itself — the chat UI is a
 * floating widget injected by the bootstrap script.
 */
export function CustomerWebClientChat({
	orgId,
	deploymentName,
	siteURL,
	scrt2URL,
	language = "en",
	devMode = false,
}: CustomerWebClientChatProps) {
	useEffect(() => {
		if (typeof window === "undefined") return;
		if (
			!orgId ||
			!deploymentName ||
			!siteURL ||
			!scrt2URL ||
			!(orgId.length === 15 || orgId.length === 18)
		) {
			console.warn("[CustomerWebClientChat] missing required config; skipping init");
			return;
		}

		const win = window as WindowWithCwcProperties;
		const bootstrapSrc = `${siteURL}/assets/js/bootstrap.js`;
		const existing = document.querySelector<HTMLScriptElement>(`script[src="${bootstrapSrc}"]`);
		const script: HTMLScriptElement = existing ?? document.createElement("script");

		const init = () => {
			try {
				if (!win.embeddedservice_bootstrap) return;
				win.embeddedservice_bootstrap.settings.language = language;
				if (devMode) win.embeddedservice_bootstrap.settings.devMode = true;
				win.embeddedservice_bootstrap.init(orgId, deploymentName, siteURL, {
					scrt2URL,
				});
			} catch (err) {
				console.error("Error loading Embedded Messaging: ", err);
			}
		};

		if (existing) {
			if (win.embeddedservice_bootstrap) init();
			else existing.addEventListener("load", init, { once: true });
		} else {
			script.type = "text/javascript";
			script.src = bootstrapSrc;
			script.addEventListener("load", init, { once: true });
			document.body.appendChild(script);
		}

		return () => {
			script.removeEventListener("load", init);
		};
	}, [orgId, deploymentName, siteURL, scrt2URL, language, devMode]);

	return null;
}

export default CustomerWebClientChat;
