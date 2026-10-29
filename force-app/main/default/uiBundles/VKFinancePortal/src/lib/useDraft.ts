import { useCallback, useState } from "react";

/**
 * An editable copy of a value that starts over whenever the value itself changes (for example
 * after a save brings back the server's version). No effect needed, so no extra render.
 * The setter changes when the starting value does, so list it in hook dependencies.
 */
export function useDraft<T>(start: T): [T, (next: T) => void] {
	const [state, setState] = useState({ start, value: start });
	const value = Object.is(state.start, start) ? state.value : start;
	const set = useCallback((next: T) => setState({ start, value: next }), [start]);
	return [value, set];
}
