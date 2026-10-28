// Globals tshx provides beyond the ECMAScript library.
declare const console: { log(...values: any[]): void };
declare function setImmediate(callback: (...args: any[]) => void, ...args: any[]): number;
declare function clearImmediate(id: number | undefined): void;
declare function setTimeout(callback: (...args: any[]) => void, ms?: number, ...args: any[]): number;
declare function setInterval(callback: (...args: any[]) => void, ms?: number, ...args: any[]): number;
declare function clearTimeout(id: number | undefined): void;
declare function clearInterval(id: number | undefined): void;
declare function queueMicrotask(callback: () => void): void;
declare function structuredClone<T>(value: T): T;
