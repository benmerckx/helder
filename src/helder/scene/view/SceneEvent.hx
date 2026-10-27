package helder.scene.view;

import helder.gfx.shader.Vec3;
import helder.scene.Node as SceneGraphNode;
import helder.ui.Event;

// what a scene node's listener gets: the node hit (the nearest whose mesh's
// bounds the pointer's ray crosses), where, how far, the ui's event; the
// node whose listener runs (current), stop() to go no further up
class SceneEvent {
	public final node:SceneGraphNode;
	public final point:Vec3;
	public final distance:Float;
	public final event:Event;
	public var current(default, null):SceneGraphNode;
	public var stopped(default, null) = false;

	public function new(node, point, distance, event) {
		this.node = node;
		this.point = point;
		this.distance = distance;
		this.event = event;
		current = node;
	}

	public function stop()
		stopped = true;
}
