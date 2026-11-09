package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import studio.Theme.c;
#if (hxmc.target == "wasm32-wasi")
import studio.web.StudioWeb;
import studio.web.StudioWeb.WebText;
#end

// The studio in the browser without a project: a new project (a design
// file), a folder to open (the File System Access API: copied into the
// origin's private file system, OPFS, where projects live), the examples
// bundled with the page, and the projects already in OPFS. Choosing one opens it (the page loads it and
// starts the studio again with it).
class Welcome implements Markup {
	public static function view(studio:Studio):View {
		var examples:Array<Dynamic> = [], projects:Array<Dynamic> = [];
		#if (hxmc.target == "wasm32-wasi")
		examples = haxe.Json.parse(WebText.take(StudioWeb.examples()));
		projects = haxe.Json.parse(WebText.take(StudioWeb.projects()));
		#end
		return <scroll tag="welcome" grow={1} background={c("bg")} color={c("fg")} font-family={Theme.UI} font-size={Theme.BODY}
			ref={(n:Node) -> n.theme = Theme.sheet} align-items="center" padding="56 20">
			<view width="100%" max-width={420} row-gap={6}>
				<text font-weight={Theme.MEDIUM} padding="0 8 14">helder studio</text>
				<view:button tag="new-project" slot="nav-item" role="button" label="New project" focusable onPress={() -> newProject()}>
					<text>New project</text>
				</view:button>
				<view:button tag="open-folder" slot="nav-item" role="button" label="Open a folder…" focusable onPress={() -> openFolder()}>
					<text>Open a folder…</text>
				</view:button>
				{list("Examples", "example-", examples, name -> openExample(name))}
				{list("Projects", "project-", projects, name -> openProject(name))}
			</view>
		</scroll>;
	}

	static function list(title:String, prefix:String, items:Array<Dynamic>, open:String->Void):View
		return <Show when={items.length > 0}>
			<text padding="18 8 4" color={c("fg3")} font-size={Theme.SMALL}>{title}</text>
			<For each={items}>{(r:helder.view.graph.Read<Dynamic>) -> {
				var it:Dynamic = r();
				<view:button tag={prefix + it.name} slot="nav-item" column-gap={12} role="button" label={it.label ?? it.name} focusable onPress={() -> open(it.name)}>
					<text grow={1}>{it.label ?? it.name}</text>
					<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg3")}>{it.screens == null ? "" : it.screens + " screens"}</text>
				</view:button>;
			}}</For>
		</Show>;

	static function newProject() {
		#if (hxmc.target == "wasm32-wasi")
		StudioWeb.new_project();
		#end
	}

	static function openFolder() {
		#if (hxmc.target == "wasm32-wasi")
		StudioWeb.open_folder();
		#end
	}

	static function openExample(name:String) {
		#if (hxmc.target == "wasm32-wasi")
		hxmc.unsafe.Arena.scoped(a -> StudioWeb.open_example(a.cstring(name)));
		#end
	}

	static function openProject(name:String) {
		#if (hxmc.target == "wasm32-wasi")
		hxmc.unsafe.Arena.scoped(a -> StudioWeb.open_project(a.cstring(name)));
		#end
	}
}
