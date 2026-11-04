# An HDR panorama's light, prefiltered once here for helder.scene's
# Environment.prefiltered: a Radiance .hdr (equirectangular: longitude
# across, -z at its centre, up at its top, EnvironmentShader.equirect's)
# filtered for image-based lighting into one atlas of rows, each the whole
# sphere at ROW_W x ROW_W/2:
#
# - rows 0 to LEVELS - 1: the specular light along a reflection for a
#   roughness of row / (LEVELS - 1), the panorama convolved with GGX's
#   distribution (the split sum's first half under Karis' n = v = r: each
#   source texel weighted by D(n.h) n.l and its solid angle);
# - the last row: the diffuse light about a normal (the irradiance over pi,
#   cosine weighted).
#
# Filtered in linear light, then divided by a scale (printed: the
# Environment's intensity to set) so the bright end fits 8 bits, and
# written as an sRGB PNG. Example: examples/gltf-showcase/environments.
#
#   python3 examples/gltf-showcase/envbake.py <in.hdr> <out.png>
#
# (needs numpy and Pillow; seconds)
import sys

import numpy as np
from PIL import Image

ROW_W = 256
LEVELS = 6


def read_hdr(path):
    # (Radiance RGBE, new-style run-length rows)
    data = open(path, 'rb').read()
    end = data.index(b'\n\n') + 2
    line_end = data.index(b'\n', end)
    dims = data[end:line_end].split()
    h, w = int(dims[1]), int(dims[3])
    pos = line_end + 1
    out = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        if data[pos] != 2 or data[pos + 1] != 2:
            raise SystemExit('envbake: only run-length encoded .hdr files')
        pos += 4
        for c in range(4):
            x = 0
            row = out[y, :, c]
            while x < w:
                n = data[pos]
                pos += 1
                if n > 128:
                    n -= 128
                    row[x:x + n] = data[pos]
                    pos += 1
                else:
                    row[x:x + n] = np.frombuffer(data, np.uint8, n, pos)
                    pos += n
                x += n
    e = out[..., 3].astype(np.int32)
    f = np.where(e > 0, np.ldexp(1.0, e - 136), 0).astype(np.float32)
    return out[..., :3].astype(np.float32) * f[..., None]


def directions(w, h):
    # (each texel's centre: its unit direction and solid angle)
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    phi = (u - 0.5) * 2 * np.pi  # atan2(x, -z)
    theta = v * np.pi  # acos(y)
    th, ph = np.meshgrid(theta, phi, indexing='ij')
    d = np.stack([np.sin(th) * np.sin(ph), np.cos(th), -np.sin(th) * np.cos(ph)], -1)
    area = (2 * np.pi / w) * (np.pi / h) * np.sin(th)
    return d.reshape(-1, 3).astype(np.float32), area.reshape(-1).astype(np.float32)


def resized(src, w):
    # (a box filter down to w x w/2: the panorama's light kept)
    h = w // 2
    sh, sw = src.shape[:2]
    ys = (np.arange(h + 1) * sh) // h
    xs = (np.arange(w + 1) * sw) // w
    c = np.cumsum(np.cumsum(np.pad(src, ((1, 0), (1, 0), (0, 0))), 0), 1)
    s = c[ys[1:]][:, xs[1:]] - c[ys[:-1]][:, xs[1:]] - c[ys[1:]][:, xs[:-1]] + c[ys[:-1]][:, xs[:-1]]
    n = (ys[1:] - ys[:-1])[:, None, None] * (xs[1:] - xs[:-1])[None, :, None]
    return (s / n).astype(np.float32)


def convolve(src, sw, out_dirs, weight):
    # (each output direction's weighted mean of the source's texels, in chunks)
    dirs, area = directions(sw, sw // 2)
    colors = src.reshape(-1, 3)
    result = np.zeros((len(out_dirs), 3), np.float32)
    for k in range(0, len(out_dirs), 512):
        n = out_dirs[k:k + 512]
        w = weight(n @ dirs.T) * area
        result[k:k + 512] = (w @ colors) / np.maximum(w.sum(1, keepdims=True), 1e-8)
    return result


def ggx(rough):
    a2 = max(rough * rough, 1e-4) ** 2

    def weight(nl):
        # (n = v = r: h halfway between n and l, n.h = sqrt((1 + n.l) / 2))
        nh2 = np.clip((1 + nl) / 2, 0, 1)
        d = a2 / (np.pi * (nh2 * (a2 - 1) + 1) ** 2)
        return d * np.clip(nl, 0, 1)

    return weight


def main(src_path, out_path):
    src = read_hdr(src_path)
    h = ROW_W // 2
    out_dirs, _ = directions(ROW_W, h)
    rows = [resized(src, ROW_W)]
    for level in range(1, LEVELS):
        rough = level / (LEVELS - 1)
        # (the source finer for the narrow lobes, coarser for the wide)
        sw = 256 if rough < 0.45 else 128
        rows.append(convolve(resized(src, sw), sw, out_dirs, ggx(rough)).reshape(h, ROW_W, 3))
    rows.append(convolve(resized(src, 64), 64, out_dirs, lambda nl: np.clip(nl, 0, 1)).reshape(h, ROW_W, 3))
    atlas = np.concatenate(rows, 0)
    # (the scale: the brightest half percent clips, the sun's and the lamps'
    # sharp reflections; the rest keeps 8 bits' steps)
    scale = max(1.0, float(np.percentile(atlas, 99.5)))
    img = np.clip((atlas / scale) ** (1 / 2.2) * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(img, 'RGB').save(out_path, optimize=True)
    print(f'{out_path}: {img.shape[1]} x {img.shape[0]}, {LEVELS} levels and the irradiance; intensity {scale:.3f}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
