package helder.scene.view;

// A scene node's events, by attribute (SceneRenderer's @:events): each
// handler given a SceneEvent (the node hit, where, the ui's event or
// gesture), by a <Scene>'s picking. Markup checks a handler against it: a
// function of a SceneEvent or of none; a name not here is no event. Data,
// not code: helder.typescript's manifest and declarations read it.
// SceneRenderer.LISTENERS is its order at run time.
typedef SceneEvents = {
	onPointerDown:SceneEvent,
	onPointerUp:SceneEvent,
	onPointerMove:SceneEvent,
	onPointerEnter:SceneEvent,
	onPointerLeave:SceneEvent,
	onClick:SceneEvent,
	onPointerCancel:SceneEvent,
	onTap:SceneEvent
}
