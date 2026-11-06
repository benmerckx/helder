import helder.os.linux.DBus;
import helder.os.linux.Portal;

// helder.os's D-Bus client against a real dbus-daemon (the dbus lane,
// Linux: a private session bus started for it): Hello, a call of the bus
// (ListNames), a service's half (a name requested, a call answered, a
// signal), then the FileChooser portal's OpenFile against a stand-in portal
// on a thread of its own (its call's arguments read back, its Response
// signal's URI as the path picked).
class DBusTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('DBusTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		var a = DBus.session();
		check("connected, Hello", a != null && StringTools.startsWith(a.name, ":"), a == null ? "no bus" : a.name);
		if (a == null) Sys.exit(1);
		var names = a.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames", "", [], 5);
		check("ListNames", names != null && (names.body[0] : Array<String>).indexOf(a.name) >= 0);
		// (a service's loop: polled without waiting, a call not waited for, an error answered)
		// (what came is the bus's, NameAcquired, or nothing; not waited for)
		var t0 = Sys.time(), first = a.poll();
		check("poll: no wait", Sys.time() - t0 < 0.1 && (first == null || first.sender == "org.freedesktop.DBus"));
		var b = DBus.session();
		var serial = b.callLater(a.name, "/org/example/x", "org.example.X", "Hello", "s", ["hi"]);
		var got:Null<DBusMessage> = null, until = Sys.time() + 5;
		while (got == null && Sys.time() < until) {
			got = a.poll();
			if (got != null && got.member != "Hello") got = null;
			if (got == null) Sys.sleep(0.01);
		}
		check("poll: the call come", got != null && got.path == "/org/example/x" && got.body[0] == "hi");
		if (got != null) a.error(got, "org.example.Error.No", "not here");
		// (the bus's NameAcquired first)
		var answer = b.next(5);
		while (answer != null && answer.replySerial != serial)
			answer = b.next(5);
		check("error: the caller's", answer != null && answer.type == DBus.ERROR && answer.replySerial == serial && answer.errorName == "org.example.Error.No"
			&& answer.body[0] == "not here", answer == null ? "none" : answer.errorName);
		b.close();
		// (a stand-in portal: answers OpenFile with its request's path, then the Response)
		var seen:Array<Dynamic> = [];
		sys.thread.Thread.create(() -> {
			var p = DBus.session();
			p.requestName(Portal.DESTINATION);
			while (true) {
				var m = p.next(5);
				if (m == null) break;
				if (m.type != DBus.METHOD_CALL || m.member != "OpenFile") continue;
				seen = m.body;
				var token = "";
				for (kv in (m.body[2] : Array<Dynamic>))
					if (kv[0] == "handle_token") token = (kv[1] : Variant).value;
				var path = Portal.PATH + "/request/" + m.sender.substr(1).split(".").join("_") + "/" + token;
				p.reply(m, "o", [path]);
				Sys.sleep(0.1);
				p.signal(path, "org.freedesktop.portal.Request", "Response", "ua{sv}", [0, [["uris", new Variant("as", ["file:///tmp/photos/caf%C3%A9%202.jpg"])]]], m.sender);
				break;
			}
		});
		Sys.sleep(0.3);
		var picked = Portal.openFile(a, "x11:1a2b", "Open an image", [{name: "Images", extensions: ["jpg", "png"]}], 10);
		check("OpenFile: the URI picked as a path", picked == "/tmp/photos/café 2.jpg", picked == null ? "null" : picked);
		check("OpenFile: its parent, title and filters", seen.length == 3 && seen[0] == "x11:1a2b" && seen[1] == "Open an image" && haxe.Json.stringify(optionOf(seen[2], "filters")) == '[["Images",[[0,"*.jpg"],[0,"*.png"]]]]',
			seen.length == 3 ? haxe.Json.stringify(optionOf(seen[2], "filters")) : "no call");
		Sys.exit(failed > 0 ? 1 : 0);
	}

	static function optionOf(options:Array<Dynamic>, name:String):Dynamic {
		for (kv in options)
			if (kv[0] == name) return (kv[1] : Variant).value;
		return null;
	}
}
