function scope(): number {
    let i = 7;
    for (let i = 0; i < 3; i++) { let x = i; }
    return i;
}
function square(x: number): number { return x * x; }
function applySquare(f: (x: number) => number): number { return f(9); }
console.log(scope(), applySquare(square));
