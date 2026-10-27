import { useCallback, useEffect, useRef, useState, type DependencyList } from "react";
import { errorMessages } from "@/api/vkfClient";

export interface AsyncState<T> {
	data: T | undefined;
	errors: string[];
	loading: boolean;
	reload: () => void;
	setData: (data: T) => void;
}

/**
 * Loads data when deps change. A response that arrives after a newer request started is
 * dropped, so fast month switching never shows stale numbers. Keeps the previous data
 * while reloading, so screens don't flash empty.
 */
export function useAsync<T>(load: () => Promise<T>, deps: DependencyList): AsyncState<T> {
	const [data, setData] = useState<T>();
	const [errors, setErrors] = useState<string[]>([]);
	const [loading, setLoading] = useState(true);
	const [nonce, setNonce] = useState(0);
	const latest = useRef(0);

	useEffect(() => {
		const request = ++latest.current;
		setLoading(true);
		load()
			.then((result) => {
				if (request !== latest.current) return;
				setData(result);
				setErrors([]);
			})
			.catch((error: unknown) => {
				if (request === latest.current) setErrors(errorMessages(error));
			})
			.finally(() => {
				if (request === latest.current) setLoading(false);
			});
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [...deps, nonce]);

	const reload = useCallback(() => setNonce((n) => n + 1), []);
	return { data, errors, loading, reload, setData };
}
