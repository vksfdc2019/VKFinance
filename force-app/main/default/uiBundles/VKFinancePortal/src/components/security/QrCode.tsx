import { useMemo } from "react";
import QRCode from "qrcode";

/**
 * A QR code drawn as one inline SVG path (no image URL, so it works under the site's CSP).
 * Dark modules on white with the standard four-module quiet zone, so any phone camera reads it.
 */
export function QrCode({ text, size = 200, label }: { text: string; size?: number; label: string }) {
	const { path, count } = useMemo(() => {
		const qr = QRCode.create(text, { errorCorrectionLevel: "M" });
		const n = qr.modules.size;
		let d = "";
		for (let row = 0; row < n; row++) {
			for (let col = 0; col < n; col++) {
				if (qr.modules.get(row, col)) d += `M${col + 4} ${row + 4}h1v1h-1z`;
			}
		}
		return { path: d, count: n + 8 };
	}, [text]);

	return (
		<svg width={size} height={size} viewBox={`0 0 ${count} ${count}`} role="img" aria-label={label} shapeRendering="crispEdges" className="rounded-xl">
			<rect width={count} height={count} fill="#ffffff" />
			<path d={path} fill="#0f172a" />
		</svg>
	);
}
