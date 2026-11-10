import Puzzle.Vec;

// What the moth flies over: where it lands below a point (null: nothing,
// it hovers) and a point brought to the plane it flies in.
interface Ground {
	function ground(x:Float, y:Float):Null<Vec>;
	function flat(x:Float, y:Float, z:Float):Vec;
}
