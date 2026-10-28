function sum(n: number): number {
    let result = 0;
    for (let i = 0; i < n; i++) result = result + i;
    return result;
}
console.log(sum(100));
