import Board;
import helder.canvas.Painter;

// One greybox screen being played: stepped at Puzzle.STEP, drawn in world
// units (y up), touched at points of the world. A tap acts on what it
// touches; a press elsewhere leads the moth, as in the game.
interface Play {
	var board(default, null):Board;
	var moth(default, null):Flight;
	var solved(default, null):Bool;
	// what happened since asked (the playtests' log)
	var events(default, null):Array<String>;
	function step(dt:Float):Void;
	function draw(c:Painter, t:Float):Void;
	function down(x:Float, y:Float):Void;
	function move(x:Float, y:Float):Void;
	function up():Void;
}
