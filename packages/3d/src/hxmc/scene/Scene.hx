package hxmc.scene;

// The root of a scene graph: a node whose world is the scene's space, with
// what a renderer asks of the whole tree.
class Scene extends Node {
	public function new(name = "scene") {
		super(name);
	}

	// f on each visible node (a hidden node hides what is below it), parents first
	public function walkVisible(f:Node->Void)
		visit(this, f);

	static function visit(n:Node, f:Node->Void) {
		if (!n.visible) return;
		f(n);
		for (c in n.children)
			visit(c, f);
	}

	// the first camera in the tree (depth first), or null
	public function firstCamera():Null<Camera> {
		var found:Null<Camera> = null;
		walk(n -> if (found == null && n.camera != null) found = n.camera);
		return found;
	}
}
