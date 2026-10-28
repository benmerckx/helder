function show(x: { value: number } | null): number | undefined { return x?.value; }
console.log(show(null));
