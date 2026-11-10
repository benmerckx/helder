// A value as a cell shows it and back from what was typed: Drizzle's
// timestamps (seconds or milliseconds) as UTC dates, its booleans as true
// and false, numbers as numbers, objects as JSON
import { Column } from "./table";

export function text(c: Column, v: unknown): string | null {
	if (v === null || v === undefined) return null;
	if ((c.mode === "timestamp" || c.mode === "timestamp_ms") && typeof v === "number") return date(c.mode === "timestamp_ms" ? v / 1000 : v);
	if (c.mode === "boolean" && (typeof v === "number" || typeof v === "boolean")) return v === true || v === 1 ? "true" : "false";
	if (typeof v === "string") return v;
	if (typeof v === "boolean" || typeof v === "number") return String(v);
	return JSON.stringify(v);
}

// what was typed as the column's value (null: NULL); an error when it is not one
export function parse(c: Column, s: string): unknown {
	const t = s.trim();
	if (c.mode === "timestamp" || c.mode === "timestamp_ms") {
		if (t === "") return null;
		const secs = seconds(t);
		if (secs === null) throw new Error(`Not a date: ${t} (2024-05-06 13:42:25)`);
		return c.mode === "timestamp_ms" ? secs * 1000 : secs;
	}
	if (c.mode === "boolean") {
		switch (t.toLowerCase()) {
			case "true": case "1": case "yes": return true;
			case "false": case "0": case "no": return false;
			case "": return null;
			default: throw new Error(`Not a boolean: ${t}`);
		}
	}
	if (c.numeric) {
		if (t === "") return null;
		const n = Number(t);
		if (Number.isNaN(n)) throw new Error(`Not a number: ${t}`);
		return n;
	}
	return s;
}

const two = (n: number) => (n < 10 ? "0" + n : String(n));

// seconds since 1970 as "2024-05-06 13:42:25" (UTC)
export function date(secs: number): string {
	const s = Math.floor(secs), days = Math.floor(s / 86400), rest = s - days * 86400;
	// (Howard Hinnant's civil_from_days)
	const z = days + 719468, era = Math.floor(z / 146097), doe = z - era * 146097;
	const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
	let y = yoe + era * 400;
	const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100)), mp = Math.floor((5 * doy + 2) / 153);
	const d = doy - Math.floor((153 * mp + 2) / 5) + 1, m = mp < 10 ? mp + 3 : mp - 9;
	if (m <= 2) y++;
	return `${y}-${two(m)}-${two(d)} ${two(Math.floor(rest / 3600))}:${two(Math.floor(rest / 60) % 60)}:${two(rest % 60)}`;
}

// "2024-05-06", "2024-05-06 13:42" or "2024-05-06T13:42:25" (UTC) as seconds since 1970
export function seconds(t: string): number | null {
	const r = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?Z?$/.exec(t);
	if (r === null) return null;
	let y = Number(r[1]);
	const m = Number(r[2]), d = Number(r[3]);
	// (days_from_civil)
	if (m <= 2) y--;
	const era = Math.floor(y / 400), yoe = y - era * 400;
	const doy = Math.floor((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1;
	const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
	const days = era * 146097 + doe - 719468;
	return days * 86400 + Number(r[4] ?? 0) * 3600 + Number(r[5] ?? 0) * 60 + Number(r[6] ?? 0);
}

// a count with thousands' commas
export function count(n: number): string {
	return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
