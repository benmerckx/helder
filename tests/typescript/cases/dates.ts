// Date: UTC arithmetic, local fields, setters, parsing, formatting, invalid dates
const d = new Date(Date.UTC(2024, 1, 29, 13, 45, 30, 123));
console.log(d.toISOString(), d.getTime(), d.getUTCDay(), d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), JSON.stringify({ d }));
console.log(d.toString(), "|", d.toUTCString(), "|", d.toDateString(), "|", d.toLocaleDateString(), d.toLocaleTimeString(), "|", d.toLocaleString());
const e = new Date(2024, 0, 31); e.setMonth(1); console.log(e.getMonth(), e.getDate(), e.getFullYear());
e.setDate(0); console.log(e.toISOString()); e.setHours(25, 61, 61, 1001); console.log(e.toISOString());
console.log(Date.parse("2024-03-05"), Date.parse("2024-03-05T10:00:00Z"), Date.parse("2024-03-05T10:00:00.5+02:00"), new Date("Tue Mar 05 2024 10:00:00 GMT+0000").getTime(), new Date("March 7, 2024 10:30:00").getDate());
console.log(new Date(NaN).getTime(), String(new Date("garbage")), new Date(0).valueOf(), new Date(-1).toISOString(), new Date(8.64e15 + 1).getTime());
console.log(new Date(2020, 11, 31, 23, 59, 59) < new Date(2021, 0, 1), +new Date(1000), `${new Date(0)}`.slice(0, 15), d, [d], typeof Date.now(), Date.now() > 1.7e12);
console.log(new Date(99, 0).getFullYear(), new Date(-62198755200000).toISOString(), new Date("+010000-01-01T00:00:00Z").getUTCFullYear(), Object.prototype.toString.call(d));
const ms = (a: Date, b: Date) => b.getTime() - a.getTime(); console.log(ms(new Date(2024, 0, 1), new Date(2024, 2, 1)) / 86400000);
