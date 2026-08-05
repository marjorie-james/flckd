// Thin fetch wrapper for the flckd API. Browser requests always use the
// same-origin /api/v1 endpoint so runtime config cannot disclose route data to
// another origin. Vite proxies /api -> :3000 in development.
import i18n from "../i18n";

const API_PREFIX = "/api/v1";

export class ApiError extends Error {
  code: string;
  status: number;
  constructor(code: string, message: string, status: number) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

// The effective selected locale — the resolved result including any explicit
// override, not the raw browser signal — so the server localizes its responses
// to exactly what the visitor sees (FR-016).
function currentLocale(): string {
  return i18n.language || "en";
}

async function handle<T>(res: Response): Promise<T> {
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = body as { code?: string; message?: string };
    throw new ApiError(err.code ?? "error", err.message ?? res.statusText, res.status);
  }
  return body as T;
}

export function apiGet<T>(
  path: string,
  params?: Record<string, string | number>,
  signal?: AbortSignal,
): Promise<T> {
  const qs = params
    ? "?" + new URLSearchParams(Object.entries(params).map(([k, v]) => [k, String(v)])).toString()
    : "";
  return fetch(`${API_PREFIX}${path}${qs}`, {
    headers: { "Accept-Language": currentLocale() },
    signal,
  }).then((r) => handle<T>(r));
}

export function apiPost<T>(path: string, body: unknown, signal?: AbortSignal): Promise<T> {
  return fetch(`${API_PREFIX}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept-Language": currentLocale() },
    body: JSON.stringify(body),
    signal,
  }).then((r) => handle<T>(r));
}
