package helder.cli;

using StringTools;

// helder.json: the app's settings at the project's root, by target, and
// where each is published (helder.json.schema at helder.build/schema/helder.json):
//
//   {
//     "$schema": "https://helder.build/schema/helder.json",
//     "name": "Little Skies",              the app's name (the page's title, the stores')
//     "label": "Skies",                    the launcher's and home screen's label (else name)
//     "description": "Mini golf in the sky.",
//     "id": "build.helder.littleskies",    both phones' id (else org.helder.<name>)
//     "version": "1.2.0", "build": 3,      the version shown, and the build number (1)
//     "entry": "src/LittleSkies.hx",       what helder builds from the directory (else its main file)
//     "icon": "icon.svg",                  or {"any": "icon.svg", "maskable": "maskable.png", "monochrome": "mono.svg"}
//     "colors": {"theme": "#3ED6C3", "background": "#060912"},
//     "splash": {"image": "splash.svg", "background": "#060912", "dark": {"image": "splash-dark.svg", "background": "#000"}},
//     "display": "fullscreen",             fullscreen, standalone, minimal-ui, browser
//     "orientation": "landscape",          any, natural, portrait(-primary, -secondary), landscape(-primary, -secondary)
//     "lang": "en", "dir": "ltr", "categories": ["games"], "fileHandlers": [...] (the web manifest's file_handlers)
//     "run": {                             helder.run: <name>.helder.run (`helder publish`)
//       "name": "little-skies",            the address (else name, made a slug)
//       "listed": true,                    in helder.build/explore (false)
//       "kind": "game",                    game, app or tool
//       "tags": ["sports"],
//       "source": "https://github.com/...",
//       "screenshots": ["shots/1.png"]     (an override; else the stories with store: true, else one of the program)
//     },
//     "targets": {
//       "android": {"package", "minSdk", "targetSdk", "permissions", "key", "signing", "serviceAccount", "adaptiveIcon",
//                   "publish": ["play"] or [{"to": "play", "track": "internal"}], "store": "<url>"},
//       "ios": {"bundleId", "minVersion", "entitlements", "signing", "sdk", "nonExemptEncryption", "privacy",
//               "publish": ["testflight"], "store": "<url>"},
//       "macos": {"publish": ["notarize"], "store": "<url>"}, "windows": {"store": "<url>"}, "linux": {"store": "<url>"}
//     }
//   }
//
// No secrets: signing names files (a key's file is better given by its
// environment variable: Android's, Ios'). Read as the web manifest it
// stands for (toManifest: the W3C members and a "helder" member, what
// Manifest.parse takes), its mistakes named by helder.json's members; the
// web build writes that manifest without its "helder" member (webText).
// `helder migrate` writes one from a helder.webmanifest (fromManifest).
class HelderJson {
	public static inline var FILE = "helder.json";
	public static inline var SCHEMA = "https://helder.build/schema/helder.json";

	static final TOP = [
		"$schema", "name", "label", "description", "id", "version", "build", "entry", "icon", "colors", "splash", "display", "orientation", "lang", "dir",
		"categories", "fileHandlers", "run", "targets"
	];
	public static final RUN = ["name", "listed", "kind", "tags", "source", "screenshots"];
	public static final KINDS = ["game", "app", "tool"];
	public static final TARGETS = ["web", "android", "ios", "macos", "windows", "linux"];
	// each target's destinations for `helder publish` (helder.run is run's)
	public static final DESTINATIONS:Map<String, Array<String>> = [
		"web" => [], "android" => ["play"], "ios" => ["testflight"], "macos" => ["notarize"], "windows" => [], "linux" => []
	];
	static final OWN = ["publish", "store"];
	static final ICON = ["any", "maskable", "monochrome"];
	// (a name a DNS label takes, for run.name)
	static final NAME = ~/^[a-z0-9](?:[a-z0-9]|-(?!-))*[a-z0-9]$/;

