// helder's functions are called, not passed around as values.
import { signal } from "helder/view";
const make = signal; // expect: helder-value.ts:3: TSHX001: helder's signal is used as a value
console.log(make(1));
