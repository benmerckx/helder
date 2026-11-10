// a value written to a signal read back as written: the same objects, nested ones too (Interop.signal, held)
import { signal } from "helder/view";
const o = { a: 1, f: () => 2 };
const s = signal(o);
console.log(s() === o, s.peek() === o, s() === s());
const list = [o, { a: 2, f: () => 3 }];
const t = signal<{ a: number }[] | null>(null);
t(list);
setTimeout(() => {
	console.log(t.peek() === list, t.peek()![1] === list[1]);
	t(l => l === null ? null : [...l, { a: 3 }]);
	setTimeout(() => {
		console.log(t.peek()![0] === o, t.peek()!.length);
		const n = signal(5);
		console.log(n(), typeof n());
	}, 0);
}, 0);
