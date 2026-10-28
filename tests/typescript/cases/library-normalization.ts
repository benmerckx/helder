{
for (const form of [undefined, "NFC", "NFD", "NFKC", "NFKD"] as const) {
  for (const s of ["é", "e\u0301", "\u212b", "\ufb03", "\u1e9b\u0323", "각", "\u1100\u1161\u11a8", "a\u0315\u0300", "\ud800x\udfff", "\u{1d15e}"])
    console.log(form, JSON.stringify(s.normalize(form)));
}
const log: string[] = [];
console.log(String.prototype.normalize.call({ toString() { log.push("receiver"); return "e\u0301"; } }, { toString() { log.push("form"); return "NFC"; } } as any), log.join());
for (const form of ["", "nfc", "NFKZ", null]) { try { "abc".normalize(form as any); } catch (e: any) { console.log(e.name); } }
try { String.prototype.normalize.call(null, "bad"); } catch (e: any) { console.log(e.name); }
try { "abc".normalize(Symbol() as any); } catch (e: any) { console.log(e.name); }
console.log(String.prototype.normalize.length, String.prototype.normalize.name);
}
