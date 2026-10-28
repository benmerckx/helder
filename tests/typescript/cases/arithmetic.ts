function fib(n: number): number {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}
console.log(fib(20), 1 / 0, -0, 0.1 + 0.2);
