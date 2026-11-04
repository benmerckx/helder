# Sponza

Crytek's Sponza atrium (glTF-Sample-Assets' glTF version) in helder.scene,
with GPU-compressed textures picked for the device: a sun with two shadow
cascades (`Shadows.cascaded`), a prefiltered sky (`Environment.prefiltered`),
HDR, bloom and ACES; a scripted fly-through (Catmull-Rom through six keys),
or a free camera (drag to look, WASD or the arrows, Q and E), and the
numbers over it (first frame, frame times' p50 and p99, draws, the GPU's
texture bytes).

```sh
node examples/sponza/fetch.mjs              # Sponza.glb and its three packed files, into models/ (git-ignored)
bun run helder examples/sponza/Sponza.hx    # natively; --target web for a page
```

## Compressed textures

`fetch.mjs` builds the asset step (`helder.scene.gltf.Pack`) natively and
packs the model three times: `Sponza.hxm3d` with the images as the file has
them, `Sponza.bc.hxm3d` (`--textures bc`: BC1, or BC3 where an image has
alpha) and `Sponza.astc.hxm3d` (`--textures astc`: ASTC 4x4). Each image is
decoded, its mip chain made (2x2 boxes) and every level compressed by
`helder.image.BlockCompress` (endpoints on the block's principal axis,
nearest indices; ASTC as one partition of 8-bit LDR endpoints, 3-bit weights
for RGB, 2-bit for RGBA). At run time the program fetches the file whose
format the GPU samples (`Device.supports(BC1)`, else `ASTC4x4`, else the
PNG/JPEG one); `PackedModel` uploads the levels as they are, or, on a GPU
without the format, decodes the first level on the CPU and mip-maps it.

helder.gfx has the formats on every back end: GL (`EXT_texture_compression_s3tc`,
`KHR_texture_compression_astc_ldr`), WebGL2 (`WEBGL_compressed_texture_s3tc`,
`_astc`), WebGPU (`texture-compression-bc`, `-astc`, asked for with the
device), Metal (BC; ASTC not yet asked for) and D3D11 (BC).

| Sponza's textures | the file | download | gzipped | on the GPU (its textures) | the frame's textures all told |
| --- | --- | ---: | ---: | ---: | ---: |
| PNG and JPEG, decoded to RGBA8 | Sponza.hxm3d | 53.8 MB | – | 363 MB | 472 MB |
| BC1/BC3 | Sponza.bc.hxm3d | 60.5 MB | 36.9 MB | 49.6 MB | 141 MB |
| ASTC 4x4 | Sponza.astc.hxm3d | 105.9 MB | 66.3 MB | 95.1 MB | 187 MB |

(Device.textureBytes natively on Mesa's llvmpipe, at 960 x 600; the last
column includes the HDR targets, the bloom chain, two 2048 shadow maps and
the sky's atlas, about 92 MB.) Packing takes 12 s for BC and 18 s for ASTC
natively. Loading: the PNG/JPEG file's 69 images are decoded when loaded
(3.3 s to the first frame natively), the compressed ones are uploaded as
they are (0.45 s).

Not yet: Basis Universal (KTX2) supercompression, transcoded at load, which
would make one smaller file for every GPU (the BC file is larger than the
JPEGs before gzip); ETC2; ASTC's larger blocks (6x6: 3.6 bits a texel) and
a better encoder's search; the alpha-masked leaves' shadows (cut out in the
frame, solid in the shadow map).

## Credits

Sponza: Crytek, under the CRYENGINE Limited License Agreement
(glTF-Sample-Assets' `LICENSES/LicenseRef-CRYENGINE-Agreement.txt`; fetched,
not redistributed in the repository). The sky: Poly Haven's
kloofendal_48d_partly_cloudy_puresky, CC0 (`environment.png`, baked by
`examples/gltf-showcase/envbake.py`).