	// the text read: the web manifest it stands for (its "helder" member
	// helder's), its run and targets' own; mistakes thrown naming the member
	public static function parse(text:String):{manifest:Dynamic, run:Null<RunConfig>, destinations:Array<Destination>, stores:haxe.DynamicAccess<String>} {
		var j:Dynamic = try haxe.Json.parse(text) catch (e:Dynamic) throw '$FILE: not JSON ($e)';
		if (!isObject(j)) throw '$FILE: not a JSON object';
		known(j, TOP, "the top level");
		var m:Dynamic = {};
		for (k in ["name", "description", "lang", "dir", "categories", "display", "orientation"]) copy(j, k, m, k);
		copy(j, "label", m, "short_name");
		copy(j, "fileHandlers", m, "file_handlers");
		var c:Dynamic = j.colors;
		if (c != null) {
			known(c, ["theme", "background"], "colors");
			copy(c, "theme", m, "theme_color");
			copy(c, "background", m, "background_color");
		}
		var icon:Dynamic = j.icon;
		if (icon != null) {
			var icons:Array<Dynamic> = [];
			if (Std.isOfType(icon, String)) icons.push(image(icon, "any"));
			else {
				known(icon, ICON, "icon");
				for (p in ICON) {
					var src:Dynamic = Reflect.field(icon, p);
					if (src == null) continue;
					if (!Std.isOfType(src, String)) throw '$FILE: icon.$p: a file (a string)';
					icons.push(image(src, p));
				}
			}
			m.icons = icons;
		}
		var h:Dynamic = {};
		copy(j, "id", h, "id");
		copy(j, "version", h, "version");
		copy(j, "build", h, "build");
		var s:Dynamic = j.splash;
		if (s != null) {
			known(s, ["image", "background", "dark"], "splash");
			var hs:Dynamic = {};
			copy(s, "image", hs, "image");
			copy(s, "background", hs, "background_color");
			if (s.dark != null) {
				known(s.dark, ["image", "background"], "splash.dark");
				var d:Dynamic = {};
				copy(s.dark, "image", d, "image");
				copy(s.dark, "background", d, "background_color");
				hs.dark = d;
			}
			h.splash = hs;
		}
		var destinations:Array<Destination> = [], stores = new haxe.DynamicAccess<String>();
		var t:Dynamic = j.targets;
		if (t != null) {
			known(t, TARGETS, "targets");
			for (name in TARGETS) {
				var o:Dynamic = Reflect.field(t, name);
				if (o == null) continue;
				if (!isObject(o)) throw '$FILE: targets.$name: an object';
				if (name != "android" && name != "ios") known(o, OWN, 'targets.$name');
				var rest:Dynamic = {};
				for (k in Reflect.fields(o)) if (!OWN.contains(k)) Reflect.setField(rest, k, Reflect.field(o, k));
				if (name == "android" || name == "ios") Reflect.setField(h, name, rest);
				var store:Dynamic = o.store;
				if (store != null) {
					if (!Std.isOfType(store, String) || !~/^https:\/\/[^\s]+$/.match(store)) throw '$FILE: targets.$name.store: an https URL';
					stores.set(name, store);
				}
				var p:Dynamic = o.publish;
				if (p == null) continue;
				if (!Std.isOfType(p, Array)) throw '$FILE: targets.$name.publish: an array of destinations (${list(name)})';
				for (k => d in (p : Array<Dynamic>)) {
					var to:Dynamic = Std.isOfType(d, String) ? d : isObject(d) ? d.to : null;
					if (!Std.isOfType(to, String) || !DESTINATIONS[name].contains(to))
						throw '$FILE: targets.$name.publish[$k]: ${haxe.Json.stringify(d)}: ${list(name)}';
					var options:Dynamic = Std.isOfType(d, String) ? {} : d;
					if (to == "play") known(options, ["to", "track", "draft"], 'targets.$name.publish[$k]');
					else known(options, ["to"], 'targets.$name.publish[$k]');
					destinations.push({target: name, to: to, track: options.track, draft: options.draft == true});
				}
			}
		}
		if (Reflect.fields(h).length > 0) m.helder = h;
		var run = j.run == null ? null : runConfig(j.run, j.name);
		// (the manifest's own checks, named as helder.json names them)
		try Manifest.parse(haxe.Json.stringify(m), FILE) catch (e:Dynamic) throw rename(Std.string(e));
		return {manifest: m, run: run, destinations: destinations, stores: stores};
	}

