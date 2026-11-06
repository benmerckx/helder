// helder/gfx for TypeScript: written by src/helder/gfx/typescript.mjs (do not edit).
//
// The shader math as CPU code (helder.gfx.shader's types, the same names),
// and shader({vertex, fragment}), a definition: its stages compiled when the
// program is built, to GLSL, WGSL, MSL and HLSL, the same text as Haxe's
// shader({...}) of the same functions (src/helder/gfx/shader/Shader.hx):
//
//   type Vertex = {pos: Vec2, color: Vec3};
//   type Varyings = {pos: Vec4, color: Vec3};
//   export const Triangle = shader({
//     vertex: (v: Vertex): Varyings => ({pos: position(vec4(v.pos, 0, 1)), color: v.color}),
//     fragment: (i: Varyings) => vec4(i.color, 1),
//   });
//
// The operators are methods (a.mul(b), a.add(1); a number's side second:
// x.mul(2), as Haxe's 2 * x prints).
// Structs are type aliases of object types (their name the struct's).

type Scalar = number;

export class Vec2 {
	constructor(readonly x: number, readonly y: number) {}
	add(b: Vec2 | number): Vec2 {
		return typeof b === "number" ? new Vec2(this.x + b, this.y + b) : new Vec2(this.x + b.x, this.y + b.y);
	}
	sub(b: Vec2 | number): Vec2 {
		return typeof b === "number" ? new Vec2(this.x - b, this.y - b) : new Vec2(this.x - b.x, this.y - b.y);
	}
	mul(b: Vec2 | number): Vec2 {
		return typeof b === "number" ? new Vec2(this.x * b, this.y * b) : new Vec2(this.x * b.x, this.y * b.y);
	}
	div(b: Vec2 | number): Vec2 {
		return typeof b === "number" ? new Vec2(this.x / b, this.y / b) : new Vec2(this.x / b.x, this.y / b.y);
	}
	neg(): Vec2 {
		return new Vec2(-this.x, -this.y);
	}
	get xx(): Vec2 {
		return new Vec2(this.x, this.x);
	}
	get xy(): Vec2 {
		return new Vec2(this.x, this.y);
	}
	get yx(): Vec2 {
		return new Vec2(this.y, this.x);
	}
	get yy(): Vec2 {
		return new Vec2(this.y, this.y);
	}
	get xxx(): Vec3 {
		return new Vec3(this.x, this.x, this.x);
	}
	get xxy(): Vec3 {
		return new Vec3(this.x, this.x, this.y);
	}
	get xyx(): Vec3 {
		return new Vec3(this.x, this.y, this.x);
	}
	get xyy(): Vec3 {
		return new Vec3(this.x, this.y, this.y);
	}
	get yxx(): Vec3 {
		return new Vec3(this.y, this.x, this.x);
	}
	get yxy(): Vec3 {
		return new Vec3(this.y, this.x, this.y);
	}
	get yyx(): Vec3 {
		return new Vec3(this.y, this.y, this.x);
	}
	get yyy(): Vec3 {
		return new Vec3(this.y, this.y, this.y);
	}
	get xxxx(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.x);
	}
	get xxxy(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.y);
	}
	get xxyx(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.x);
	}
	get xxyy(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.y);
	}
	get xyxx(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.x);
	}
	get xyxy(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.y);
	}
	get xyyx(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.x);
	}
	get xyyy(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.y);
	}
	get yxxx(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.x);
	}
	get yxxy(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.y);
	}
	get yxyx(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.x);
	}
	get yxyy(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.y);
	}
	get yyxx(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.x);
	}
	get yyxy(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.y);
	}
	get yyyx(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.x);
	}
	get yyyy(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.y);
	}
}

