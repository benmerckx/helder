import helder.web.Islands;

// The demo's islands bundle (JavaScript): what the loader loads for them
//   haxe -cp src -cp examples \
//     -D helder.view.renderer.dom=helder.web.DomRenderer -main DemoBundle -dce full -js islands.js
class DemoBundle {
	static function main()
		Islands.start([DemoIslands.Counter, DemoIslands.Mismatch, DemoIslands.Lab]);
}
