import hxmc.web.Islands;

// lab.js, the examples page's island that calls lab.wasm
// (site/islands/LabIsland.hx; packages/web/examples/Lab.hx)
class LabBundle {
	static function main()
		Islands.start([LabIsland.Lab]);
}
