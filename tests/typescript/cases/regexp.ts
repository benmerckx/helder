// regular expressions: groups, lookaround, flags, replace/split/matchAll, unicode
{
console.log(/a(b+)/.exec("xabbb")![1],"a-b_c".replace(/[-_]/g,"+"),/^\d+$/.test("123"),"a1b2".split(/\d/).join());
}
{
const date = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/;
const m = "Due 2024-03-15!".match(date)!; console.log(m[0], m.index, m.groups!.year, m.groups!.month, m.length);
console.log("a1b22c333".replace(/\d+/g, d => `<${d.length}>`), "John Smith".replace(/(\w+)\s(\w+)/, "$2, $1"), "x-y_z".split(/[-_]/).join("|"));
console.log(/^[\w.+-]+@[\w-]+\.[\w.]+$/.test("user.name+tag@example.co.uk"), /^\s*$/.test("   "), /colou?r/i.test("COLOR"));
const re = /o/g; let r; const hits: number[] = []; while ((r = re.exec("foo boo")) !== null) hits.push(r.index); console.log(hits.join(), re.lastIndex);
console.log([..."a1b2c3".matchAll(/([a-z])(\d)/g)].map(x => x[1] + "=" + x[2]).join("&"), "abc".search(/c/), "aaa".replace(/a*?/g, "-"));
console.log("one  two   three".split(/\s+/), "a,b;c".split(/([,;])/), "test".split(/(?:)/u).length);
console.log(/(\d+)(?=px)/.exec("width: 100px")![1], /(?<!\$)\b\d+/.exec("$50 or 30")![0], /(?<=\$)\d+/.exec("cost $42")![0]);
console.log(/(a)|(b)/.exec("b"), /(\w)\1/.test("hello"), /^.$/su.test("😀"), /^.$/.test("😀"), /\u{1F600}/u.test("😀"));
console.log(/a.c/s.test("a\nc"), /^b/m.test("a\nb"), new RegExp("a/b", "gi").source, String(/x\/y/g)); try { new RegExp("["); } catch (e: any) { console.log(e.name); }
}
