import { useEffect, useState } from "react";
import { createDataSDK } from "@salesforce/platform-sdk";

type PingResult = {
	status: string;
	serverTime: string;
	sessionHeaderReceived: boolean;
	userType: string;
};

// Phase 0 spike: proves a guest visitor can call VK Finance Apex REST through the site
// and that the custom session header reaches Apex. Replaced by the dashboard in Phase 1.
export default function HomePage() {
	const [result, setResult] = useState<PingResult | null>(null);
	const [error, setError] = useState<string | null>(null);

	useEffect(() => {
		(async () => {
			try {
				const sdk = await createDataSDK();
				const response = await sdk.fetch!("/services/apexrest/vkf/v1/ping", {
					method: "GET",
					headers: { Accept: "application/json", "X-VKF-Session": "phase0-spike" },
				});
				if (!response.ok) {
					throw new Error(`HTTP ${response.status}`);
				}
				setResult((await response.json()) as PingResult);
			} catch (err) {
				setError(err instanceof Error ? err.message : String(err));
			}
		})();
	}, []);

	return (
		<div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
			<h1 className="text-2xl font-bold mb-2">VK Finance</h1>
			<p className="text-gray-600 mb-6">Phase 0 connectivity check</p>
			{!result && !error && <p>Calling /vkf/v1/ping…</p>}
			{error && <p className="text-red-700">Ping failed: {error}</p>}
			{result && (
				<pre className="bg-gray-100 rounded p-4 text-sm" data-testid="ping-result">
					{JSON.stringify(result, null, 2)}
				</pre>
			)}
		</div>
	);
}