export class Vec3 {
	constructor(readonly x: number, readonly y: number, readonly z: number) {}
	add(b: Vec3 | number): Vec3 {
		return typeof b === "number" ? new Vec3(this.x + b, this.y + b, this.z + b) : new Vec3(this.x + b.x, this.y + b.y, this.z + b.z);
	}
	sub(b: Vec3 | number): Vec3 {
		return typeof b === "number" ? new Vec3(this.x - b, this.y - b, this.z - b) : new Vec3(this.x - b.x, this.y - b.y, this.z - b.z);
	}
	mul(b: Vec3 | number): Vec3 {
		return typeof b === "number" ? new Vec3(this.x * b, this.y * b, this.z * b) : new Vec3(this.x * b.x, this.y * b.y, this.z * b.z);
	}
	div(b: Vec3 | number): Vec3 {
		return typeof b === "number" ? new Vec3(this.x / b, this.y / b, this.z / b) : new Vec3(this.x / b.x, this.y / b.y, this.z / b.z);
	}
	neg(): Vec3 {
		return new Vec3(-this.x, -this.y, -this.z);
	}
	get xx(): Vec2 {
		return new Vec2(this.x, this.x);
	}
	get xy(): Vec2 {
		return new Vec2(this.x, this.y);
	}
	get xz(): Vec2 {
		return new Vec2(this.x, this.z);
	}
	get yx(): Vec2 {
		return new Vec2(this.y, this.x);
	}
	get yy(): Vec2 {
		return new Vec2(this.y, this.y);
	}
	get yz(): Vec2 {
		return new Vec2(this.y, this.z);
	}
	get zx(): Vec2 {
		return new Vec2(this.z, this.x);
	}
	get zy(): Vec2 {
		return new Vec2(this.z, this.y);
	}
	get zz(): Vec2 {
		return new Vec2(this.z, this.z);
	}
	get xxx(): Vec3 {
		return new Vec3(this.x, this.x, this.x);
	}
	get xxy(): Vec3 {
		return new Vec3(this.x, this.x, this.y);
	}
	get xxz(): Vec3 {
		return new Vec3(this.x, this.x, this.z);
	}
	get xyx(): Vec3 {
		return new Vec3(this.x, this.y, this.x);
	}
	get xyy(): Vec3 {
		return new Vec3(this.x, this.y, this.y);
	}
	get xyz(): Vec3 {
		return new Vec3(this.x, this.y, this.z);
	}
	get xzx(): Vec3 {
		return new Vec3(this.x, this.z, this.x);
	}
	get xzy(): Vec3 {
		return new Vec3(this.x, this.z, this.y);
	}
	get xzz(): Vec3 {
		return new Vec3(this.x, this.z, this.z);
	}
	get yxx(): Vec3 {
		return new Vec3(this.y, this.x, this.x);
	}
	get yxy(): Vec3 {
		return new Vec3(this.y, this.x, this.y);
	}
	get yxz(): Vec3 {
		return new Vec3(this.y, this.x, this.z);
	}
	get yyx(): Vec3 {
		return new Vec3(this.y, this.y, this.x);
	}
	get yyy(): Vec3 {
		return new Vec3(this.y, this.y, this.y);
	}
	get yyz(): Vec3 {
		return new Vec3(this.y, this.y, this.z);
	}
	get yzx(): Vec3 {
		return new Vec3(this.y, this.z, this.x);
	}
	get yzy(): Vec3 {
		return new Vec3(this.y, this.z, this.y);
	}
	get yzz(): Vec3 {
		return new Vec3(this.y, this.z, this.z);
	}
	get zxx(): Vec3 {
		return new Vec3(this.z, this.x, this.x);
	}
	get zxy(): Vec3 {
		return new Vec3(this.z, this.x, this.y);
	}
	get zxz(): Vec3 {
		return new Vec3(this.z, this.x, this.z);
	}
	get zyx(): Vec3 {
		return new Vec3(this.z, this.y, this.x);
	}
	get zyy(): Vec3 {
		return new Vec3(this.z, this.y, this.y);
	}
	get zyz(): Vec3 {
		return new Vec3(this.z, this.y, this.z);
	}
	get zzx(): Vec3 {
		return new Vec3(this.z, this.z, this.x);
	}
	get zzy(): Vec3 {
		return new Vec3(this.z, this.z, this.y);
	}
	get zzz(): Vec3 {
		return new Vec3(this.z, this.z, this.z);
	}
	get xxxx(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.x);
	}
	get xxxy(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.y);
	}
	get xxxz(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.z);
	}
	get xxyx(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.x);
	}
	get xxyy(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.y);
	}
	get xxyz(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.z);
	}
	get xxzx(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.x);
	}
	get xxzy(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.y);
	}
	get xxzz(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.z);
	}
	get xyxx(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.x);
	}
	get xyxy(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.y);
	}
	get xyxz(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.z);
	}
	get xyyx(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.x);
	}
	get xyyy(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.y);
	}
	get xyyz(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.z);
	}
	get xyzx(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.x);
	}
	get xyzy(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.y);
	}
	get xyzz(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.z);
	}
	get xzxx(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.x);
	}
	get xzxy(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.y);
	}
	get xzxz(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.z);
	}
	get xzyx(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.x);
	}
	get xzyy(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.y);
	}
	get xzyz(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.z);
	}
	get xzzx(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.x);
	}
	get xzzy(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.y);
	}
	get xzzz(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.z);
	}
	get yxxx(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.x);
	}
	get yxxy(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.y);
	}
	get yxxz(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.z);
	}
	get yxyx(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.x);
	}
	get yxyy(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.y);
	}
	get yxyz(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.z);
	}
	get yxzx(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.x);
	}
	get yxzy(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.y);
	}
	get yxzz(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.z);
	}
	get yyxx(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.x);
	}
	get yyxy(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.y);
	}
	get yyxz(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.z);
	}
	get yyyx(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.x);
	}
	get yyyy(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.y);
	}
	get yyyz(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.z);
	}
	get yyzx(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.x);
	}
	get yyzy(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.y);
	}
	get yyzz(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.z);
	}
	get yzxx(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.x);
	}
	get yzxy(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.y);
	}
	get yzxz(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.z);
	}
	get yzyx(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.x);
	}
	get yzyy(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.y);
	}
	get yzyz(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.z);
	}
	get yzzx(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.x);
	}
	get yzzy(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.y);
	}
	get yzzz(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.z);
	}
	get zxxx(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.x);
	}
	get zxxy(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.y);
	}
	get zxxz(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.z);
	}
	get zxyx(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.x);
	}
	get zxyy(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.y);
	}
	get zxyz(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.z);
	}
	get zxzx(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.x);
	}
	get zxzy(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.y);
	}
	get zxzz(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.z);
	}
	get zyxx(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.x);
	}
	get zyxy(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.y);
	}
	get zyxz(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.z);
	}
	get zyyx(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.x);
	}
	get zyyy(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.y);
	}
	get zyyz(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.z);
	}
	get zyzx(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.x);
	}
	get zyzy(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.y);
	}
	get zyzz(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.z);
	}
	get zzxx(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.x);
	}
	get zzxy(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.y);
	}
	get zzxz(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.z);
	}
	get zzyx(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.x);
	}
	get zzyy(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.y);
	}
	get zzyz(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.z);
	}
	get zzzx(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.x);
	}
	get zzzy(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.y);
	}
	get zzzz(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.z);
	}
}

