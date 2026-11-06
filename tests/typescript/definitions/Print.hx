import helder.gfx.ShaderCode;

// A shader as the definitions' tests print it, the same lines as print.ts.
class Print {
	public static function shader<V, P>(s:helder.gfx.shader.Shader<V, P>) {
		for (stage in [{name: "vertex", code: s.vertexCode}, {name: "fragment", code: s.fragmentCode}])
			for (l in ["glsl", "wgsl", "msl", "hlsl"]) {
				var text:Null<String> = switch l {
					case "glsl": stage.code.glsl;
					case "wgsl": stage.code.wgsl;
					case "msl": stage.code.msl;
					case _: stage.code.hlsl;
				}
				if (text != null) Sys.println('--- ${stage.name} $l\n$text');
			}
		for (l in s.layout)
			Sys.println('layout ${l.stride}: ' + [for (a in l.attributes) '${a.location} ${(cast a.format : Int)} ${a.offset}'].join(", "));
		for (u in s.uniforms)
			Sys.println('uniform ${u.name} ${u.binding} ${u.size}');
		for (t in s.textures)
			Sys.println('texture ${t.name} ${t.binding}');
	}
}
