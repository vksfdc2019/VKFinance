import { WalletCards } from "lucide-react";

export function BrandMark() {
	return (
		<span className="inline-flex items-center gap-2 font-semibold text-slate-900 dark:text-slate-100">
			<span className="flex size-8 items-center justify-center rounded-lg bg-brand-800 text-white">
				<WalletCards className="size-4" aria-hidden="true" />
			</span>
			VK Finance
		</span>
	);
}
