// BMBinaryTreesCode's computation with its result printed (@:result(26208))
@:access(BMBinaryTreesCode)
class CheckBinarytrees {
	static function main() {
		var minDepth = 8;
		var n = 14;
		var maxDepth = Std.int(Math.max(minDepth + 2, n));
		var stretchDepth = maxDepth + 1;
		var check = BMBinaryTreesCode.bottomUpTree(0, stretchDepth).itemCheck();
		var result = check;
		var longLivedTree = BMBinaryTreesCode.bottomUpTree(0, maxDepth);
		var depth = minDepth;
		while (depth <= maxDepth) {
			var iterations = 1 << (maxDepth - depth + minDepth);
			check = 0;
			for (i in 0...iterations) {
				check += BMBinaryTreesCode.bottomUpTree(i, depth).itemCheck();
				check += BMBinaryTreesCode.bottomUpTree(-i, depth).itemCheck();
			}
			result ^= check;
			Sys.println(iterations * 2 + " trees of depth " + depth + " check: " + check);
			depth += 2;
		}
		result ^= longLivedTree.itemCheck();
		Sys.println("result " + result);
	}
}
