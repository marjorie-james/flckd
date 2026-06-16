// Thin fetch wrapper for the flckd API. Talks only to our own backend (never a
// third party): same-origin by default, or the apiBase from runtime config when
// the API is hosted separately (e.g. a standby spine). Vite proxies /api -> :3000
// in dev.
import { apiBase } from "../config";

// Built per call (not at module load) so it reflects config.json fetched at boot.
// apiBase() is "" in the common same-origin case → a relative "/api/v1" request.
const base = (): string => `${apiBase()}/api/v1`;

export class ApiError extends Error {
  code: string;
  status: number;
  constructor(code: string, message: string, status: number) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

function navigatorLang(): string {
  return (typeof navigator !== "undefined" && navigator.language) || "en";
}

async function handle<T>(res: Response): Promise<T> {
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = body as { code?: string; message?: string };
    throw new ApiError(err.code ?? "error", err.message ?? res.statusText, res.status);
  }
  return body as T;
}

export function apiGet<T>(path: string, params?: Record<string, string | number>): Promise<T> {
  const qs = params
    ? "?" + new URLSearchParams(Object.entries(params).map(([k, v]) => [k, String(v)])).toString()
    : "";
  return fetch(`${base()}${path}${qs}`, {
    headers: { "Accept-Language": navigatorLang() },
  }).then((r) => handle<T>(r));
}

export function apiPost<T>(path: string, body: unknown, signal?: AbortSignal): Promise<T> {
  return fetch(`${base()}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept-Language": navigatorLang() },
    body: JSON.stringify(body),
    signal,
  }).then((r) => handle<T>(r));
}
