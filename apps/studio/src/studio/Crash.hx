package studio;

import haxe.CallStack;
import helder.view.*;
import helder.view.Flow.*;
import studio.Theme.c;

using StringTools;

// The studio's own error that nothing caught (an event's or a frame's,
// helder.os.App.onError; a view's making, Errored): shown over the studio,
// which goes on without what threw, with where it was thrown and how it
// got there (hxmc's stacks, natively); Reload makes the studio's view
// again (Studio.reload), the project and its previews kept. In the browser
// the module has no stacks of its own (no frame records in WebAssembly):
// an error out of an event ends it, and the page shows its frames instead
// (studio.mjs's crashed).
class Crash implements Markup {
	public final message:String;
	// the file and line it was thrown at ("" when unknown)
	public final where:String;
	public final stack:String;

	function new(message, where, stack) {
		this.message = message;
		this.where = where;
		this.stack = stack;
	}

	public static function of(e:Dynamic):Crash {
		if (!(e is haxe.Exception)) return new Crash(Std.string(e), "", "");
		var x:haxe.Exception = e, items = x.stack.asArray();
		var where = "";
		for (i in items) switch i {
			case FilePos(_, file, line, _):
				where = '$file:$line';
				break;
			case _:
		}
		return new Crash(x.message, where, CallStack.toString(x.stack).trim());
	}

	public static function view(studio:Studio, crash:Crash, reload:Void->Void):View
		return <view tag="crash-layer" slot="floating" position="absolute" inset={0} align-items="center" justify="center" padding={16}
			background="rgba(11,11,13,0.72)">
			<view tag="crash" role="alertdialog" label="The studio stopped" width={560} max-width="100%" max-height="100%" padding={16} row-gap={10}
				background={c("bg")} radius={Theme.RADIUS_M} shadow={Theme.POPOVER} border-width={1} border-color={c("line")}>
				<text font-size={13} font-weight={Theme.MEDIUM}>The studio stopped what it was doing</text>
				<text color={c("red")}>{crash.message}</text>
				<Show when={crash.where != ""}>
					<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg2")}>{crash.where}</text>
				</Show>
				<Show when={crash.stack != ""}>
					<scroll max-height={240} min-height={0} padding={8} radius={Theme.RADIUS} background={c("canvas")}>
						<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg3")}>{crash.stack}</text>
					</scroll>
				</Show>
				<view direction="row" justify="end" column-gap={8}>
					<view:button tag="crash-reload" slot="primary" role="button" label="Reload" focusable onPress={reload}>
						<text>Reload</text>
					</view:button>
				</view>
			</view>
		</view>;
}
