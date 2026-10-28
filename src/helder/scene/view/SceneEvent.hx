package helder.scene.view;

import helder.gfx.shader.Vec3;
import helder.scene.Node as SceneGraphNode;
import helder.ui.Event;

// what a scene node's listener gets: the node hit (the nearest whose mesh's
// bounds the pointer's ray crossed at its press), where, how far, the ui's
// event (null for a gesture's: gesture, a recogniser of the box's); the node
// whose listener runs (current), stop() to go no further up. One per
// <Scene> box, refilled for each dispatch: copy what must outlive the call.
class SceneEvent {
	public var node(default, null):SceneGraphNode = SceneGraphNode.NONE;
	public var point(default, null):Vec3 = new Vec3(0, 0, 0);
	public var distance(default, null) = 0.0;
	public var event(default, null):Null<Event> = null;
	public var gesture(default, null):Null<helder.ui.gesture.Gesture> = null;
	// the pointer's (event's or gesture's): 0 the mouse, else a finger's or a pen's slot
	public var pointerId(default, null) = 0;
	public var current(default, null):SceneGraphNode = SceneGraphNode.NONE;
	public var stopped(default, null) = false;

	public function new() {}

	public function stop()
		stopped = true;

	@:allow(helder.scene.view) function set(node:SceneGraphNode, point:Vec3, distance:Float, event:Null<Event>, gesture:Null<helder.ui.gesture.Gesture>,
			pointerId:Int):SceneEvent {
		this.node = current = node;
		this.point = point;
		this.distance = distance;
		this.event = event;
		this.gesture = gesture;
		this.pointerId = pointerId;
		stopped = false;
		return this;
	}
}
