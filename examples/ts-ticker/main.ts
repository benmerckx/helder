// Ticks on a timer until it is stopped: helder dev rebuilds it as its files change.
import { label } from "./label";

let n = 0;
setInterval(() => console.log(label(++n)), 200);
