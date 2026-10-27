import { beforeEach, describe, expect, it, vi } from "vitest";

const fetchMock = vi.fn();
vi.mock("@salesforce/platform-sdk", () => ({ createDataSDK: async () => ({ fetch: fetchMock }) }));

import { ApiError, SESSION_EXPIRED_EVENT, sessionStore, vkf } from "./vkfClient";
import { safeNext } from "@/features/auth/RouteGuards";

function respond(status: number, body?: unknown) {
	return new Response(body === undefined ? null : JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

describe("vkf client", () => {
	beforeEach(() => {
		fetchMock.mockReset();
		sessionStorage.clear();
	});

	it("sends the session token header and parses JSON", async () => {
		sessionStore.set("abc123");
		fetchMock.mockResolvedValue(respond(200, { ok: true }));
		await expect(vkf("GET", "/profile/me")).resolves.toEqual({ ok: true });
		const [url, init] = fetchMock.mock.calls[0];
		expect(url).toBe("/services/apexrest/vkf/v1/profile/me");
		expect(init.headers["X-VKF-Session"]).toBe("abc123");
		expect(init.body).toBeUndefined();
	});

	it("clears the token and announces expiry on SESSION_EXPIRED", async () => {
		sessionStore.set("stale");
		const listener = vi.fn();
		window.addEventListener(SESSION_EXPIRED_EVENT, listener);
		fetchMock.mockResolvedValue(respond(401, { code: "SESSION_EXPIRED" }));
		await expect(vkf("GET", "/auth/session")).rejects.toBeInstanceOf(ApiError);
		expect(sessionStore.get()).toBeNull();
		expect(listener).toHaveBeenCalledOnce();
		window.removeEventListener(SESSION_EXPIRED_EVENT, listener);
	});

	it("keeps server messages for failed sign-in without firing expiry", async () => {
		const listener = vi.fn();
		window.addEventListener(SESSION_EXPIRED_EVENT, listener);
		fetchMock.mockResolvedValue(respond(401, { code: "INVALID_CREDENTIALS", errors: ["Invalid username or password."] }));
		const error = (await vkf("POST", "/auth/login", { username: "a", password: "b" }).catch((e: unknown) => e)) as ApiError;
		expect(error).toBeInstanceOf(ApiError);
		expect(error.code).toBe("INVALID_CREDENTIALS");
		expect(error.errors).toEqual(["Invalid username or password."]);
		expect(listener).not.toHaveBeenCalled();
		expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ username: "a", password: "b" });
		window.removeEventListener(SESSION_EXPIRED_EVENT, listener);
	});

	it("hides platform error details behind a friendly message", async () => {
		fetchMock.mockResolvedValue(respond(500, [{ errorCode: "APEX_ERROR", message: "System.NullPointerException at line 4" }]));
		const error = (await vkf("GET", "/family/members").catch((e: unknown) => e)) as ApiError;
		expect(error.code).toBe("APEX_ERROR");
		expect(error.errors[0]).not.toContain("NullPointer");
	});

	it("returns null for 204 responses", async () => {
		fetchMock.mockResolvedValue(new Response(null, { status: 204 }));
		await expect(vkf("POST", "/auth/logout", {})).resolves.toBeNull();
	});
});

describe("safeNext", () => {
	it("only allows in-app relative paths", () => {
		expect(safeNext("/family")).toBe("/family");
		expect(safeNext("//evil.example")).toBe("/");
		expect(safeNext("https://evil.example")).toBe("/");
		expect(safeNext("/\\evil.example")).toBe("/");
		expect(safeNext(null)).toBe("/");
	});
});
