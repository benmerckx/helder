import { pong } from "./cycle-b.js";
export function ping(n: number): string { return n <= 0 ? "ping!" : pong(n - 1); }
