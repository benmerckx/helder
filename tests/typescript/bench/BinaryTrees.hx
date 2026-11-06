// binary-trees.ts in Haxe (bench.mjs: TypeScript against Haxe)
class TreeNode {
	public var left:Null<TreeNode>;
	public var right:Null<TreeNode>;

	public function new(left, right) {
		this.left = left;
		this.right = right;
	}

	public function check():Int
		return left == null || right == null ? 1 : 1 + left.check() + right.check();
}

class BinaryTrees {
	static function bottomUp(depth:Int):TreeNode
		return depth > 0 ? new TreeNode(bottomUp(depth - 1), bottomUp(depth - 1)) : new TreeNode(null, null);

	static function main() {
		var max = 16;
		Sys.println("stretch " + bottomUp(max + 1).check());
		var longLived = bottomUp(max);
		var depth = 4;
		while (depth <= max) {
			var iterations = 1 << (max - depth + 4);
			var check = 0;
			for (i in 0...iterations) check += bottomUp(depth).check();
			Sys.println('$iterations $depth $check');
			depth += 2;
		}
		Sys.println("long lived " + longLived.check());
	}
}
