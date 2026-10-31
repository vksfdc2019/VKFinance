/**
 * Owner Workspace helpers shared by every vkfOwner* component: formatting, month maths,
 * Apex error text and safe per-viewer storage. No UI here.
 */

const formatters = new Map();

function formatter(currencyCode, compact) {
  const key = `${currencyCode}|${compact}`;
  if (!formatters.has(key)) {
    formatters.set(
      key,
      new Intl.NumberFormat("en-IN", {
        style: "currency",
        currency: currencyCode || "INR",
        maximumFractionDigits: compact ? 1 : 0,
        notation: compact ? "compact" : "standard"
      })
    );
  }
  return formatters.get(key);
}

/** ₹1,23,456 (or ₹1.2L with compact). Non-numbers show as ₹0. */
export function money(value, currencyCode, compact = false) {
  const n = Number(value);
  return formatter(currencyCode, compact).format(Number.isFinite(n) ? n : 0);
}

/** "+₹500" / "−₹500" for ledger rows. */
export function signedMoney(value, isDebit, currencyCode) {
  return `${isDebit ? "−" : "+"}${money(Math.abs(Number(value) || 0), currencyCode)}`;
}

export function percent(value, digits = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? `${n.toFixed(digits)}%` : "—";
}

/** Dates arrive as 'YYYY-MM-DD'; parse as local dates so the day never shifts. */
export function parseDate(value) {
  if (!value) {
    return null;
  }
  const [y, m, d] = String(value).substring(0, 10).split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function shortDate(value) {
  const d = parseDate(value);
  return d
    ? d.toLocaleDateString("en-IN", { day: "numeric", month: "short" })
    : "";
}

export function longDate(value) {
  const d = parseDate(value);
  return d
    ? d.toLocaleDateString("en-IN", {
        weekday: "short",
        day: "numeric",
        month: "short",
        year: "numeric"
      })
    : "";
}

export function isoToday() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export function currentMonth() {
  return isoToday().substring(0, 7);
}

/** shiftMonth('2026-01', -1) === '2025-12' */
export function shiftMonth(key, delta) {
  const [y, m] = (key || currentMonth()).split("-").map(Number);
  const d = new Date(y, m - 1 + delta, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

export function monthLabel(key, short = false) {
  const [y, m] = (key || currentMonth()).split("-").map(Number);
  return new Date(y, m - 1, 1).toLocaleDateString("en-IN", {
    month: short ? "short" : "long",
    year: "numeric"
  });
}

export function initials(name) {
  return (name || "?")
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0].toUpperCase())
    .join("");
}

/** The message an Apex AuraHandledException (or a network failure) carries. */
export function errorMessage(error) {
  if (!error) {
    return "Something went wrong.";
  }
  if (Array.isArray(error.body)) {
    return error.body.map((e) => e.message).join(" ");
  }
  return error.body?.message || error.message || "Something went wrong.";
}

/** Parses the controller's JSON strings; an empty response becomes the fallback. */
export function parse(json, fallback = null) {
  if (!json) {
    return fallback;
  }
  try {
    return JSON.parse(json);
  } catch {
    return fallback;
  }
}

/** Per-viewer conveniences only (last family, last tab). Storage can be blocked: never throw. */
export function remember(key, value) {
  try {
    window.localStorage.setItem(`vkfOwner.${key}`, value);
  } catch {
    // ignore: the workspace works without storage
  }
}

export function recall(key) {
  try {
    return window.localStorage.getItem(`vkfOwner.${key}`);
  } catch {
    return null;
  }
}

/** A stable colour for avatars and accounts without one. */
export function colorFor(text) {
  const palette = [
    "#0f766e",
    "#0e7490",
    "#4f46e5",
    "#7c3aed",
    "#be185d",
    "#c2410c",
    "#15803d",
    "#334155"
  ];
  let hash = 0;
  for (const ch of text || "") {
    hash = (hash * 31 + ch.charCodeAt(0)) | 0;
  }
  return palette[Math.abs(hash) % palette.length];
}

export const LEDGER_FILTERS = [
  { value: "", label: "All" },
  { value: "Expense,Bill Payment,EMI Payment", label: "Spending" },
  { value: "Income,Refund", label: "Income" },
  { value: "Transfer Out,Transfer In,Card Payment", label: "Transfers" }
];