	// the run block: its name a DNS label (else the app's name as one)
	static function runConfig(r:Dynamic, appName:Dynamic):RunConfig {
		if (!isObject(r)) throw '$FILE: run: an object';
		known(r, RUN, "run");
		var name:Dynamic = r.name;
		if (name != null && !Std.isOfType(name, String)) throw '$FILE: run.name: a string';
		if (name == null && Std.isOfType(appName, String)) name = slug(appName);
		if (name != null) {
			var why = nameProblem(name);
			if (why != null) throw '$FILE: run.name: "$name" $why';
		}
		if (r.listed != null && r.listed != true && r.listed != false) throw '$FILE: run.listed: true or false';
		if (r.kind != null && !KINDS.contains(r.kind)) throw '$FILE: run.kind: ${haxe.Json.stringify(r.kind)}: ${KINDS.join(", ")}';
		var tags:Dynamic = r.tags;
		if (tags != null && !(Std.isOfType(tags, Array) && (tags : Array<Dynamic>).length <= 5 && Lambda.foreach((tags : Array<Dynamic>), x -> Std.isOfType(x, String) && ~/^[a-z0-9][a-z0-9-]{0,23}$/.match(x))))
			throw '$FILE: run.tags: at most 5 tags, each lowercase letters, digits and -';
		if (r.source != null && !(Std.isOfType(r.source, String) && ~/^https:\/\/[^\s]+$/.match(r.source))) throw '$FILE: run.source: an https URL';
		var shots:Dynamic = r.screenshots;
		if (shots != null && !(Std.isOfType(shots, Array) && (shots : Array<Dynamic>).length <= 8 && Lambda.foreach((shots : Array<Dynamic>), x -> Std.isOfType(x, String) && Manifest.local(x))))
			throw '$FILE: run.screenshots: at most 8 image files beside helder.json';
		return {
			name: name,
			listed: r.listed == true,
			kind: r.kind,
			tags: tags == null ? [] : [for (t in (tags : Array<Dynamic>)) Std.string(t)],
			source: r.source,
			screenshots: shots == null ? null : [for (s in (shots : Array<Dynamic>)) Std.string(s)]
		};
	}

	// why a name is not a helder.run address (null: it is one)
	public static function nameProblem(name:String):Null<String> {
		if (name.length < 3 || name.length > 40) return "is not 3 to 40 characters";
		if (!NAME.match(name)) return "is not lowercase letters, digits and single hyphens (not first or last)";
		if (~/^[0-9]+$/.match(name)) return "is only digits";
		return null;
	}

	// a name as an address: lowercase, its other characters hyphens
	public static function slug(name:String):String {
		var s = ~/[^a-z0-9]+/g.replace(name.toLowerCase(), "-");
		s = ~/^-+|-+$/g.replace(s, "");
		return s.length > 40 ? ~/-+$/.replace(s.substr(0, 40), "") : s;
	}

	// the entry it names, from its directory (null: none)
	public static function entry(text:String):Null<String> {
		var j:Dynamic = try haxe.Json.parse(text) catch (_:Dynamic) null;
		return j != null && Std.isOfType(j.entry, String) ? j.entry : null;
	}

	// the web manifest a web build writes: the W3C members alone (signing's
	// and the phones' settings are not the browser's)
	public static function webText(manifest:Dynamic):String {
		var w:Dynamic = {};
		for (k in Reflect.fields(manifest)) if (k != "helder") Reflect.setField(w, k, Reflect.field(manifest, k));
		return haxe.Json.stringify(w, null, "  ");
	}

	// `helder migrate`: a helder.webmanifest's text as helder.json's
	public static function fromManifest(text:String):String {
		var m:Dynamic = haxe.Json.parse(text);
		Manifest.parse(text);
		var out = new Ordered();
		out.set("$schema", SCHEMA);
		for (k in ["name"]) out.set(k, Reflect.field(m, k));
		if (m.short_name != null && m.short_name != m.name) out.set("label", m.short_name);
		out.set("description", m.description);
		var h:Dynamic = m.helder ?? {};
		out.set("id", h.id);
		out.set("version", h.version);
		out.set("build", h.build);
		var icons:Array<Dynamic> = m.icons ?? [];
		if (icons.length == 1 && (icons[0].purpose == null || icons[0].purpose == "any")) out.set("icon", icons[0].src);
		else if (icons.length > 0) {
			var o = new Ordered();
			for (i in icons) for (p in ~/\s+/g.split(((i.purpose ?? "any") : String).trim())) if (o.get(p) == null) o.set(p, i.src);
			out.set("icon", o);
		}
		if (m.theme_color != null || m.background_color != null) {
			var c = new Ordered();
			c.set("theme", m.theme_color);
			c.set("background", m.background_color);
			out.set("colors", c);
		}
		var s:Dynamic = h.splash;
		if (s != null) {
			var o = new Ordered();
			o.set("image", s.image);
			o.set("background", s.background_color);
			if (s.dark != null) {
				var d = new Ordered();
				d.set("image", s.dark.image);
				d.set("background", s.dark.background_color);
				o.set("dark", d);
			}
			out.set("splash", o);
		}
		for (k in ["display", "orientation", "lang", "dir", "categories"]) out.set(k, Reflect.field(m, k));
		out.set("fileHandlers", m.file_handlers);
		if (m.screenshots != null) Term.err(Style.status("warning", Warn, '${Manifest.FILE}: its screenshots are the web\'s; helder.json\'s run.screenshots are helder.run\'s (not moved)'));
		if (h.android != null || h.ios != null) {
			var t = new Ordered();
			if (h.android != null) t.set("android", h.android);
			if (h.ios != null) t.set("ios", h.ios);
			out.set("targets", t);
		}
		return out.json("") + "\n";
	}

