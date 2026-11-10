package tables;

import haxe.Exception;
import haxe.io.Bytes;
import helder.async.http.Client;
import tables.Json.Record;

// drizzle-kit studio's server (`npx drizzle-kit studio`: drizzle-kit's
// src/serializer/studio.ts): one POST of JSON, its type init (the
// dialect, the driver, the schema's relations), proxy (a statement, its
// rows as arrays) or tproxy (statements in a transaction, rolled back at
// the first error: an {error} after the results)
class Drizzle {
	// the server's protocol this was written against
	public static inline var VERSION = "6.2";

	public final url:String;

	public function new(url:String)
		this.url = url;

	@:coroutine public function init():Setup {
		var r:Record = post('{"type":"init"}');
		var version = Std.string(r.get("version"));
		var rels:Array<Dynamic> = r.get("relations") ?? [];
		var files:Array<Dynamic> = r.get("schemaFiles") ?? [];
		return {
			version: version,
			dialect: Std.string(r.get("dialect")),
			driver: Std.string(r.get("packageName") ?? r.get("driver") ?? ""),
			database: r.get("databaseName"),
			files: [for (f in files) {name: Std.string((f : Record).get("name")), content: Std.string((f : Record).get("content"))}],
			relations: [
				for (x in rels) {
					var o:Record = x;
					{
						name: o.get("name"),
						kind: o.get("type"),
						table: o.get("table"),
						schema: o.get("schema"),
						columns: o.get("columns"),
						refTable: o.get("refTable"),
						refSchema: o.get("refSchema"),
						refColumns: o.get("refColumns")
					}
				}
			]
		};
	}

	// a statement's rows, each an array of its columns' values
	@:coroutine public function rows(sql:String, ?params:Array<Dynamic>):Array<Array<Dynamic>> {
		var r:Dynamic = post(Json.stringify(body("proxy", sql, params, "array", "all")));
		return r is Array ? r : [];
	}

	// a statement's rows as records: their columns by name, in order
	@:coroutine public function records(sql:String, ?params:Array<Dynamic>):Array<Record> {
		var r:Dynamic = post(Json.stringify(body("proxy", sql, params, "object", "all")));
		return r is Array ? r : [];
	}

	// statements in one transaction (none kept if one fails: its error thrown)
	@:coroutine public function transaction(statements:Array<String>):Void {
		var data:Array<Dynamic> = [for (s in statements) new Record().set("sql", s).set("method", "run")];
		var results:Dynamic = post(Json.stringify(new Record().set("type", "tproxy").set("data", data)));
		if (!(results is Array)) return;
		for (x in (results : Array<Dynamic>))
			if (x is Record && (x : Record).keys.indexOf("error") >= 0) throw new Exception(Std.string((x : Record).get("error")));
	}

	static function body(type:String, sql:String, params:Null<Array<Dynamic>>, mode:String, method:String):Record
		return new Record().set("type", type).set("data", new Record().set("sql", sql).set("params", params ?? []).set("mode", mode).set("method", method));

	@:coroutine function post(json:String):Dynamic {
		var res = try Client.request(url, {
			method: "POST",
			headers: ["content-type" => "application/json"],
			body: Bytes.ofString(json)
		}) catch (e:Exception) throw new Exception('No drizzle-kit studio at $url');
		var v = Json.parse(res.text());
		if (v is Record) {
			var r:Record = v;
			if (r.get("status") == "error") throw new Exception(Std.string(r.get("error")));
		}
		if (res.status >= 400) throw new Exception('drizzle-kit studio answered ${res.status}');
		return v;
	}
}

typedef Setup = {
	version:String,
	dialect:String,
	driver:String,
	database:Null<String>,
	// the Drizzle schema's files: their names and text
	files:Array<{name:String, content:String}>,
	relations:Array<Relation>
}

// a relation of the Drizzle schema: one (a reference) or many (what refers to it)
typedef Relation = {
	name:String,
	kind:String,
	table:String,
	schema:String,
	columns:Array<String>,
	refTable:String,
	refSchema:String,
	refColumns:Array<String>
}
