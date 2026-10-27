package helder.web;

#if js
// An island bundle's side (JavaScript): its main names the islands it
// hydrates,
//
//   static function main() Islands.start([Demo.Counter, Demo.Lab]);
//
// and each defined island (Island.all) is handed to the loader
// (globalThis.hxmcIslands, by name): the loader calls it with the island's
// element and its props once the bundle has loaded, and it hydrates the
// element (DomRenderer.hydrate). One bundle may hold several islands.
class Islands {
	// (islands: the definitions this bundle keeps, Island.define's results)
	public static function start(islands:Array<Any>) {
		var registry:Dynamic = js.Syntax.code("globalThis.hxmcIslands || (globalThis.hxmcIslands = {})");
		for (name => i in Island.all) {
			var island = i;
			Reflect.setField(registry, name, (el:js.html.Element, props:Dynamic) -> DomRenderer.hydrate(island.content(props), el));
		}
	}
}
#end