export class Vec4 {
	constructor(readonly x: number, readonly y: number, readonly z: number, readonly w: number) {}
	add(b: Vec4 | number): Vec4 {
		return typeof b === "number" ? new Vec4(this.x + b, this.y + b, this.z + b, this.w + b) : new Vec4(this.x + b.x, this.y + b.y, this.z + b.z, this.w + b.w);
	}
	sub(b: Vec4 | number): Vec4 {
		return typeof b === "number" ? new Vec4(this.x - b, this.y - b, this.z - b, this.w - b) : new Vec4(this.x - b.x, this.y - b.y, this.z - b.z, this.w - b.w);
	}
	mul(b: Vec4 | number): Vec4 {
		return typeof b === "number" ? new Vec4(this.x * b, this.y * b, this.z * b, this.w * b) : new Vec4(this.x * b.x, this.y * b.y, this.z * b.z, this.w * b.w);
	}
	div(b: Vec4 | number): Vec4 {
		return typeof b === "number" ? new Vec4(this.x / b, this.y / b, this.z / b, this.w / b) : new Vec4(this.x / b.x, this.y / b.y, this.z / b.z, this.w / b.w);
	}
	neg(): Vec4 {
		return new Vec4(-this.x, -this.y, -this.z, -this.w);
	}
	get xx(): Vec2 {
		return new Vec2(this.x, this.x);
	}
	get xy(): Vec2 {
		return new Vec2(this.x, this.y);
	}
	get xz(): Vec2 {
		return new Vec2(this.x, this.z);
	}
	get xw(): Vec2 {
		return new Vec2(this.x, this.w);
	}
	get yx(): Vec2 {
		return new Vec2(this.y, this.x);
	}
	get yy(): Vec2 {
		return new Vec2(this.y, this.y);
	}
	get yz(): Vec2 {
		return new Vec2(this.y, this.z);
	}
	get yw(): Vec2 {
		return new Vec2(this.y, this.w);
	}
	get zx(): Vec2 {
		return new Vec2(this.z, this.x);
	}
	get zy(): Vec2 {
		return new Vec2(this.z, this.y);
	}
	get zz(): Vec2 {
		return new Vec2(this.z, this.z);
	}
	get zw(): Vec2 {
		return new Vec2(this.z, this.w);
	}
	get wx(): Vec2 {
		return new Vec2(this.w, this.x);
	}
	get wy(): Vec2 {
		return new Vec2(this.w, this.y);
	}
	get wz(): Vec2 {
		return new Vec2(this.w, this.z);
	}
	get ww(): Vec2 {
		return new Vec2(this.w, this.w);
	}
	get xxx(): Vec3 {
		return new Vec3(this.x, this.x, this.x);
	}
	get xxy(): Vec3 {
		return new Vec3(this.x, this.x, this.y);
	}
	get xxz(): Vec3 {
		return new Vec3(this.x, this.x, this.z);
	}
	get xxw(): Vec3 {
		return new Vec3(this.x, this.x, this.w);
	}
	get xyx(): Vec3 {
		return new Vec3(this.x, this.y, this.x);
	}
	get xyy(): Vec3 {
		return new Vec3(this.x, this.y, this.y);
	}
	get xyz(): Vec3 {
		return new Vec3(this.x, this.y, this.z);
	}
	get xyw(): Vec3 {
		return new Vec3(this.x, this.y, this.w);
	}
	get xzx(): Vec3 {
		return new Vec3(this.x, this.z, this.x);
	}
	get xzy(): Vec3 {
		return new Vec3(this.x, this.z, this.y);
	}
	get xzz(): Vec3 {
		return new Vec3(this.x, this.z, this.z);
	}
	get xzw(): Vec3 {
		return new Vec3(this.x, this.z, this.w);
	}
	get xwx(): Vec3 {
		return new Vec3(this.x, this.w, this.x);
	}
	get xwy(): Vec3 {
		return new Vec3(this.x, this.w, this.y);
	}
	get xwz(): Vec3 {
		return new Vec3(this.x, this.w, this.z);
	}
	get xww(): Vec3 {
		return new Vec3(this.x, this.w, this.w);
	}
	get yxx(): Vec3 {
		return new Vec3(this.y, this.x, this.x);
	}
	get yxy(): Vec3 {
		return new Vec3(this.y, this.x, this.y);
	}
	get yxz(): Vec3 {
		return new Vec3(this.y, this.x, this.z);
	}
	get yxw(): Vec3 {
		return new Vec3(this.y, this.x, this.w);
	}
	get yyx(): Vec3 {
		return new Vec3(this.y, this.y, this.x);
	}
	get yyy(): Vec3 {
		return new Vec3(this.y, this.y, this.y);
	}
	get yyz(): Vec3 {
		return new Vec3(this.y, this.y, this.z);
	}
	get yyw(): Vec3 {
		return new Vec3(this.y, this.y, this.w);
	}
	get yzx(): Vec3 {
		return new Vec3(this.y, this.z, this.x);
	}
	get yzy(): Vec3 {
		return new Vec3(this.y, this.z, this.y);
	}
	get yzz(): Vec3 {
		return new Vec3(this.y, this.z, this.z);
	}
	get yzw(): Vec3 {
		return new Vec3(this.y, this.z, this.w);
	}
	get ywx(): Vec3 {
		return new Vec3(this.y, this.w, this.x);
	}
	get ywy(): Vec3 {
		return new Vec3(this.y, this.w, this.y);
	}
	get ywz(): Vec3 {
		return new Vec3(this.y, this.w, this.z);
	}
	get yww(): Vec3 {
		return new Vec3(this.y, this.w, this.w);
	}
	get zxx(): Vec3 {
		return new Vec3(this.z, this.x, this.x);
	}
	get zxy(): Vec3 {
		return new Vec3(this.z, this.x, this.y);
	}
	get zxz(): Vec3 {
		return new Vec3(this.z, this.x, this.z);
	}
	get zxw(): Vec3 {
		return new Vec3(this.z, this.x, this.w);
	}
	get zyx(): Vec3 {
		return new Vec3(this.z, this.y, this.x);
	}
	get zyy(): Vec3 {
		return new Vec3(this.z, this.y, this.y);
	}
	get zyz(): Vec3 {
		return new Vec3(this.z, this.y, this.z);
	}
	get zyw(): Vec3 {
		return new Vec3(this.z, this.y, this.w);
	}
	get zzx(): Vec3 {
		return new Vec3(this.z, this.z, this.x);
	}
	get zzy(): Vec3 {
		return new Vec3(this.z, this.z, this.y);
	}
	get zzz(): Vec3 {
		return new Vec3(this.z, this.z, this.z);
	}
	get zzw(): Vec3 {
		return new Vec3(this.z, this.z, this.w);
	}
	get zwx(): Vec3 {
		return new Vec3(this.z, this.w, this.x);
	}
	get zwy(): Vec3 {
		return new Vec3(this.z, this.w, this.y);
	}
	get zwz(): Vec3 {
		return new Vec3(this.z, this.w, this.z);
	}
	get zww(): Vec3 {
		return new Vec3(this.z, this.w, this.w);
	}
	get wxx(): Vec3 {
		return new Vec3(this.w, this.x, this.x);
	}
	get wxy(): Vec3 {
		return new Vec3(this.w, this.x, this.y);
	}
	get wxz(): Vec3 {
		return new Vec3(this.w, this.x, this.z);
	}
	get wxw(): Vec3 {
		return new Vec3(this.w, this.x, this.w);
	}
	get wyx(): Vec3 {
		return new Vec3(this.w, this.y, this.x);
	}
	get wyy(): Vec3 {
		return new Vec3(this.w, this.y, this.y);
	}
	get wyz(): Vec3 {
		return new Vec3(this.w, this.y, this.z);
	}
	get wyw(): Vec3 {
		return new Vec3(this.w, this.y, this.w);
	}
	get wzx(): Vec3 {
		return new Vec3(this.w, this.z, this.x);
	}
	get wzy(): Vec3 {
		return new Vec3(this.w, this.z, this.y);
	}
	get wzz(): Vec3 {
		return new Vec3(this.w, this.z, this.z);
	}
	get wzw(): Vec3 {
		return new Vec3(this.w, this.z, this.w);
	}
	get wwx(): Vec3 {
		return new Vec3(this.w, this.w, this.x);
	}
	get wwy(): Vec3 {
		return new Vec3(this.w, this.w, this.y);
	}
	get wwz(): Vec3 {
		return new Vec3(this.w, this.w, this.z);
	}
	get www(): Vec3 {
		return new Vec3(this.w, this.w, this.w);
	}
	get xxxx(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.x);
	}
	get xxxy(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.y);
	}
	get xxxz(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.z);
	}
	get xxxw(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.w);
	}
	get xxyx(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.x);
	}
	get xxyy(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.y);
	}
	get xxyz(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.z);
	}
	get xxyw(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.w);
	}
	get xxzx(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.x);
	}
	get xxzy(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.y);
	}
	get xxzz(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.z);
	}
	get xxzw(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.w);
	}
	get xxwx(): Vec4 {
		return new Vec4(this.x, this.x, this.w, this.x);
	}
	get xxwy(): Vec4 {
		return new Vec4(this.x, this.x, this.w, this.y);
	}
	get xxwz(): Vec4 {
		return new Vec4(this.x, this.x, this.w, this.z);
	}
	get xxww(): Vec4 {
		return new Vec4(this.x, this.x, this.w, this.w);
	}
	get xyxx(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.x);
	}
	get xyxy(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.y);
	}
	get xyxz(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.z);
	}
	get xyxw(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.w);
	}
	get xyyx(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.x);
	}
	get xyyy(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.y);
	}
	get xyyz(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.z);
	}
	get xyyw(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.w);
	}
	get xyzx(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.x);
	}
	get xyzy(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.y);
	}
	get xyzz(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.z);
	}
	get xyzw(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.w);
	}
	get xywx(): Vec4 {
		return new Vec4(this.x, this.y, this.w, this.x);
	}
	get xywy(): Vec4 {
		return new Vec4(this.x, this.y, this.w, this.y);
	}
	get xywz(): Vec4 {
		return new Vec4(this.x, this.y, this.w, this.z);
	}
	get xyww(): Vec4 {
		return new Vec4(this.x, this.y, this.w, this.w);
	}
	get xzxx(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.x);
	}
	get xzxy(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.y);
	}
	get xzxz(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.z);
	}
	get xzxw(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.w);
	}
	get xzyx(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.x);
	}
	get xzyy(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.y);
	}
	get xzyz(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.z);
	}
	get xzyw(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.w);
	}
	get xzzx(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.x);
	}
	get xzzy(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.y);
	}
	get xzzz(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.z);
	}
	get xzzw(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.w);
	}
	get xzwx(): Vec4 {
		return new Vec4(this.x, this.z, this.w, this.x);
	}
	get xzwy(): Vec4 {
		return new Vec4(this.x, this.z, this.w, this.y);
	}
	get xzwz(): Vec4 {
		return new Vec4(this.x, this.z, this.w, this.z);
	}
	get xzww(): Vec4 {
		return new Vec4(this.x, this.z, this.w, this.w);
	}
	get xwxx(): Vec4 {
		return new Vec4(this.x, this.w, this.x, this.x);
	}
	get xwxy(): Vec4 {
		return new Vec4(this.x, this.w, this.x, this.y);
	}
	get xwxz(): Vec4 {
		return new Vec4(this.x, this.w, this.x, this.z);
	}
	get xwxw(): Vec4 {
		return new Vec4(this.x, this.w, this.x, this.w);
	}
	get xwyx(): Vec4 {
		return new Vec4(this.x, this.w, this.y, this.x);
	}
	get xwyy(): Vec4 {
		return new Vec4(this.x, this.w, this.y, this.y);
	}
	get xwyz(): Vec4 {
		return new Vec4(this.x, this.w, this.y, this.z);
	}
	get xwyw(): Vec4 {
		return new Vec4(this.x, this.w, this.y, this.w);
	}
	get xwzx(): Vec4 {
		return new Vec4(this.x, this.w, this.z, this.x);
	}
	get xwzy(): Vec4 {
		return new Vec4(this.x, this.w, this.z, this.y);
	}
	get xwzz(): Vec4 {
		return new Vec4(this.x, this.w, this.z, this.z);
	}
	get xwzw(): Vec4 {
		return new Vec4(this.x, this.w, this.z, this.w);
	}
	get xwwx(): Vec4 {
		return new Vec4(this.x, this.w, this.w, this.x);
	}
	get xwwy(): Vec4 {
		return new Vec4(this.x, this.w, this.w, this.y);
	}
	get xwwz(): Vec4 {
		return new Vec4(this.x, this.w, this.w, this.z);
	}
	get xwww(): Vec4 {
		return new Vec4(this.x, this.w, this.w, this.w);
	}
	get yxxx(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.x);
	}
	get yxxy(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.y);
	}
	get yxxz(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.z);
	}
	get yxxw(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.w);
	}
	get yxyx(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.x);
	}
	get yxyy(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.y);
	}
	get yxyz(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.z);
	}
	get yxyw(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.w);
	}
	get yxzx(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.x);
	}
	get yxzy(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.y);
	}
	get yxzz(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.z);
	}
	get yxzw(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.w);
	}
	get yxwx(): Vec4 {
		return new Vec4(this.y, this.x, this.w, this.x);
	}
	get yxwy(): Vec4 {
		return new Vec4(this.y, this.x, this.w, this.y);
	}
	get yxwz(): Vec4 {
		return new Vec4(this.y, this.x, this.w, this.z);
	}
	get yxww(): Vec4 {
		return new Vec4(this.y, this.x, this.w, this.w);
	}
	get yyxx(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.x);
	}
	get yyxy(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.y);
	}
	get yyxz(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.z);
	}
	get yyxw(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.w);
	}
	get yyyx(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.x);
	}
	get yyyy(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.y);
	}
	get yyyz(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.z);
	}
	get yyyw(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.w);
	}
	get yyzx(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.x);
	}
	get yyzy(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.y);
	}
	get yyzz(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.z);
	}
	get yyzw(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.w);
	}
	get yywx(): Vec4 {
		return new Vec4(this.y, this.y, this.w, this.x);
	}
	get yywy(): Vec4 {
		return new Vec4(this.y, this.y, this.w, this.y);
	}
	get yywz(): Vec4 {
		return new Vec4(this.y, this.y, this.w, this.z);
	}
	get yyww(): Vec4 {
		return new Vec4(this.y, this.y, this.w, this.w);
	}
	get yzxx(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.x);
	}
	get yzxy(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.y);
	}
	get yzxz(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.z);
	}
	get yzxw(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.w);
	}
	get yzyx(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.x);
	}
	get yzyy(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.y);
	}
	get yzyz(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.z);
	}
	get yzyw(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.w);
	}
	get yzzx(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.x);
	}
	get yzzy(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.y);
	}
	get yzzz(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.z);
	}
	get yzzw(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.w);
	}
	get yzwx(): Vec4 {
		return new Vec4(this.y, this.z, this.w, this.x);
	}
	get yzwy(): Vec4 {
		return new Vec4(this.y, this.z, this.w, this.y);
	}
	get yzwz(): Vec4 {
		return new Vec4(this.y, this.z, this.w, this.z);
	}
	get yzww(): Vec4 {
		return new Vec4(this.y, this.z, this.w, this.w);
	}
	get ywxx(): Vec4 {
		return new Vec4(this.y, this.w, this.x, this.x);
	}
	get ywxy(): Vec4 {
		return new Vec4(this.y, this.w, this.x, this.y);
	}
	get ywxz(): Vec4 {
		return new Vec4(this.y, this.w, this.x, this.z);
	}
	get ywxw(): Vec4 {
		return new Vec4(this.y, this.w, this.x, this.w);
	}
	get ywyx(): Vec4 {
		return new Vec4(this.y, this.w, this.y, this.x);
	}
	get ywyy(): Vec4 {
		return new Vec4(this.y, this.w, this.y, this.y);
	}
	get ywyz(): Vec4 {
		return new Vec4(this.y, this.w, this.y, this.z);
	}
	get ywyw(): Vec4 {
		return new Vec4(this.y, this.w, this.y, this.w);
	}
	get ywzx(): Vec4 {
		return new Vec4(this.y, this.w, this.z, this.x);
	}
	get ywzy(): Vec4 {
		return new Vec4(this.y, this.w, this.z, this.y);
	}
	get ywzz(): Vec4 {
		return new Vec4(this.y, this.w, this.z, this.z);
	}
	get ywzw(): Vec4 {
		return new Vec4(this.y, this.w, this.z, this.w);
	}
	get ywwx(): Vec4 {
		return new Vec4(this.y, this.w, this.w, this.x);
	}
	get ywwy(): Vec4 {
		return new Vec4(this.y, this.w, this.w, this.y);
	}
	get ywwz(): Vec4 {
		return new Vec4(this.y, this.w, this.w, this.z);
	}
	get ywww(): Vec4 {
		return new Vec4(this.y, this.w, this.w, this.w);
	}
	get zxxx(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.x);
	}
	get zxxy(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.y);
	}
	get zxxz(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.z);
	}
	get zxxw(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.w);
	}
	get zxyx(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.x);
	}
	get zxyy(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.y);
	}
	get zxyz(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.z);
	}
	get zxyw(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.w);
	}
	get zxzx(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.x);
	}
	get zxzy(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.y);
	}
	get zxzz(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.z);
	}
	get zxzw(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.w);
	}
	get zxwx(): Vec4 {
		return new Vec4(this.z, this.x, this.w, this.x);
	}
	get zxwy(): Vec4 {
		return new Vec4(this.z, this.x, this.w, this.y);
	}
	get zxwz(): Vec4 {
		return new Vec4(this.z, this.x, this.w, this.z);
	}
	get zxww(): Vec4 {
		return new Vec4(this.z, this.x, this.w, this.w);
	}
	get zyxx(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.x);
	}
	get zyxy(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.y);
	}
	get zyxz(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.z);
	}
	get zyxw(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.w);
	}
	get zyyx(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.x);
	}
	get zyyy(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.y);
	}
	get zyyz(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.z);
	}
	get zyyw(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.w);
	}
	get zyzx(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.x);
	}
	get zyzy(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.y);
	}
	get zyzz(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.z);
	}
	get zyzw(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.w);
	}
	get zywx(): Vec4 {
		return new Vec4(this.z, this.y, this.w, this.x);
	}
	get zywy(): Vec4 {
		return new Vec4(this.z, this.y, this.w, this.y);
	}
	get zywz(): Vec4 {
		return new Vec4(this.z, this.y, this.w, this.z);
	}
	get zyww(): Vec4 {
		return new Vec4(this.z, this.y, this.w, this.w);
	}
	get zzxx(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.x);
	}
	get zzxy(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.y);
	}
	get zzxz(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.z);
	}
	get zzxw(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.w);
	}
	get zzyx(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.x);
	}
	get zzyy(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.y);
	}
	get zzyz(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.z);
	}
	get zzyw(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.w);
	}
	get zzzx(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.x);
	}
	get zzzy(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.y);
	}
	get zzzz(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.z);
	}
	get zzzw(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.w);
	}
	get zzwx(): Vec4 {
		return new Vec4(this.z, this.z, this.w, this.x);
	}
	get zzwy(): Vec4 {
		return new Vec4(this.z, this.z, this.w, this.y);
	}
	get zzwz(): Vec4 {
		return new Vec4(this.z, this.z, this.w, this.z);
	}
	get zzww(): Vec4 {
		return new Vec4(this.z, this.z, this.w, this.w);
	}
	get zwxx(): Vec4 {
		return new Vec4(this.z, this.w, this.x, this.x);
	}
	get zwxy(): Vec4 {
		return new Vec4(this.z, this.w, this.x, this.y);
	}
	get zwxz(): Vec4 {
		return new Vec4(this.z, this.w, this.x, this.z);
	}
	get zwxw(): Vec4 {
		return new Vec4(this.z, this.w, this.x, this.w);
	}
	get zwyx(): Vec4 {
		return new Vec4(this.z, this.w, this.y, this.x);
	}
	get zwyy(): Vec4 {
		return new Vec4(this.z, this.w, this.y, this.y);
	}
	get zwyz(): Vec4 {
		return new Vec4(this.z, this.w, this.y, this.z);
	}
	get zwyw(): Vec4 {
		return new Vec4(this.z, this.w, this.y, this.w);
	}
	get zwzx(): Vec4 {
		return new Vec4(this.z, this.w, this.z, this.x);
	}
	get zwzy(): Vec4 {
		return new Vec4(this.z, this.w, this.z, this.y);
	}
	get zwzz(): Vec4 {
		return new Vec4(this.z, this.w, this.z, this.z);
	}
	get zwzw(): Vec4 {
		return new Vec4(this.z, this.w, this.z, this.w);
	}
	get zwwx(): Vec4 {
		return new Vec4(this.z, this.w, this.w, this.x);
	}
	get zwwy(): Vec4 {
		return new Vec4(this.z, this.w, this.w, this.y);
	}
	get zwwz(): Vec4 {
		return new Vec4(this.z, this.w, this.w, this.z);
	}
	get zwww(): Vec4 {
		return new Vec4(this.z, this.w, this.w, this.w);
	}
	get wxxx(): Vec4 {
		return new Vec4(this.w, this.x, this.x, this.x);
	}
	get wxxy(): Vec4 {
		return new Vec4(this.w, this.x, this.x, this.y);
	}
	get wxxz(): Vec4 {
		return new Vec4(this.w, this.x, this.x, this.z);
	}
	get wxxw(): Vec4 {
		return new Vec4(this.w, this.x, this.x, this.w);
	}
	get wxyx(): Vec4 {
		return new Vec4(this.w, this.x, this.y, this.x);
	}
	get wxyy(): Vec4 {
		return new Vec4(this.w, this.x, this.y, this.y);
	}
	get wxyz(): Vec4 {
		return new Vec4(this.w, this.x, this.y, this.z);
	}
	get wxyw(): Vec4 {
		return new Vec4(this.w, this.x, this.y, this.w);
	}
	get wxzx(): Vec4 {
		return new Vec4(this.w, this.x, this.z, this.x);
	}
	get wxzy(): Vec4 {
		return new Vec4(this.w, this.x, this.z, this.y);
	}
	get wxzz(): Vec4 {
		return new Vec4(this.w, this.x, this.z, this.z);
	}
	get wxzw(): Vec4 {
		return new Vec4(this.w, this.x, this.z, this.w);
	}
	get wxwx(): Vec4 {
		return new Vec4(this.w, this.x, this.w, this.x);
	}
	get wxwy(): Vec4 {
		return new Vec4(this.w, this.x, this.w, this.y);
	}
	get wxwz(): Vec4 {
		return new Vec4(this.w, this.x, this.w, this.z);
	}
	get wxww(): Vec4 {
		return new Vec4(this.w, this.x, this.w, this.w);
	}
	get wyxx(): Vec4 {
		return new Vec4(this.w, this.y, this.x, this.x);
	}
	get wyxy(): Vec4 {
		return new Vec4(this.w, this.y, this.x, this.y);
	}
	get wyxz(): Vec4 {
		return new Vec4(this.w, this.y, this.x, this.z);
	}
	get wyxw(): Vec4 {
		return new Vec4(this.w, this.y, this.x, this.w);
	}
	get wyyx(): Vec4 {
		return new Vec4(this.w, this.y, this.y, this.x);
	}
	get wyyy(): Vec4 {
		return new Vec4(this.w, this.y, this.y, this.y);
	}
	get wyyz(): Vec4 {
		return new Vec4(this.w, this.y, this.y, this.z);
	}
	get wyyw(): Vec4 {
		return new Vec4(this.w, this.y, this.y, this.w);
	}
	get wyzx(): Vec4 {
		return new Vec4(this.w, this.y, this.z, this.x);
	}
	get wyzy(): Vec4 {
		return new Vec4(this.w, this.y, this.z, this.y);
	}
	get wyzz(): Vec4 {
		return new Vec4(this.w, this.y, this.z, this.z);
	}
	get wyzw(): Vec4 {
		return new Vec4(this.w, this.y, this.z, this.w);
	}
	get wywx(): Vec4 {
		return new Vec4(this.w, this.y, this.w, this.x);
	}
	get wywy(): Vec4 {
		return new Vec4(this.w, this.y, this.w, this.y);
	}
	get wywz(): Vec4 {
		return new Vec4(this.w, this.y, this.w, this.z);
	}
	get wyww(): Vec4 {
		return new Vec4(this.w, this.y, this.w, this.w);
	}
	get wzxx(): Vec4 {
		return new Vec4(this.w, this.z, this.x, this.x);
	}
	get wzxy(): Vec4 {
		return new Vec4(this.w, this.z, this.x, this.y);
	}
	get wzxz(): Vec4 {
		return new Vec4(this.w, this.z, this.x, this.z);
	}
	get wzxw(): Vec4 {
		return new Vec4(this.w, this.z, this.x, this.w);
	}
	get wzyx(): Vec4 {
		return new Vec4(this.w, this.z, this.y, this.x);
	}
	get wzyy(): Vec4 {
		return new Vec4(this.w, this.z, this.y, this.y);
	}
	get wzyz(): Vec4 {
		return new Vec4(this.w, this.z, this.y, this.z);
	}
	get wzyw(): Vec4 {
		return new Vec4(this.w, this.z, this.y, this.w);
	}
	get wzzx(): Vec4 {
		return new Vec4(this.w, this.z, this.z, this.x);
	}
	get wzzy(): Vec4 {
		return new Vec4(this.w, this.z, this.z, this.y);
	}
	get wzzz(): Vec4 {
		return new Vec4(this.w, this.z, this.z, this.z);
	}
	get wzzw(): Vec4 {
		return new Vec4(this.w, this.z, this.z, this.w);
	}
	get wzwx(): Vec4 {
		return new Vec4(this.w, this.z, this.w, this.x);
	}
	get wzwy(): Vec4 {
		return new Vec4(this.w, this.z, this.w, this.y);
	}
	get wzwz(): Vec4 {
		return new Vec4(this.w, this.z, this.w, this.z);
	}
	get wzww(): Vec4 {
		return new Vec4(this.w, this.z, this.w, this.w);
	}
	get wwxx(): Vec4 {
		return new Vec4(this.w, this.w, this.x, this.x);
	}
	get wwxy(): Vec4 {
		return new Vec4(this.w, this.w, this.x, this.y);
	}
	get wwxz(): Vec4 {
		return new Vec4(this.w, this.w, this.x, this.z);
	}
	get wwxw(): Vec4 {
		return new Vec4(this.w, this.w, this.x, this.w);
	}
	get wwyx(): Vec4 {
		return new Vec4(this.w, this.w, this.y, this.x);
	}
	get wwyy(): Vec4 {
		return new Vec4(this.w, this.w, this.y, this.y);
	}
	get wwyz(): Vec4 {
		return new Vec4(this.w, this.w, this.y, this.z);
	}
	get wwyw(): Vec4 {
		return new Vec4(this.w, this.w, this.y, this.w);
	}
	get wwzx(): Vec4 {
		return new Vec4(this.w, this.w, this.z, this.x);
	}
	get wwzy(): Vec4 {
		return new Vec4(this.w, this.w, this.z, this.y);
	}
	get wwzz(): Vec4 {
		return new Vec4(this.w, this.w, this.z, this.z);
	}
	get wwzw(): Vec4 {
		return new Vec4(this.w, this.w, this.z, this.w);
	}
	get wwwx(): Vec4 {
		return new Vec4(this.w, this.w, this.w, this.x);
	}
	get wwwy(): Vec4 {
		return new Vec4(this.w, this.w, this.w, this.y);
	}
	get wwwz(): Vec4 {
		return new Vec4(this.w, this.w, this.w, this.z);
	}
	get wwww(): Vec4 {
		return new Vec4(this.w, this.w, this.w, this.w);
	}
}

