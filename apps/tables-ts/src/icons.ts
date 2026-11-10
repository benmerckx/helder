// Lucide's icons (LUCIDE-LICENSE, ISC), those used, as SVG
import { Icons } from "helder/ui";

const icon = (inner: string) =>
	Icons.parse(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${inner}</svg>`);

export const table = icon(`<path d="M9 3H5a2 2 0 0 0-2 2v4m6-6h10a2 2 0 0 1 2 2v4M9 3v18m0 0h10a2 2 0 0 0 2-2V9M9 21H5a2 2 0 0 1-2-2V9m0 0h18"/>`);
export const view = icon(`<path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/>`);
export const search = icon(`<path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/>`);
export const plus = icon(`<path d="M5 12h14"/><path d="M12 5v14"/>`);
export const trash = icon(`<path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/>`);
export const refresh = icon(`<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>`);
export const database = icon(`<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5V19A9 3 0 0 0 21 19V5"/><path d="M3 12A9 3 0 0 0 21 12"/>`);
export const columns = icon(`<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/><path d="M15 3v18"/>`);
export const terminal = icon(`<path d="m7 11 2-2-2-2"/><path d="M11 13h4"/><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/>`);
export const back = icon(`<path d="m15 18-6-6 6-6"/>`);
export const link = icon(`<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>`);
export const close = icon(`<path d="M18 6 6 18"/><path d="m6 6 12 12"/>`);
export const open = icon(`<path d="M7 7h10v10"/><path d="M7 17 17 7"/>`);
export const filter = icon(`<path d="M3 6h18"/><path d="M7 12h10"/><path d="M10 18h4"/>`);
export const play = icon(`<path d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/>`);
export const undo = icon(`<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11"/>`);
export const panel = icon(`<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M15 3v18"/>`);
export const check = icon(`<path d="M20 6 9 17l-5-5"/>`);
