package studio;

import helder.async.*;

using StringTools;

// What the prompt bar talks to: a prompt about what is in focus (the whole
// app, a screen, a node), answered (as many replies as it has: progress,
// then the end). The hosted prompt box (helder.build's) and a model of the
// user's own key plug in here later; they act through the same tools as
// the studio's MCP server (Tools).
interface Agent {
	function ask(prompt:String, context:AgentContext, reply:String->Void):Void;
}

typedef AgentContext = {
	// the screen in focus (null: the whole app), the node selected in it
	screen:Null<String>,
	selection:Null<Studio.Selection>,
}

// The agent without a model: a prompt that names a tool ("/tree", "/check",
// "/snap", "/read app.tsx") calls it on the local tool surface (Tools, the
// MCP server's); anything else says how to drive the studio from an agent
// over MCP (README.md, "Agents").
class LocalAgent implements Agent {
	final studio:Studio;

	public function new(studio)
		this.studio = studio;

	public function ask(prompt:String, context:AgentContext, reply:String->Void) {
		var p = prompt.trim();
		var words = p.split(" ").filter(w -> w != "");
		var tool = switch words[0] {
			case "/tree": "run.tree";
			case "/snap": "run.snap";
			case "/check": "build.check";
			case "/read": "project.read";
			case _: null;
		}
		if (tool == null) {
			var url = studio.mcp?.url ?? "(no MCP server)";
			reply('No model is connected yet. Drive the studio from an agent over MCP at $url (project.read, project.patch, build.check, run.snap, run.tree), or try /tree, /snap, /check, /read <file>.');
			return;
		}
		var args:Dynamic = {};
		if (tool == "project.read" && words.length > 1) args.path = words[1];
		if ((tool == "run.tree" || tool == "run.snap") && context.screen != null) args.screen = context.screen;
		var t = studio.tools;
		Async.launch(_ -> {
			var r = t.call(tool, args);
			var texts = [for (c in r.content) if (c.type == "text") (c.text : String)];
			// (one line: its whitespace collapsed, at most 240 characters)
			var first = ~/\s+/g.replace(texts.length == 0 ? "" : texts[texts.length - 1], " ");
			reply('$tool: ' + (first.length > 240 ? first.substr(0, 240) + "…" : first));
		});
	}
}
