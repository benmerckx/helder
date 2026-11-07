package studio;

import haxe.Json;
import helder.async.*;
import helder.async.http.Http;

using StringTools;

// The studio's tools (Tools) over MCP, the Model Context Protocol's
// Streamable HTTP transport in its simplest form: JSON-RPC requests POSTed
// to /mcp, each answered with one JSON response (no event stream, no
// session needed; notifications answered 202). Listening on 127.0.0.1 only,
// on HELDER_STUDIO_MCP_PORT, --mcp-port, else a free port; the URL is
// printed and written to <root>/bin/studio/<name>/mcp.json for an agent to
// find. Claude Code:
//
//   claude mcp add --transport http helder-studio http://127.0.0.1:<port>/mcp
class Mcp {
	public static inline var VERSION = "2025-06-18";

	final studio:Studio;
	final port:Int;
	public var url(default, null):Null<String> = null;

	public function new(studio, port:Int) {
		this.studio = studio;
		this.port = port;
	}

	@:coroutine public function serve(task:Node) {
		var server = try Server.listen("127.0.0.1", port) catch (e:Dynamic) {
			Sys.println('studio: no MCP server ($e)');
			return;
		}
		url = 'http://127.0.0.1:${server.port}/mcp';
		Sys.println('studio: MCP at $url (claude mcp add --transport http helder-studio $url)');
		var p = studio.project;
		if (p != null) try {
			helder.cli.TestCommand.mkdirs(p.out);
			sys.io.File.saveContent('${p.out}/mcp.json', Json.stringify({url: url, project: p.dir, tools: [for (t in Tools.list) t.name]}, "  ") + "\n");
		} catch (_:Dynamic) {}
		Http.serve(server, handle);
	}

	@:coroutine function handle(req:Request):Null<Response> {
		if (req.path != "/mcp") return Response.text("helder studio: MCP is at /mcp\n", 404);
		if (req.method == "GET") return Response.text("helder studio: no event stream; POST JSON-RPC to /mcp\n", 405);
		if (req.method == "DELETE") return new Response(200);
		if (req.method != "POST") return Response.text("POST /mcp\n", 405);
		var m:Dynamic = try Json.parse(req.body.toString()) catch (_:Dynamic) null;
		if (m == null) return json({jsonrpc: "2.0", id: null, error: {code: -32700, message: "not JSON"}}, 400);
		if (Std.isOfType(m, Array)) {
			var out = [];
			for (x in (m : Array<Dynamic>)) {
				var r = one(x);
				if (r != null) out.push(r);
			}
			return out.length == 0 ? new Response(202) : json(out);
		}
		var r = one(m);
		return r == null ? new Response(202) : json(r);
	}

	// one message: its response (null: a notification's, none)
	@:coroutine function one(m:Dynamic):Null<Dynamic> {
		var id:Dynamic = m.id;
		if (m.method == null) return null;
		if (id == null) return null;
		var method:String = m.method;
		var result:Dynamic = switch method {
			case "initialize":
				{
					protocolVersion: m.params?.protocolVersion ?? VERSION,
					capabilities: {tools: {listChanged: false}},
					serverInfo: {name: "helder-studio", version: "0.1.0"},
					instructions: "helder studio's project: read and patch its files (project.read, project.patch: through the studio's history; live literals patched in the running screens, anything else rebuilt), check it (build.check), and see what each screen (a story) shows (run.snap, run.tree)."
				};
			case "ping": {};
			case "tools/list": {tools: Tools.list};
			case "tools/call":
				var name:String = m.params?.name;
				studio.tools.call(name, m.params?.arguments);
			case "resources/list": {resources: []};
			case "prompts/list": {prompts: []};
			case _: null;
		}
		if (result == null) return {jsonrpc: "2.0", id: id, error: {code: -32601, message: 'no method $method'}};
		return {jsonrpc: "2.0", id: id, result: result};
	}

	static function json(v:Dynamic, status = 200):Response
		return Response.text(Json.stringify(v), status, "application/json");
}
