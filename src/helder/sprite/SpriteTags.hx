package helder.sprite;

import helder.ui.view.NodeRenderer;
import helder.view.Render;
import helder.view.graph.Graph;

// The tag for a SpriteBox in ui's markup, imported with
// import helder.sprite.SpriteTags.*:
//
//   <view grow={1} onTap={tap} onPinch={pinch}>
//     <Sprites grow={1} animate onReady={b -> sheet = b.add(image)} onDraw={draw}/>
//   </view>
class SpriteTags {
	public static function Sprites(props:{
		?grow:Float,
		?width:helder.view.graph.Read<Dynamic>,
		?height:helder.view.graph.Read<Dynamic>,
		?style:Dynamic,
		?animate:Bool,
		?background:helder.gfx.Color,
		?onReady:SpriteBatch->Void,
		?onDraw:(SpriteBatch, Float, Float) -> Void,
		?ref:SpriteBox->Void
	}):helder.ui.Node {
		var box = new SpriteBox();
		if (props.animate != null) box.animate = props.animate;
		if (props.background != null) box.background = props.background;
		box.onReady = props.onReady;
		box.onDraw = props.onDraw;
		if (props.grow != null) NodeRenderer.setProperty(box, "grow", props.grow);
		if (props.width != null) bind(box, "width", props.width);
		if (props.height != null) bind(box, "height", props.height);
		if (props.style != null) NodeRenderer.setStyle(box, props.style);
		Graph.onCleanup(box.dispose);
		if (props.ref != null) props.ref(box);
		return box;
	}

	static function bind(n:helder.ui.Node, name:String, v:Dynamic)
		Render.isReactive(v) ? Graph.renderEffect(() -> Render.read(v), x -> NodeRenderer.setProperty(n, name, x)) : NodeRenderer.setProperty(n, name, Render.read(v));
}
