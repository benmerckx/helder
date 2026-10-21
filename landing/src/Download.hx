import Compiler;
import js.Browser.document;
import js.Browser.navigator;
import js.html.Element;
import js.lib.Promise;
import js.lib.Uint8Array;

// The native download: the visitor's OS and CPU (the browser's client hints
// where it has them, its user agent else; a phone: pick a desktop), the
// picker of the six targets, the build packed (a zip keeping the
// executable's mode and the files it loads; a bare .exe for Windows) and
// how to run it.
class Download {
	public static final LABELS = [
		"linux-x86_64" => ["Linux", "x86-64", "🐧"],
		"linux-arm64" => ["Linux", "ARM64", "🐧"],
		"macos-arm64" => ["macOS", "Apple silicon", "⌘"],
		"macos-x86_64" => ["macOS", "Intel", "⌘"],
		"windows-x86_64" => ["Windows", "x86-64", "⊞"],
		"windows-arm64" => ["Windows", "ARM64", "⊞"],
	];

	public static var detected(default, null):{target:String, guessed:Bool} = {target: "windows-x86_64", guessed: true};
	public static var chosen:{target:String, guessed:Bool} = detected;

	public static function detect():Promise<Bool> {
		var ua = navigator.userAgent;
		var os:Null<String> = ~/Windows/.match(ua) ? "windows" : ~/iPhone|iPad|iPod|Android/.match(ua) ? null : ~/Mac OS X|Macintosh/.match(ua) ? "macos" : ~/Linux|X11|CrOS/.match(ua) ? "linux" : null;
		// (an iPad asks for the desktop site: a Mac with a touch screen)
		if (os == "macos" && navigator.maxTouchPoints > 1) os = null;
		var arch:Null<String> = ~/aarch64|arm64/i.match(ua) ? "arm64" : null;
		var data:Dynamic = (cast navigator).userAgentData;
		var hints:Promise<Dynamic> = data != null ? data.getHighEntropyValues(["architecture", "bitness"]) : Promise.resolve(null);
		return hints.catchError(_ -> null).then(h -> {
			if (h != null && h.architecture == "arm") arch = "arm64" else if (h != null && h.architecture == "x86") arch = "x86_64";
			// (Safari says Intel on Apple silicon too: most Macs now are arm64)
			if (arch == null) arch = os == "macos" ? "arm64" : "x86_64";
			detected = {target: '${os ?? "windows"}-$arch', guessed: os == null};
			chosen = detected;
			label();
			true;
		});
	}

	public static function label() {
		var l = LABELS[chosen.target];
		document.getElementById("dl-target").textContent = chosen.guessed ? "pick your desktop ▸" : '${l[0]} · ${l[1]}';
	}

	public static function picker(open:Bool, targets:Array<String>, onPick:String->Void) {
		var ul = document.getElementById("targets");
		ul.hidden = !open;
		document.getElementById("pick").setAttribute("aria-expanded", Std.string(open));
		if (!open) return;
		ul.innerHTML = "";
		for (t in targets) {
			var l = LABELS[t];
			var li = document.createLIElement();
			li.setAttribute("role", "option");
			li.tabIndex = -1;
			li.dataset.target = t;
			li.setAttribute("aria-selected", Std.string(t == chosen.target));
			li.innerHTML = '<span class="os-icon">${l[2]}</span><span>${l[0]} · ${l[1]}</span>${t == detected.target && !detected.guessed ? "<small>this machine</small>" : ""}';
			li.onclick = () -> {
				chosen = {target: t, guessed: false};
				picker(false, targets, onPick);
				label();
				onPick(t);
			}
			ul.append(li);
		}
		var sel:Element = ul.querySelector('[aria-selected="true"]') ?? ul.firstElementChild;
		sel?.focus();
	}

	// the build handed over as a file
	public static function save(e:Example, target:String, file:String, bytes:Uint8Array, assets:Array<Array<Dynamic>>):String {
		var blob, name;
		if (StringTools.startsWith(target, "windows") && assets.length == 0) {
			blob = new js.html.Blob([bytes], {type: "application/vnd.microsoft.portable-executable"});
			name = e.main + ".exe";
		} else {
			var files:Array<Zip.ZipFile> = [{name: file, data: bytes, mode: 493}];
			for (a in assets) files.push({name: a[0], data: a[1]});
			blob = new js.html.Blob([Zip.make(files)], {type: "application/zip"});
			name = '${e.main}-$target.zip';
		}
		var a = document.createAnchorElement();
		a.href = js.html.URL.createObjectURL(blob);
		a.download = name;
		document.body.append(a);
		a.click();
		a.remove();
		haxe.Timer.delay(() -> js.html.URL.revokeObjectURL(a.href), 30000);
		return name;
	}

	public static function howToRun(e:Example, target:String, name:String) {
		var l = LABELS[target];
		var exe = e.main;
		var body = switch target.split("-")[0] {
			case "macos": '<p>Unzip it, then in a terminal: <code>xattr -d com.apple.quarantine $exe && ./$exe</code></p><p>It is signed ad hoc, not notarized, so macOS quarantines a download until you say otherwise. Or right-click it and choose <em>Open</em>.</p>';
			case "linux": '<p>Unzip it and run <code>./$exe</code>. It loads your GPU\'s drivers through glibc (X11, GL or Vulkan via Mesa).</p>';
			case _: '<p>Run <code>$name</code>. SmartScreen does not know this program yet: <em>More info</em>, then <em>Run anyway</em>.</p>';
		}
		document.getElementById("sheet-title").textContent = '${e.title} for ${l[0]} · ${l[1]}';
		document.getElementById("sheet-body").innerHTML = '<p>Compiled from the same Haxe source, with your edits, by the compiler in this tab: no server, no toolchain.</p>$body';
		document.getElementById("sheet").hidden = false;
		document.getElementById("sheet-ok").focus();
	}
}
