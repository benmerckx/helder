// Strings: building one piece by piece, splitting it, counting its words.
function words(n: number): string {
	let s = "";
	for (let i = 0; i < n; i++) s += i % 7 === 0 ? "lorem " : "ipsum ";
	return s;
}
const text = words(50000);
let count = 0, letters = 0;
for (const w of text.split(" ")) if (w.length > 0) { count++; letters += w.length; }
const counts = new Map<string, number>();
for (const w of text.split(" ")) counts.set(w, (counts.get(w) ?? 0) + 1);
let codes = 0;
for (let i = 0; i < text.length; i++) codes += text.charCodeAt(i);
console.log(count, letters, codes, [...counts.entries()].map(([k, v]) => k + "=" + v).join(","));
