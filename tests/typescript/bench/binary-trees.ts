// Allocation and recursion through methods: the benchmarks game's binary-trees.
class TreeNode {
	constructor(public left: TreeNode | null, public right: TreeNode | null) {}
	check(): number { return this.left === null || this.right === null ? 1 : 1 + this.left.check() + this.right.check(); }
}
function bottomUp(depth: number): TreeNode {
	return depth > 0 ? new TreeNode(bottomUp(depth - 1), bottomUp(depth - 1)) : new TreeNode(null, null);
}
const max = 16;
console.log("stretch", bottomUp(max + 1).check());
const longLived = bottomUp(max);
for (let depth = 4; depth <= max; depth += 2) {
	const iterations = 1 << (max - depth + 4);
	let check = 0;
	for (let i = 0; i < iterations; i++) check += bottomUp(depth).check();
	console.log(iterations, depth, check);
}
console.log("long lived", longLived.check());
