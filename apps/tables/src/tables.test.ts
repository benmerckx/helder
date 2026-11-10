// The app's pure parts: SQL text by dialect, values shown and typed back
// (Drizzle's timestamps, booleans), and SQL's suggestions at the caret
import { describe, test, equals } from "helder/test";
import { Column, Table } from "./table";
import { Sql } from "./sql";
import * as format from "./format";
import { complete } from "./complete";

function sample(): Table[] {
	const people = new Table("main", "people", false);
	people.add(new Column("id", "integer", false, true, null));
	people.add(new Column("name", "text", false, false, null));
	const issues = new Table("main", "issues", false);
	issues.add(new Column("id", "integer", false, true, null));
	issues.add(new Column("title", "text", false, false, null));
	issues.add(new Column("assignee", "integer", true, false, null));
	issues.add(new Column("Due Date", "integer", true, false, null));
	return [people, issues];
}

function column(name: string, type: string, nullable: boolean, mode = ""): Column {
	const c = new Column(name, type, nullable, false, null);
	c.mode = mode;
	return c;
}

describe("sql", () => {
	test("names and literals by dialect", () => {
		const t = sample()[1];
		equals(new Sql("sqlite").update(t, [7], [1], ["O'Hara"]), `UPDATE "issues" SET "title" = 'O''Hara' WHERE "id" = 7`);
		equals(new Sql("mysql").delete(t, [7]), "DELETE FROM `issues` WHERE `id` = 7");
		equals(new Sql("postgresql").literal(true), "true");
		equals(new Sql("sqlite").insert(t, [], []), `INSERT INTO "issues" DEFAULT VALUES`);
	});
});

describe("format", () => {
	test("timestamps as UTC dates and back", () => {
		equals(format.date(1699549822), "2023-11-09 17:10:22");
		equals(format.seconds("2023-11-09 17:10:22"), 1699549822);
		equals(format.seconds("2024-02-29"), 1709164800);
		equals(format.seconds("yesterday"), null);
	});

	test("typed text as the column's value", () => {
		equals(format.parse(column("due", "integer", true, "timestamp"), "1970-01-02"), 86400);
		equals(format.parse(column("done", "integer", false, "boolean"), "yes"), true);
		equals(format.parse(column("n", "real", true), "2.5"), 2.5);
		equals(format.parse(column("n", "integer", true), ""), null);
	});

	test("counts with commas", () => equals(format.count(1234567), "1,234,567"));
});

describe("complete", () => {
	const sql = new Sql("sqlite");
	const labels = (text: string) => complete(text, text.length, sample(), sql)?.items.map(i => i.label) ?? [];

	test("tables after FROM and JOIN", () => {
		equals(labels("SELECT * FROM "), ["people", "issues"]);
		equals(labels("SELECT * FROM issues JOIN pe"), ["people"]);
	});

	test("columns of a table or an alias after its dot, quoted when they need it", () => {
		equals(complete("SELECT i.as FROM issues i", 11, sample(), sql)?.items.map(i => i.label), ["assignee"]);
		equals(complete("SELECT issues.du", 16, sample(), sql)?.items[0].insert, `"Due Date"`);
	});

	test("the query's columns, then tables and keywords", () => {
		equals(labels("SELECT * FROM issues WHERE ti"), ["title"]);
		equals(labels("SELECT * FROM issues WHERE id > 3 OR"), ["ORDER BY"]);
	});

	test("nothing in a string or a comment", () => {
		equals(labels("SELECT * FROM issues WHERE title = 'ti"), []);
		equals(labels("-- from "), []);
	});
});
