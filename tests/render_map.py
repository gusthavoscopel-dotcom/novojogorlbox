"""Desenha o bairro visto de cima a partir do JSON exportado por tests/map.luau.

Uso:
    lune run tests/map.luau /tmp/mapa.json
    python3 tests/render_map.py /tmp/mapa.json docs/mapa.png
"""

import json
import sys

from PIL import Image, ImageDraw

SCALE = 3  # pixels por stud
HALF = 186  # metade do lado do mapa + margem


def to_px(x, z):
    return ((x + HALF) * SCALE, (z + HALF) * SCALE)


def hull(points):
    points = sorted(set(points))
    if len(points) <= 2:
        return points

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def footprint(part):
    sx, sy, sz = (v / 2 for v in part["size"])
    px, py, pz = part["pos"]
    r = part["rot"]
    corners = []
    for cx in (-sx, sx):
        for cy in (-sy, sy):
            for cz in (-sz, sz):
                wx = px + r[0] * cx + r[1] * cy + r[2] * cz
                wz = pz + r[6] * cx + r[7] * cy + r[8] * cz
                corners.append(to_px(round(wx, 3), round(wz, 3)))
    return hull(corners)


def main(source, target):
    data = json.load(open(source))
    size = HALF * 2 * SCALE
    image = Image.new("RGBA", (size, size), (40, 40, 48, 255))
    draw = ImageDraw.Draw(image, "RGBA")

    parts = [p for p in data["parts"] if p["pos"][1] < 50]  # ignora o lobby flutuante
    parts.sort(key=lambda p: p["pos"][1] + p["size"][1] / 2)
    for part in parts:
        r, g, b = (int(c * 255) for c in part["color"])
        alpha = int(255 * (1 - part["transparency"]))
        fill = (r, g, b, alpha)
        polygon = footprint(part)
        if part["shape"] in ("Ball", "Cylinder"):
            xs = [p[0] for p in polygon]
            ys = [p[1] for p in polygon]
            draw.ellipse([min(xs), min(ys), max(xs), max(ys)], fill=fill)
        else:
            draw.polygon(polygon, fill=fill)

    for poi in data["pois"]:
        x, y = to_px(poi["x"], poi["z"])
        radius = poi["zone"] * SCALE
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], outline=(255, 255, 255, 140), width=2)
        draw.text((x - 30, y - 6), poi["id"], fill=(255, 255, 255, 255))

    image.convert("RGB").save(target)
    print("imagem salva em", target)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
