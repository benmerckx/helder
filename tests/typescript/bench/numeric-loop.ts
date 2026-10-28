function sum(n: number): number {
    let s = 0;
    for (let i = 0; i < n; i++) s = s + (i % 97);
    return s;
}
console.log(sum(10000000));
