// A JSON module (resolveJsonModule): its value the default import.
import data from "./data.json" with { type: "json" };

console.log(data.title, data.tags.length, data.size.width * 2, data.demo);
console.log(JSON.stringify(data));