export class Mat4 {
	constructor(readonly c0: Vec4, readonly c1: Vec4, readonly c2: Vec4, readonly c3: Vec4) {}
	mul(b: Mat4): Mat4;
	mul(b: Vec4): Vec4;
	mul(b: Mat4 | Vec4): Mat4 | Vec4 {
		if (b instanceof Vec4) return this.c0.mul(b.x).add(this.c1.mul(b.y)).add(this.c2.mul(b.z)).add(this.c3.mul(b.w));
		return new Mat4(this.mul(b.c0), this.mul(b.c1), this.mul(b.c2), this.mul(b.c3));
	}
}

// a texture and its sampler, a shader's parameter (sample(t, uv)); on the
// CPU, RGBA8 texels, rows top to bottom, read at the nearest, repeating
export class Texture2D {
	constructor(readonly width: number, readonly height: number, readonly texels: Uint8Array) {}
	read(uv: Vec2): Vec4 {
		const x = Math.floor((uv.x - Math.floor(uv.x)) * this.width), y = Math.floor((uv.y - Math.floor(uv.y)) * this.height);
		const p = 4 * (y * this.width + x);
		return new Vec4(this.texels[p] / 255, this.texels[p + 1] / 255, this.texels[p + 2] / 255, this.texels[p + 3] / 255);
	}
}

