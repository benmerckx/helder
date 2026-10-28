import { ping } from "./cycle-a.js";
export function pong(n: number): string { return n <= 0 ? "pong!" : ping(n - 1); }
