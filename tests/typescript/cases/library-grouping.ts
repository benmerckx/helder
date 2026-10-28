function check(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}
function throwsSame(fn: () => unknown, expected: unknown) {
  try { fn(); } catch (error) { check(error === expected, "Wrong thrown value"); return; }
  throw new Error("Missing exception");
}

for (const group of [Object.groupBy as any, Map.groupBy as any]) {
  const values = [1, 2];
  const seen: number[] = [];
  group(values, (value: number, index: number) => {
    seen.push(value);
    if (index === 0) values.push(3);
    return "key";
  });
  check(seen.join() === "1,2,3", "Callbacks must run during iteration");

  let reads = 0, calls = 0, closed = 0;
  const iterator: any = {
    [Symbol.iterator]() { return this; },
    get next() {
      reads++;
      return function (this: any) {
        check(this === iterator, "Wrong iterator receiver");
        calls++;
        return calls < 3 ? {value: calls, done: false} : {done: true};
      };
    },
    return() { closed++; return {}; }
  };
  group(iterator, function (this: unknown, value: number, index: number) {
    check(this === undefined, "Wrong callback receiver");
    check(arguments.length === 2 && value === index + 1, "Wrong callback arguments");
    return "key";
  });
  check(reads === 1 && calls === 3 && closed === 0, "Cache next without closing on completion");

  const sentinel = {};
  for (const closeKind of ["normal", "throw", "getter", "primitive", "noncallable"]) {
    let order = "";
    const abrupt: any = {
      [Symbol.iterator]() { return this; },
      next() { order += "N"; return {value: 1, done: false}; },
      get return() {
        order += "R";
        if (closeKind === "getter") throw new Error("return getter");
        if (closeKind === "noncallable") return 1;
        return function (this: unknown) {
          check(this === abrupt && arguments.length === 0, "Wrong return call");
          order += "C";
          if (closeKind === "throw") throw new Error("return call");
          return closeKind === "primitive" ? 1 : {};
        };
      }
    };
    throwsSame(() => group(abrupt, () => { order += "F"; throw sentinel; }), sentinel);
    check(order === (closeKind === "getter" || closeKind === "noncallable" ? "NFR" : "NFRC"), "Close once and preserve callback error");
  }

  for (const step of ["next", "done", "value"]) {
    let closes = 0;
    const broken: any = {
      [Symbol.iterator]() { return this; },
      next() {
        if (step === "next") throw sentinel;
        return {
          get done() { if (step === "done") throw sentinel; return false; },
          get value() { throw sentinel; }
        };
      },
      return() { closes++; return {}; }
    };
    throwsSame(() => group(broken, () => "key"), sentinel);
    check(closes === 0, "Do not close after iterator-step failures");
  }

  let touched = false;
  const input = {get [Symbol.iterator]() { touched = true; throw sentinel; }};
  try { group(input as any, null as any); throw sentinel; }
  catch (error) { check(error instanceof TypeError && !touched, "Validate callback before getting iterator"); }
}

let closes = 0;
const keyError = {};
const input = {
  [Symbol.iterator]() { return this; },
  next() { return {value: 1, done: false}; },
  return() { closes++; return {}; }
};
throwsSame(() => Object.groupBy(input as any, () => ({[Symbol.toPrimitive]() { throw keyError; }}) as any), keyError);
check(closes === 1, "Close if property-key coercion throws");

const symbol = Symbol("group");
const object: any = Object.groupBy([0, 1, 2], value => ["__proto__", "constructor", symbol][value]);
check(Object.getPrototypeOf(object) === null, "Null prototype");
check(object.__proto__![0] === 0 && object.constructor![0] === 1 && object[symbol]![0] === 2, "Special property keys");
const objectKey = {[Symbol.toPrimitive]() { throw new Error("Map keys must not be coerced"); }};
const map = Map.groupBy([1, 2], () => objectKey);
check(map.get(objectKey)!.join() === "1,2", "Preserve object keys");
const zero = Map.groupBy([-0, 0, NaN, NaN], value => value);
check(zero.size === 2 && Object.is(zero.keys().next().value, 0), "Normalize negative zero keys");
check(Object.is(zero.get(0)![0], -0) && zero.get(NaN)!.length === 2, "Preserve grouped values and merge NaN keys");
console.log("Grouping order, iterator closing, coercion and key checks passed");
