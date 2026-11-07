package helder.ui.motion;

// What a node declares of motion for itself and its subtree (Node.motion;
// markup's motion="snappy|default|calm", motion={{duration: 0.3, bounce:
// 0.2}}, motion="0.3 0.1"): one curve for every property, and per
// property class one over it (motion-layout, motion-opacity, motion-color,
// motion-transform, motion-radius, motion-presence: attributes, or the
// fields here); lead and trail: when an edge moves, the edge in the
// direction of travel on lead, the other on trail (a box stretching as it
// goes); textLeads: a text colour moves in half its curve's time, so that a
// theme switch keeps its contrast (on by default). The nearest declaration
// over a node is its (an instant node between: none).
class MotionSpec {
	public var curve:Curve;
	public var layout:Null<Curve> = null;
	public var opacity:Null<Curve> = null;
	public var color:Null<Curve> = null;
	public var transform:Null<Curve> = null;
	public var radius:Null<Curve> = null;
	public var presence:Null<Curve> = null;
	public var lead:Null<Curve> = null;
	public var trail:Null<Curve> = null;
	public var textLeads = true;

	public function new(?curve:Curve)
		this.curve = curve ?? Curve.named("default");

	public static final DEFAULT = new MotionSpec();

	// a spec from what markup gives: a curve (Curve.of), a MotionSpec, or a structure of its fields
	// ({curve, layout, opacity, color, transform, radius, presence, lead, trail, textLeads}; duration
	// and bounce: the curve)
	public static function of(v:Dynamic):Null<MotionSpec> {
		if (v == null || v == false) return null;
		if (Std.isOfType(v, MotionSpec)) return v;
		if (Std.isOfType(v, String) || Std.isOfType(v, Curve) || Std.isOfType(v, Float) || Std.isOfType(v, Int)
			|| Reflect.hasField(v, "duration")) return new MotionSpec(v == true ? null : Curve.of(v));
		var s = new MotionSpec(Curve.of(Reflect.field(v, "curve")));
		s.layout = Curve.of(Reflect.field(v, "layout"));
		s.opacity = Curve.of(Reflect.field(v, "opacity"));
		s.color = Curve.of(Reflect.field(v, "color"));
		s.transform = Curve.of(Reflect.field(v, "transform"));
		s.radius = Curve.of(Reflect.field(v, "radius"));
		s.presence = Curve.of(Reflect.field(v, "presence"));
		s.lead = Curve.of(Reflect.field(v, "lead"));
		s.trail = Curve.of(Reflect.field(v, "trail"));
		if (Reflect.field(v, "textLeads") == false) s.textLeads = false;
		return s;
	}

	// (a copy: one property's curve set on a node whose spec is shared)
	public function copy():MotionSpec {
		var s = new MotionSpec(curve);
		s.layout = layout;
		s.opacity = opacity;
		s.color = color;
		s.transform = transform;
		s.radius = radius;
		s.presence = presence;
		s.lead = lead;
		s.trail = trail;
		s.textLeads = textLeads;
		return s;
	}

	public inline function layoutCurve():Curve
		return layout ?? curve;

	public inline function opacityCurve():Curve
		return opacity ?? curve;

	public inline function colorCurve():Curve
		return color ?? curve;

	public inline function transformCurve():Curve
		return transform ?? curve;

	public inline function radiusCurve():Curve
		return radius ?? curve;

	public inline function presenceCurve():Curve
		return presence ?? curve;
}
