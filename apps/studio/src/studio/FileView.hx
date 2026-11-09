package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.FileTree.FileKind;
import studio.Theme.c;

using StringTools;

// A file of the tree that is neither a page nor code, in a viewer of its
// kind: an image fitted or at 1:1, its size, format and bytes, and where it
// is used (each line of the project's code and design files naming it); a
// font's specimen (its family, the alphabet, a line at several sizes); any
// other file's kind and size. glTF and audio show their size only (their
// viewers are not made yet).
class FileView implements Markup {
	public static function view(studio:Studio):View {
		var path = studio.shown(), tree = studio.tree;
		if (path == null || tree == null) return null;
		var kind = FileTree.kindOf(path);
		var actual = signal(false);
		return <view tag="file-view" grow={1} min-height={0}>
			<view tag="file-head" direction="row" align-items="center" column-gap={10} height={44} padding="0 14" border-width="0 0 1 0" border-color={c("line")} shrink={0}>
				<image src={icon(kind)} width={Theme.ICON} height={Theme.ICON} color={c("accent")}/>
				<text font-weight={Theme.MEDIUM} max-lines={1}>{haxe.io.Path.withoutDirectory(path)}</text>
				<text font-size={Theme.SMALL} color={c("fg3")} max-lines={1} shrink={1}>{info(studio, path, kind)}</text>
				<view grow={1}/>
				<Show when={kind == Image}>
					<view slot="seg">
						<view:button tag="view-fit" slot="seg-item" role="button" label="Fit" data-on={actual() ? "false" : "true"} onPress={() -> actual(false)}><text>Fit</text></view:button>
						<view:button tag="view-actual" slot="seg-item" role="button" label="1:1" data-on={actual() ? "true" : "false"} onPress={() -> actual(true)}><text>1:1</text></view:button>
					</view>
				</Show>
			</view>
			{switch kind {
				case Image: imageView(studio, path, actual);
				case Font: fontView(path);
				case _: <view grow={1} align-items="center" justify="center" row-gap={6}>
						<image src={icon(kind)} width={32} height={32} color={c("fg3")}/>
						<text color={c("fg2")}>{kind == Model ? "A 3D model: its viewer is not made yet." : kind == Audio ? "A sound: its player is not made yet." : "No viewer for this file."}</text>
					</view>;
			}}
		</view>;
	}

	public static function icon(kind:FileKind):Svg
		return switch kind {
			case Dir: Icons.folder;
			case Design: Icons.penTool;
			case Story: Icons.bookOpen;
			case Code: Icons.fileCode;
			case Image: Icons.image;
			case Font: Icons.font;
			case Model: Icons.model;
			case Audio: Icons.audioLines;
			case Other: Icons.file;
		}

	// (its size on disk, an image's pixels and format)
	static function info(studio:Studio, path:String, kind:FileKind):String {
		var parts = [];
		if (kind == Image) {
			var s = try studio.designs.imageSize(path) catch (_:Dynamic) null;
			if (s != null) parts.push(Math.round(s.w) + " × " + Math.round(s.h));
			parts.push(haxe.io.Path.extension(path).toUpperCase());
		}
		var bytes = size(path);
		if (bytes >= 0) parts.push(bytes < 1024 ? '$bytes B' : bytes < 1024 * 1024 ? Math.round(bytes / 1024) + " KB" : Math.round(bytes / 1024 / 102.4) / 10 + " MB");
		return parts.join(" · ");
	}

	static function size(path:String):Int {
		#if (hxmc.target == "wasm32-wasi")
		return -1;
		#else
		return try sys.FileSystem.stat(path).size catch (_:Dynamic) -1;
		#end
	}

	static function imageView(studio:Studio, path:String, actual:Read<Bool>):View {
		var img:Dynamic = try studio.designs.image(path) catch (e:Dynamic) null;
		var s = try studio.designs.imageSize(path) catch (_:Dynamic) {w: 0.0, h: 0.0};
		var uses = usesOf(studio, path);
		return <view grow={1} min-height={0}>
			<scroll tag="image-stage" grow={1} min-height={0} background={c("canvas")} padding={24}>
				<view min-height="100%" align-items="center" justify="center">
					{img == null ? <text color={c("fg3")}>{"Images are read natively (not in the browser yet)."}</text>
						: <image tag="image-shown" src={img} width={actual() ? s.w : s.w * fit(s)} height={actual() ? s.h : s.h * fit(s)}/>}
				</view>
			</scroll>
			<view tag="image-uses" slot="section" shrink={0} max-height="40%">
				<view slot="section-head"><image src={Icons.fileCode} width={12} height={12}/><text>{uses.length == 0 ? "Not used yet" : "Used in " + uses.length + " place" + (uses.length == 1 ? "" : "s")}</text></view>
				<scroll min-height={0}>
					{[for (u in uses) <view:button slot="nav-item" role="button" label={u.file} onPress={() -> studio.openCode(u.path)}>
						<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg2")} shrink={0}>{u.file + ":" + u.line}</text>
						<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg3")} max-lines={1} text-overflow="ellipsis" shrink={1}>{u.text}</text>
					</view:button>]}
				</scroll>
			</view>
		</view>;
	}

	// (fitted: at most 720 by 440 points, never past 1:1)
	static function fit(s:{w:Float, h:Float}):Float
		return Math.min(1, Math.min(720 / Math.max(1, s.w), 440 / Math.max(1, s.h)));

	// each line of the project's code and design files naming the file (by its name)
	public static function usesOf(studio:Studio, path:String):Array<{path:String, file:String, line:Int, text:String}> {
		var name = haxe.io.Path.withoutDirectory(path), out = [];
		for (f in studio.project.sources()) {
			var text = try Files.read(f) catch (_:Dynamic) continue;
			if (text.indexOf(name) < 0) continue;
			var lines = text.split("\n");
			for (i in 0...lines.length)
				if (lines[i].indexOf(name) >= 0) out.push({path: f, file: studio.tree.relative(f), line: i + 1, text: lines[i].trim()});
		}
		return out;
	}

	// a font's specimen: the face added to the studio's fonts, its family drawn
	static function fontView(path:String):View {
		var family = try {
			#if (hxmc.target == "wasm32-wasi")
			null;
			#else
			var faces = helder.text.SystemFonts.get().add(sys.io.File.getBytes(path));
			faces.length == 0 ? null : faces[0].family;
			#end
		} catch (_:Dynamic) null;
		if (family == null) return <view grow={1} align-items="center" justify="center"><text color={c("fg3")}>{"This font could not be read here."}</text></view>;
		return <scroll tag="font-specimen" grow={1} min-height={0} padding="20 24" row-gap={14}>
			<text font-family={family} font-size={64} color={c("fg")}>Aa</text>
			<text font-family={family} font-size={20} color={c("fg")}>{family}</text>
			<text font-family={family} font-size={16} color={c("fg2")}>ABCDEFGHIJKLMNOPQRSTUVWXYZ</text>
			<text font-family={family} font-size={16} color={c("fg2")}>abcdefghijklmnopqrstuvwxyz 0123456789</text>
			{[for (size in [12, 16, 24, 36]) <view direction="row" align-items="baseline" column-gap={12}>
				<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg3")} width={28}>{Std.string(size)}</text>
				<text font-family={family} font-size={size} color={c("fg")} max-lines={1}>Sphinx of black quartz, judge my vow.</text>
			</view>]}
		</scroll>;
	}
}
