/**
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * For full license text, see the LICENSE.txt file
 */

import CustomerWebClientChat from "../components/CustomerWebClientChat";

export default function TestChatPage() {
	return (
		<div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
			<div className="text-center">
				<h1 className="text-4xl font-bold text-gray-900 mb-4">Chat</h1>
				<p className="text-lg text-gray-600 mb-8">
					Welcome to your Customer Web Client chat application.
				</p>
			</div>
			<CustomerWebClientChat
				orgId="<ORG_ID_15_OR_18_CHAR_00D...>"
				deploymentName="<EMBEDDED_SERVICE_DEPLOYMENT_NAME>"
				siteURL="<SITE_URL>"
				scrt2URL="<SCRT2_URL>"
			/>
		</div>
	);
}
