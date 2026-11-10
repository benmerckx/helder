package tables;

import helder.test.Test;
import tables.Table.Column;

// The app's pure parts: JSON with its keys in order, SQL text by dialect,
// values shown and typed back (Drizzle's timestamps, booleans), and SQL's
// suggestions at the caret
function tests() {
	function sample():Array<Table> {
		var people = new Table("main", "people", false);
		people.add(new Column("id", "integer", false, true, null));
		people.add(new Column("name", "text", false, false, null));
		var issues = new Table("main", "issues", false);
		issues.add(new Column("id", "integer", false, true, null));
		issues.add(new Column("title", "text", false, false, null));
		issues.add(new Column("assignee", "integer", true, false, null));
		issues.add(new Column("Due Date", "integer", true, false, null));
		return [people, issues];
	}
	describe("Json", () -> {
		test("objects keep their keys in order", () -> {
			var r:Json.Record = Json.parse('{"b":1,"a":[true,null,"x\\n"],"c":1.5}');
			equals(r.keys, ["b", "a", "c"]);
			equals(Json.stringify(r), '{"b":1,"a":[true,null,"x\\n"],"c":1.5}');
		});
		test("big whole numbers without a fraction", () -> equals(Json.text(Json.parse("1699549822")), "1699549822"));
	});
	describe("Sql", () -> {
		test("names and literals by dialect", () -> {
			var t = sample()[1];
			equals(new Sql("sqlite").update(t, [7], [1], ["O'Hara"]), "UPDATE \"issues\" SET \"title\" = 'O''Hara' WHERE \"id\" = 7");
			equals(new Sql("mysql").delete(t, [7]), "DELETE FROM `issues` WHERE `id` = 7");
			equals(new Sql("postgresql").literal(true), "true");
			equals(new Sql("sqlite").insert(t, [], []), "INSERT INTO \"issues\" DEFAULT VALUES");
		});
	});
	describe("Format", () -> {
		test("timestamps as UTC dates and back", () -> {
			equals(Format.date(1699549822), "2023-11-09 17:10:22");
			equals(Format.seconds("2023-11-09 17:10:22"), 1699549822.0);
			equals(Format.seconds("2024-02-29"), 1709164800.0);
			equals(Format.seconds("yesterday"), null);
		});
		test("typed text as the column's value", () -> {
			var due = new Column("due", "integer", true, false, null);
			due.mode = "timestamp";
			equals(Format.parse(due, "1970-01-02"), 86400.0);
			var flag = new Column("done", "integer", false, false, null);
			flag.mode = "boolean";
			equals(Format.parse(flag, "yes"), true);
			equals(Format.parse(new Column("n", "real", true, false, null), "2.5"), 2.5);
			equals(Format.parse(new Column("n", "integer", true, false, null), ""), null);
		});
		test("counts with commas", () -> equals(Format.count(1234567), "1,234,567"));
	});
	describe("Complete", () -> {
		function labels(text:String):Array<String> {
			var r = Complete.at(text, text.length, sample(), new Sql("sqlite"));
			return r == null ? [] : r.items.map(i -> i.label);
		}
		test("tables after FROM and JOIN", () -> {
			equals(labels("SELECT * FROM "), ["people", "issues"]);
			equals(labels("SELECT * FROM issues JOIN pe"), ["people"]);
		});
		test("columns of a table or an alias after its dot, quoted when they need it", () -> {
			var r = Complete.at("SELECT i.as FROM issues i", 11, sample(), new Sql("sqlite"));
			equals(r.items.map(i -> i.label), ["assignee"]);
			var d = Complete.at("SELECT issues.du", 16, sample(), new Sql("sqlite"));
			equals(d.items[0].insert, "\"Due Date\"");
		});
		test("the query's columns, then tables and keywords", () -> {
			equals(labels("SELECT * FROM issues WHERE ti"), ["title"]);
			equals(labels("SELECT * FROM issues WHERE id > 3 OR"), ["ORDER BY"]);
		});
		test("nothing in a string or a comment", () -> {
			equals(labels("SELECT * FROM issues WHERE title = 'ti"), []);
			equals(labels("-- from "), []);
		});
	});
}
