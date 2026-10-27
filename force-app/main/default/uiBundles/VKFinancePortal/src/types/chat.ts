/**
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * For full license text, see the LICENSE.txt file
 */

/** Shape of the Embedded Messaging bootstrap global injected by the site's bootstrap.js. */
export interface WindowWithCwcProperties extends Window {
	embeddedservice_bootstrap?: {
		settings: {
			language: string;
			devMode?: boolean;
		};
		init: (
			orgId: string,
			deploymentName: string,
			siteURL: string,
			options: { scrt2URL: string },
		) => void;
	};
}

export interface CustomerWebClientChatProps {
	/** The organization id (15- or 18-char Salesforce id starting with `00D`). */
	orgId: string;
	/** The Embedded Service deployment / channel name the agent is connected to. */
	deploymentName: string;
	/** The ESW site URL. Usually contains `ESW` and the deployment name. */
	siteURL: string;
	/** The SCRT2 (Service Cloud Real-Time) chat service URL. Usually contains `scrt`. */
	scrt2URL: string;
	/** Optional chat language. Defaults to `"en"`. */
	language?: string;
	/** Optional. Enables Embedded Messaging dev mode. Defaults to `false`. */
	devMode?: boolean;
}
