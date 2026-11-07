package helder.view;

// Where a node was written, in dev builds (-D hxmc.dev) and headless runs
// (-D helder.headless): the markup planner (helder.markup.Plan) tells each
// element it makes the span of its tag in the file (`<` to the closing
// tag's `>`), Haxe markup and TSX alike, and each component the span of its
// call and of its function's definition. A release build has none of this:
// the planner writes no call to it and no node has a field for it.
//
// Offsets are bytes of the file's UTF-8 text (Haxe's positions; TSX's
// UTF-16 positions converted), lines and columns 1-based, end exclusive.
class Source {
	// the file's full path ("/" between its directories)
	public final file:String;
	public final start:Int;
	public final end:Int;
	public final line:Int;
	public final col:Int;
	public final endLine:Int;
	public final endCol:Int;

	public function new(file:String, start:Int, end:Int, line:Int, col:Int, endLine:Int, endCol:Int) {
		this.file = file;
		this.start = start;
		this.end = end;
		this.line = line;
		this.col = col;
		this.endLine = endLine;
		this.endCol = endCol;
	}

	// whether the file's position (a line and column, 1-based) is in the span
	public function holds(line:Int, col:Int):Bool
		return (line > this.line || (line == this.line && col >= this.col)) && (line < endLine || (line == endLine && col < endCol));

	// as the devtools' Ui domain and a headless --tree give it: {file, line, col, end: {line, col}, offsets: [start, end]}
	public function data():Dynamic
		return {
			file: file,
			line: line,
			col: col,
			end: {line: endLine, col: endCol},
			offsets: [start, end]
		};

	public function toString():String
		return '$file:$line:$col-$endLine:$endCol';
}

// A component being mounted: its name, where it is called (its tag's span)
// and where its function is (null: helder's own, from TSX, or not known)
class SourceComponent {
	public final name:String;
	public final call:Source;
	public final definition:Null<Source>;

	public function new(name:String, call:Source, definition:Null<Source>) {
		this.name = name;
		this.call = call;
		this.definition = definition;
	}

	public function data():Dynamic
		return {name: name, call: call.data(), definition: definition == null ? null : definition.data()};
}

// A renderer's node that keeps where it was written (helder.ui's Node, in
// dev builds and headless runs); another renderer's nodes keep nothing
interface Located {
	// its element's span
	var source:Null<Source>;
	// the innermost component mounting it (its own markup, or children given to it)
	var sourceComponent:Null<SourceComponent>;
}
