function counter(start: number): (n: number) => number {
    let total = start;
    return (n: number): number => { total = total + n; return total; };
}
const count = counter(10);
console.log(count(2), count(3));
function apply(f: (x: number) => number, x: number): number { return f(x); }
console.log(apply((x: number) => x * x, 7));
function iterationClosures(): () => number {
    let a = (): number => -1;
    let b = (): number => -1;
    for (let i = 0; i < 2; i++) {
        if (i === 0) a = (): number => i;
        else b = (): number => i;
    }
    return (): number => a() + b();
}
console.log(iterationClosures()());
