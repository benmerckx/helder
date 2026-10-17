import hxmc.web.Islands;

// The demo's islands bundle (JavaScript): what the loader loads for them
//   haxe -cp packages/view/src -cp packages/web/src -cp packages/web/examples \
//     -D hxmc.view.renderer.dom=hxmc.web.DomRenderer -main DemoBundle -dce full -js islands.js
class DemoBundle {
	static function main()
		Islands.start([DemoIslands.Counter, DemoIslands.Mismatch, DemoIslands.Lab]);
}
