console.log("greet module");
export const VERSION = "1.0";
export function add(a: number, b: number) { return a + b; }
export class Counter { value = 0; inc() { this.value++; return this; } }
export default function greet(name: string) { return `hello ${name}`; }
