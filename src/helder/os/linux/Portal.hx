package helder.os.linux;

import helder.os.linux.DBus;

// xdg-desktop-portal's FileChooser (the desktop's own open dialog, GTK's,
// KDE's, a sandbox's) over the session bus: OpenFile with the filters, its
// request's Response signal waited for (the request's path known before
// the call: a handle_token, so that no Response is missed), the file's URI
// back as a path. null: cancelled, or no portal (the caller's own picker).
class Portal {
	public static inline var DESTINATION = "org.freedesktop.portal.Desktop";
	public static inline var PATH = "/org/freedesktop/portal/desktop";

	static var tokens = 0;

	// parent: X11's "x11:<window in hex>" (or ""); filters: a name and extensions each
	public static function openFile(bus:DBus, parent:String, title:String, filters:Array<{name:String, extensions:Array<String>}>, seconds = 3600.0):Null<String> {
		var token = "helder" + (++tokens) + "_" + Std.random(1000000);
		var sender = bus.name.substr(1).split(".").join("_");
		var request = PATH + "/request/" + sender + "/" + token;
		bus.addMatch("type='signal',interface='org.freedesktop.portal.Request',member='Response',path='" + request + "'");
		var f:Array<Dynamic> = [for (x in filters) [x.name, [for (e in x.extensions) ([0, "*." + e] : Array<Dynamic>)]]];
		var options:Array<Dynamic> = [
			["handle_token", new Variant("s", token)],
			["modal", new Variant("b", true)],
			["multiple", new Variant("b", false)]
		];
		if (f.length > 0) {
			options.push(["filters", new Variant("a(sa(us))", f)]);
			options.push(["current_filter", new Variant("(sa(us))", f[0])]);
		}
		var r = bus.call(DESTINATION, PATH, "org.freedesktop.portal.FileChooser", "OpenFile", "ssa{sv}", [parent, title, options], 10);
		if (r == null || r.type != DBus.METHOD_RETURN) return null;
		// (an older portal's own request path)
		var path:String = r.body[0] != null ? r.body[0] : request;
		var until = Sys.time() + seconds;
		while (Sys.time() < until) {
			var m = bus.next(1);
			if (m == null || m.type != DBus.SIGNAL || m.member != "Response" || m.path != path) continue;
			if (m.body[0] != 0) return null;
			for (kv in (m.body[1] : Array<Dynamic>))
				if (kv[0] == "uris") {
					var uris:Array<String> = (kv[1] : Variant).value;
					var paths = helder.os.UriList.paths(uris.join("\n"));
					return paths.length > 0 ? paths[0] : null;
				}
			return null;
		}
		return null;
	}
}