type Vec = Vec2 | Vec3 | Vec4;
type Flat = number | Vec;

// (a function of numbers, componentwise over vectors; numbers broadcast)
function each(f: (...xs: number[]) => number, xs: Flat[]): any {
	let shape: Vec | undefined;
	for (const x of xs) if (typeof x !== "number") shape = x;
	if (shape === undefined) return f(...(xs as number[]));
	const at = (x: Flat, k: "x" | "y" | "z" | "w") => typeof x === "number" ? x : (x as any)[k] as number;
	if (shape instanceof Vec2) return new Vec2(f(...xs.map((x) => at(x, "x"))), f(...xs.map((x) => at(x, "y"))));
	if (shape instanceof Vec3) return new Vec3(f(...xs.map((x) => at(x, "x"))), f(...xs.map((x) => at(x, "y"))), f(...xs.map((x) => at(x, "z"))));
	return new Vec4(f(...xs.map((x) => at(x, "x"))), f(...xs.map((x) => at(x, "y"))), f(...xs.map((x) => at(x, "z"))), f(...xs.map((x) => at(x, "w"))));
}

export function abs<T extends Flat>(x: T): T {
	return each((x) => Math.abs(x), [x]);
}
export function sign<T extends Flat>(x: T): T {
	return each((x) => x > 0 ? 1 : x < 0 ? -1 : 0, [x]);
}
export function floor<T extends Flat>(x: T): T {
	return each((x) => Math.floor(x), [x]);
}
export function ceil<T extends Flat>(x: T): T {
	return each((x) => Math.ceil(x), [x]);
}
export function fract<T extends Flat>(x: T): T {
	return each((x) => x - Math.floor(x), [x]);
}
export function sqrt<T extends Flat>(x: T): T {
	return each((x) => Math.sqrt(x), [x]);
}
export function inversesqrt<T extends Flat>(x: T): T {
	return each((x) => 1 / Math.sqrt(x), [x]);
}
export function sin<T extends Flat>(x: T): T {
	return each((x) => Math.sin(x), [x]);
}
export function cos<T extends Flat>(x: T): T {
	return each((x) => Math.cos(x), [x]);
}
export function tan<T extends Flat>(x: T): T {
	return each((x) => Math.tan(x), [x]);
}
export function exp<T extends Flat>(x: T): T {
	return each((x) => Math.exp(x), [x]);
}
export function log<T extends Flat>(x: T): T {
	return each((x) => Math.log(x), [x]);
}
export function min<T extends Flat>(x: T, y: T | number): T {
	return each((x, y) => Math.min(x, y), [x, y]);
}
export function max<T extends Flat>(x: T, y: T | number): T {
	return each((x, y) => Math.max(x, y), [x, y]);
}
export function pow<T extends Flat>(x: T, y: T | number): T {
	return each((x, y) => Math.pow(x, y), [x, y]);
}
export function step<T extends Flat>(edge: T | number, x: T): T {
	return each((edge, x) => x < edge ? 0 : 1, [edge, x]);
}
export function mix<T extends Flat>(x: T, y: T, a: T | number): T {
	return each((x, y, a) => x + (y - x) * a, [x, y, a]);
}
export function clamp<T extends Flat>(x: T, lo: T | number, hi: T | number): T {
	return each((x, lo, hi) => Math.min(Math.max(x, lo), hi), [x, lo, hi]);
}
export function smoothstep<T extends Flat>(e0: T | number, e1: T | number, x: T): T {
	return each((e0, e1, x) => {
		const t = Math.min(Math.max((x - e0) / (e1 - e0), 0), 1);
		return t * t * (3 - 2 * t);
	}, [e0, e1, x]);
}
export function dot<T extends Vec>(a: T, b: T): number {
	const p = each((a, b) => a * b, [a, b]);
	return p.x + p.y + (p.z ?? 0) + (p.w ?? 0);
}
export function length(a: Vec): number {
	return Math.sqrt(dot(a, a));
}
export function distance<T extends Vec>(a: T, b: T): number {
	return length(each((a, b) => a - b, [a, b]));
}
export function normalize<T extends Vec>(a: T): T {
	const l = length(a);
	return each((a) => a / l, [a]);
}
export function reflect<T extends Vec>(i: T, n: T): T {
	const d = 2 * dot(n, i);
	return each((i, n) => i - n * d, [i, n]);
}
export function cross(a: Vec3, b: Vec3): Vec3 {
	return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
// a texture's colour at uv (the fragment stage: at the mip level its footprint needs)
export function sample(t: Texture2D, uv: Vec2): Vec4 {
	return t.read(uv);
}
// at a mip level (the CPU's textures have one)
export function sampleLevel(t: Texture2D, uv: Vec2, level: number): Vec4 {
	return t.read(uv);
}
// (the fragment dropped: alpha testing; nothing on the CPU)
export function discard(): void {}
// the clip-space position among a vertex stage's varyings, where it builds them
export function position(v: Vec4): Vec4 {
	return v;
}

export function vec2(x: number, y?: number): Vec2 {
	return new Vec2(x, y ?? x);
}
export function vec3(s: number): Vec3;
export function vec3(x: number, y: number, z: number): Vec3;
export function vec3(xy: Vec2, z: number): Vec3;
export function vec3(x: number, yz: Vec2): Vec3;
export function vec3(...a: Flat[]): Vec3 {
	const c = flatten(a);
	return c.length === 1 ? new Vec3(c[0], c[0], c[0]) : new Vec3(c[0], c[1], c[2]);
}
export function vec4(s: number): Vec4;
export function vec4(x: number, y: number, z: number, w: number): Vec4;
export function vec4(xyz: Vec3, w: number): Vec4;
export function vec4(x: number, yzw: Vec3): Vec4;
export function vec4(xy: Vec2, z: number, w: number): Vec4;
export function vec4(xy: Vec2, zw: Vec2): Vec4;
export function vec4(...a: Flat[]): Vec4 {
	const c = flatten(a);
	return c.length === 1 ? new Vec4(c[0], c[0], c[0], c[0]) : new Vec4(c[0], c[1], c[2], c[3]);
}
function flatten(a: Flat[]): number[] {
	const c: number[] = [];
	for (const x of a)
		if (typeof x === "number") c.push(x);
		else if (x instanceof Vec2) c.push(x.x, x.y);
		else if (x instanceof Vec3) c.push(x.x, x.y, x.z);
		else c.push(x.x, x.y, x.z, x.w);
	return c;
}
export function mat4(s: number): Mat4;
export function mat4(c0: Vec4, c1: Vec4, c2: Vec4, c3: Vec4): Mat4;
export function mat4(a: number | Vec4, c1?: Vec4, c2?: Vec4, c3?: Vec4): Mat4 {
	if (typeof a === "number") return new Mat4(new Vec4(a, 0, 0, 0), new Vec4(0, a, 0, 0), new Vec4(0, 0, a, 0), new Vec4(0, 0, 0, a));
	return new Mat4(a, c1!, c2!, c3!);
}

// --- shaders

// a stage's text in the build's languages (only the target's), and what it binds
export type ShaderCode = {glsl?: string, wgsl?: string, msl?: string, hlsl?: string, bindings: {name: string, slot: number, kind: number, size?: number}[]};
export type VertexBufferLayout = {stride: number, attributes: {location: number, format: number, offset: number}[]};
export type UniformBlock = {name: string, binding: number, size: number};
export type TextureBinding = {name: string, binding: number};
export type PipelineOptions = {topology?: number, cull?: number, blend?: number, depthCompare?: number, depthWrite?: boolean};

// a uniform block's writer: its struct's value at offset, std140
export class UniformWriter<T> {
	constructor(readonly block: UniformBlock, private readonly fields: {field: string, kind: string, offset: number}[]) {}
	write(value: T, bytes: Uint8Array, offset = 0): void {
		const d = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
		for (const f of this.fields) {
			const v = (value as any)[f.field];
			if (f.kind === "i") d.setInt32(offset + f.offset, v, true);
			else if (f.kind === "m") {
				const m = v as Mat4, cs = [m.c0, m.c1, m.c2, m.c3];
				for (let c = 0; c < 4; c++) for (let k = 0; k < 4; k++) d.setFloat32(offset + f.offset + 16 * c + 4 * k, (cs[c] as any)[XYZW[k]], true);
			} else store(d, offset + f.offset, v, f.kind);
		}
	}
}
const XYZW = ["x", "y", "z", "w"];
function store(d: DataView, at: number, v: any, kind: string) {
	if (kind === "f") d.setFloat32(at, v, true);
	else for (let k = 0; k < Number(kind); k++) d.setFloat32(at + 4 * k, v[XYZW[k]], true);
}

export type Shader<V, VS, FS> = {
	readonly vertexCode: ShaderCode,
	readonly fragmentCode: ShaderCode,
	readonly layout: VertexBufferLayout[],
	readonly uniforms: UniformBlock[],
	readonly textures: TextureBinding[],
	// a writer per uniform block, named after the parameter that takes it
	readonly params: {readonly [parameter: string]: UniformWriter<any>},
	readonly vertex: VS,
	readonly fragment: FS,
	pipeline(options?: PipelineOptions): {program: {vertex: ShaderCode, fragment: ShaderCode}, layout: VertexBufferLayout[]} & PipelineOptions,
	vertexBytes(vertices: V[]): Uint8Array,
};

/** @definition shader */
export function shader<V, I, VR extends any[], FR extends any[]>(def: {vertex: (v: V, ...resources: VR) => I, fragment: (i: I, ...resources: FR) => Vec4},
		generated?: string): Shader<V, (v: V, ...resources: VR) => I, (i: I, ...resources: FR) => Vec4> {
	if (generated === undefined) throw new Error("shader: a definition, compiled by helder's compiler (its argument static)");
	const g = JSON.parse(generated);
	const params: {[parameter: string]: UniformWriter<any>} = {};
	for (const b of g.blocks) params[b.param] = new UniformWriter<any>(b.block, b.fields);
	return {
		vertexCode: g.vertexCode,
		fragmentCode: g.fragmentCode,
		layout: g.layout,
		uniforms: g.uniforms,
		textures: g.textures,
		params,
		vertex: def.vertex,
		fragment: def.fragment,
		pipeline(options?: PipelineOptions) {
			return {program: {vertex: g.vertexCode, fragment: g.fragmentCode}, layout: g.layout, ...(options ?? {})};
		},
		vertexBytes(vertices: V[]): Uint8Array {
			const bytes = new Uint8Array(g.stride * vertices.length);
			const d = new DataView(bytes.buffer);
			for (let i = 0; i < vertices.length; i++)
				for (const a of g.attributes) store(d, i * g.stride + a.offset, (vertices[i] as any)[a.field], a.components === 1 ? "f" : String(a.components));
			return bytes;
		},
	};
}
