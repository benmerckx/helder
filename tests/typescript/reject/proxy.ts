// Rejected at its own line, after comments and non-ASCII text.
const label = "☃ 😀";

/* expect: proxy.ts:5: TSHX001 */
const p = new Proxy({}, {});
