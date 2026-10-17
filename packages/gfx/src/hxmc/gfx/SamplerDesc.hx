package hxmc.gfx;

typedef SamplerDesc = {
	// magnification and minification (default Linear)
	?filter:Filter,
	// between mip levels (default none: the first level only); Linear with
	// filter Linear is trilinear filtering
	?mipFilter:Filter,
	// both directions (default Repeat)
	?wrap:Wrap
}
