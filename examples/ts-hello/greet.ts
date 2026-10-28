export class Counter {
	#count = 0;
	next(): number {
		return ++this.#count;
	}
}

export function greet(name: string, n: number): string {
	return `${n}. hello, ${name}`;
}
