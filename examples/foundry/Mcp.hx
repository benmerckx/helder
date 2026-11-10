import haxe.Json;
import helder.async.*;
import helder.async.http.Http;

// Foundry's tools (Tools) over MCP's Streamable HTTP transport in its
// simplest form, as helder studio serves its own (apps/studio's Mcp):
// JSON-RPC POSTed to /mcp, each answered with one JSON response. On
// 127.0.0.1 only, port FOUNDRY_MCP_PORT, else 7341 (else any free one).
//
//   claude mcp add --transport http foundry http://127.0.0.1:7341/mcp
class Mcp {
	static inline var VERSION = "2025-06-18";

	public static function start(ws:Workshop)
		Async.launch(_ -> serve(ws));

	@:coroutine static function serve(ws:Workshop) {
		var port = Std.parseInt(Sys.getEnv("FOUNDRY_MCP_PORT") ?? "") ?? 7341;
		var server = try Server.listen("127.0.0.1", port) catch (_:Dynamic) try Server.listen("127.0.0.1", 0) catch (e:Dynamic) {
			Sys.println('foundry: no MCP server ($e)');
			return;
		}
		var url = 'http://127.0.0.1:${server.port}/mcp';
		ws.mcp(url);
		Sys.println('foundry: MCP at $url (claude mcp add --transport http foundry $url)');
		var tools = new Tools(ws);
		Http.serve(server, req -> handle(req, tools));
	}

	@:coroutine static function handle(req:Request, tools:Tools):Null<Response> {
		if (req.path != "/mcp") return Response.text("foundry: MCP is at /mcp\n", 404);
		if (req.method == "GET") return Response.text("foundry: no event stream; POST JSON-RPC to /mcp\n", 405);
		if (req.method == "DELETE") return new Response(200);
		if (req.method != "POST") return Response.text("POST /mcp\n", 405);
		var m:Dynamic = try Json.parse(req.body.toString()) catch (_:Dynamic) null;
		if (m == null) return json({jsonrpc: "2.0", id: null, error: {code: -32700, message: "not JSON"}}, 400);
		if (Std.isOfType(m, Array)) {
			var out = [];
			for (x in (m : Array<Dynamic>)) {
				var r = one(x, tools);
				if (r != null) out.push(r);
			}
			return out.length == 0 ? new Response(202) : json(out);
		}
		var r = one(m, tools);
		return r == null ? new Response(202) : json(r);
	}

	static function one(m:Dynamic, tools:Tools):Null<Dynamic> {
		var id:Dynamic = m.id;
		if (m.method == null || id == null) return null;
		var method:String = m.method;
		var result:Dynamic = switch method {
			case "initialize": {
					protocolVersion: m.params?.protocolVersion ?? VERSION,
					capabilities: {tools: {listChanged: false}},
					serverInfo: {name: "foundry", version: "0.1.0"},
					instructions: Tools.INSTRUCTIONS
				};
			case "ping": {};
			case "tools/list": {tools: Tools.list};
			case "tools/call": tools.call(m.params?.name, m.params?.arguments);
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