	// (messages of Manifest.parse, about the manifest helder.json made, in helder.json's names)
	static function rename(message:String):String {
		for (pair in [
			['"helder": {"android": {', 'targets: {"android": {'], ['"helder": {"ios": {', 'targets: {"ios": {'],
			['"helder": {"splash": {"dark": {"background_color"}}}', 'splash.dark.background'],
			['"helder": {"splash": {"background_color"}}', 'splash.background'], ['"helder": {"splash"', 'splash'],
			['"helder": {"build"}', 'build'], ['"helder": {"version"}', 'version'], ['"helder": {"id"}', 'id'],
			['background_color', 'colors.background'], ['theme_color', 'colors.theme'], ['icons[', 'icon['], ['short_name', 'label'],
			['file_handlers', 'fileHandlers']
		])
			message = message.split(pair[0]).join(pair[1]);
		return message;
	}

	static function image(src:String, purpose:String):Dynamic {
		var o:Dynamic = {src: src, purpose: purpose};
		var ext = haxe.io.Path.extension(src).toLowerCase();
		var type = ["svg" => "image/svg+xml", "png" => "image/png", "jpg" => "image/jpeg", "jpeg" => "image/jpeg", "webp" => "image/webp"][ext];
		if (type != null) o.type = type;
		if (ext == "svg") o.sizes = "any";
		return o;
	}

	static function list(target:String):String {
		var d = DESTINATIONS[target];
		return d.length == 0 ? 'none yet for $target' : d.join(", ");
	}

	static function copy(from:Dynamic, k:String, to:Dynamic, as:String) {
		var v:Dynamic = Reflect.field(from, k);
		if (v != null) Reflect.setField(to, as, v);
	}

	static function known(o:Dynamic, keys:Array<String>, path:String) {
		if (!isObject(o)) throw '$FILE: $path: an object';
		for (k in Reflect.fields(o)) if (!keys.contains(k)) throw '$FILE: $path: no member "$k" (${keys.join(", ")})';
	}

	static function isObject(v:Dynamic):Bool
		return v != null && Reflect.isObject(v) && !Std.isOfType(v, String) && !Std.isOfType(v, Array);
}

// helder.json's run block (helder.run)
typedef RunConfig = {
	name:Null<String>,
	listed:Bool,
	kind:Null<String>,
	tags:Array<String>,
	source:Null<String>,
	screenshots:Null<Array<String>>,
}

// a target's destination for `helder publish`
typedef Destination = {
	target:String,
	to:String,
	?track:String,
	draft:Bool,
}

// (JSON written with its keys in the order given, nulls left out: migrate's)
private class Ordered {
	final keys:Array<String> = [];
	final values:Map<String, Dynamic> = [];

	public function new() {}

	public function set(k:String, v:Dynamic) {
		if (v == null) return;
		if (!values.exists(k)) keys.push(k);
		values[k] = v;
	}

	public function get(k:String):Dynamic
		return values[k];

	public function json(indent:String):String {
		var inner = indent + "  ";
		var parts = [for (k in keys) inner + haxe.Json.stringify(k) + ": " + value(values[k], inner)];
		return parts.length == 0 ? "{}" : "{\n" + parts.join(",\n") + "\n" + indent + "}";
	}

	static function value(v:Dynamic, indent:String):String
		return Std.isOfType(v, Ordered) ? (v : Ordered).json(indent) : haxe.Json.stringify(v);
}
