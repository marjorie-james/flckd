// Escape the five XML/HTML special characters. Safe for both HTML text (where
// unescaped input is a DOM-XSS vector) and XML output such as GPX — the numeric
// apostrophe reference &#39; is valid in both.
export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] as string,
  );
}
