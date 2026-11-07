// title: Code editor
// summary: helder.ui.code: a large TSX file highlighted as it is edited, multi-cursor, find and replace, diagnostics and decorations
// tags: ui, text input, code
// demo: canvas 900x640
import helder.syntax.Document;
import helder.ui.*;
import helder.ui.code.CodeEditor;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;

// A code editor (helder.ui.code.CodeEditor) on a TSX file: the file given
// as the program's argument (`helder run examples/code-editor -- app.tsx`),
// else one made here, 2,000 lines of components. Its first <view> element
// found by helder.syntax and decorated (as the studio marks what is
// selected on its canvas), its TODO comments given as diagnostics (as the
// compiler service's are), the caret's line and column in the status bar.
// Keys: the CodeAction bindings (secondary-D, secondary-F, secondary-G...).
class Editor implements Markup {
	static function main() {
		var path:Null<String> = null, text = "";
		#if sys
		var args = Sys.args();
		if (args.length > 0) {
			path = args[0];
			text = try sys.io.File.getContent(path) catch (e:Dynamic) null;
		}
		#end
		if (text == null || text == "") {
			path = "sample.tsx";
			text = sample(2000);
		}
		var editor = new CodeEditor(text, path);
		var status = new TextNode(editor.status(), "status");
		editor.view.onUpdate = () -> status.text = editor.status();
		decorate(editor);
		UiWindow.run(<Surface title="Code editor" width={900} height={640}>
			<view grow={1} font-family="DejaVu Sans" font-size={12}>
				<view tag="toolbar" direction="row" padding="6 12" column-gap={12} background="#f6f8fa">
					<text tag="file" font-weight={700}>{path}</text>
					<text color="#57606a">{editor.model.lineCount + " lines"}</text>
				</view>
				{editor}
				<view tag="statusbar" direction="row" padding="4 12" background="#f6f8fa">{status}</view>
			</view>
		</Surface>);
	}

	// the first <view> decorated, the TODO comments as diagnostics (info)
	static function decorate(editor:CodeEditor) {
		var text = editor.text;
		var doc = Document.parse(text, StringTools.endsWith(editor.path ?? "", ".hx") ? Haxe : Tsx);
		var views = doc.elementsNamed("view");
		if (views.length > 0) editor.addDecoration(views[0].start, views[0].end, Color.rgba(0x3B82F6, 0.08), Color.rgba(0x3B82F6, 0.6));
		var list:Array<helder.compiler.service.Diagnostic> = [];
		var lines = text.split("\n");
		for (i in 0...lines.length) {
			var at = lines[i].indexOf("TODO");
			if (at >= 0) list.push({file: null, line: i + 1, column: at + 1, endColumn: at + 5, severity: "info", message: "TODO: " + StringTools.trim(lines[i].substr(at + 4))});
		}
		editor.setDiagnostics(list);
	}

	// a TSX file of n lines: components of a list app, numbered
	public static function sample(n:Int):String {
		var out = ["// A sample of components (examples/code-editor): each block a component and its list.",
			"import { signal, memo, For, Show } from \"helder/view\";", ""];
		var k = 0;
		while (out.length < n) {
			for (l in BLOCK.split("\n"))
				out.push(StringTools.replace(l, "$N", Std.string(k)));
			k++;
		}
		out.resize(n);
		return out.join("\n") + "\n";
	}

	static final BLOCK = "/* Item$N: a row of the list, its title and its state.
   Rendered by List$N below. */
export type Item$N = { id: number; title: string; done: boolean };

const items$N = signal<Item$N[]>([]);
const query$N = signal(\"\");
const re$N = /item-[0-9]+/g;

// TODO: keyboard order for List$N
export function List$N(props: { title: string; limit?: number }) {
	const shown = memo(() => items$N().filter((i) => i.title.includes(query$N())).slice(0, props.limit ?? 10));
	return (
		<view tag=\"list-$N\" row-gap={6} padding={12} background=\"#ffffff\">
			<text font-size={16} font-weight={700}>{`${props.title} (${shown().length})`}</text>
			<For each={shown()}>{(item) => (
				<view direction=\"row\" column-gap={8} align-items=\"center\">
					<text color={item().done ? \"#a1a1aa\" : \"#18181b\"}>{item().title}</text>
				</view>
			)}</For>
			<Show when={shown().length === 0}><text color=\"#a1a1aa\">Nothing here.</text></Show>
		</view>
	);
}
";
}
