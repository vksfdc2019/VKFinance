import { useLayoutEffect, useState, type RefObject } from "react";

/** The element's content width, kept current as it resizes. */
export function useWidth(ref: RefObject<HTMLElement | null>): number {
	const [width, setWidth] = useState(0);
	useLayoutEffect(() => {
		const el = ref.current;
		if (!el) return;
		const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
		observer.observe(el);
		setWidth(el.getBoundingClientRect().width);
		return () => observer.disconnect();
	}, [ref]);
	return width;
}
