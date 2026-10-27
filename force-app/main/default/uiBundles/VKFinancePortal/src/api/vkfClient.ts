/**
 * The only way the portal talks to Salesforce: Apex REST under /vkf/v1, called as the
 * site guest user through the Data SDK. Adds the VK session token to every request
 * and turns a server-side SESSION_EXPIRED into a single app-wide event.
 */
import { createDataSDK } from "@salesforce/platform-sdk";

const TOKEN_KEY = "vkf.session";
const API_BASE = "/services/apexrest/vkf/v1";
export const SESSION_EXPIRED_EVENT = "vkf:session-expired";

export class ApiError extends Error {
	readonly status: number;
	readonly code: string;
	readonly errors: string[];

	constructor(status: number, code: string, errors: string[]) {
		super(errors[0] ?? code);
		this.status = status;
		this.code = code;
		this.errors = errors;
	}
}

/** sessionStorage keeps the token per tab and drops it when the browser closes. */
export const sessionStore = {
	get(): string | null {
		try {
			return sessionStorage.getItem(TOKEN_KEY);
		} catch {
			return null;
		}
	},
	set(token: string) {
		try {
			sessionStorage.setItem(TOKEN_KEY, token);
		} catch {
			// Storage unavailable (private mode): the session lasts until the page reloads.
		}
	},
	clear() {
		try {
			sessionStorage.removeItem(TOKEN_KEY);
		} catch {
			// Nothing stored.
		}
	},
};

type Method = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

let sdkPromise: ReturnType<typeof createDataSDK> | null = null;

function parse(text: string): unknown {
	try {
		return JSON.parse(text);
	} catch {
		return null;
	}
}

function describeFailure(status: number, data: unknown): { code: string; errors: string[] } {
	if (data && typeof data === "object" && !Array.isArray(data)) {
		const body = data as { code?: unknown; errors?: unknown };
		const errors = Array.isArray(body.errors) ? body.errors.map(String) : [];
		return { code: String(body.code ?? `HTTP_${status}`), errors: errors.length ? errors : [fallbackMessage(status)] };
	}
	if (Array.isArray(data)) {
		// Platform-level errors (not from VK code) come back as [{ errorCode, message }].
		const first = data[0] as { errorCode?: string; message?: string } | undefined;
		return { code: first?.errorCode ?? `HTTP_${status}`, errors: [fallbackMessage(status)] };
	}
	return { code: `HTTP_${status}`, errors: [fallbackMessage(status)] };
}

function fallbackMessage(status: number): string {
	if (status === 401) return "Your session has ended. Please sign in again.";
	if (status === 403) return "You don't have access to do that.";
	if (status === 404) return "We couldn't find that.";
	if (status === 429) return "Too many attempts. Wait a few minutes and try again.";
	return "Something went wrong. Please try again.";
}

export async function vkf<T>(method: Method, path: string, body?: unknown): Promise<T> {
	sdkPromise ??= createDataSDK();
	const sdk = await sdkPromise;
	const token = sessionStore.get();
	const headers: Record<string, string> = { Accept: "application/json" };
	if (body !== undefined) headers["Content-Type"] = "application/json";
	if (token) headers["X-VKF-Session"] = token;

	const response = await sdk.fetch!(`${API_BASE}${path}`, {
		method,
		headers,
		body: body === undefined ? undefined : JSON.stringify(body),
	});
	const text = response.status === 204 ? "" : await response.text();
	const data = text ? parse(text) : null;

	if (!response.ok) {
		const { code, errors } = describeFailure(response.status, data);
		if (response.status === 401 && code === "SESSION_EXPIRED" && token) {
			sessionStore.clear();
			window.dispatchEvent(new Event(SESSION_EXPIRED_EVENT));
		}
		throw new ApiError(response.status, code, errors);
	}
	return data as T;
}

export function errorMessages(error: unknown): string[] {
	if (error instanceof ApiError) return error.errors;
	return ["Something went wrong. Please check your connection and try again."];
}
