function show(x: number | string): string {
    if (typeof x === "number") return "number:" + (x + 1);
    return "string:" + x;
}
console.log(show(4), show("hello"), null == undefined, null === undefined);
