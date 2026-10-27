// Model.of types a model's names from its file: a name it does not have
// must not compile (npm test -- 3d expects "has no field bal").
class ModelTypo {
	static function main() {
		var m = helder.scene.render.Model.of("sample.glb");
		trace(m.nodes.bal);
	}
}
