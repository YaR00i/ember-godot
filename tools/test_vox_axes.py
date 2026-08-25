"""Axis contract: MagicaVoxel Z-up → Ember/Godot Y-up, ember(x,y,z) = vox(x,z,y).

Mirrors joi-conductor src/game/voxel/vox/voxFile.ts + emberVoxCodec.ts.
Run from anywhere: python tools/test_vox_axes.py
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JOI_PACK = ROOT.parent / "joi-conductor" / "content" / "ember"
LANTERN_VOX = JOI_PACK / "voxels" / "models" / "vox_fan_lantern_paper.vox"
LANTERN_JSON = JOI_PACK / "voxels" / "models" / "vox_fan_lantern_paper.json"
MAP_JSON = JOI_PACK / "maps" / "fan_town.json"


def parse_vox(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"VOX " or data[8:12] != b"MAIN":
        raise SystemExit(f"not a vox file: {path}")
    models: list[dict] = []
    pending = None

    def walk(start: int, end: int) -> None:
        nonlocal pending
        offset = start
        while offset + 12 <= end:
            cid = data[offset : offset + 4].decode("ascii")
            content, children = struct.unpack_from("<ii", data, offset + 4)
            content_start = offset + 12
            content_end = content_start + content
            children_end = content_end + children
            if content_end > end or children_end > end:
                break
            if cid == "SIZE" and content >= 12:
                pending = struct.unpack_from("<iii", data, content_start)
            elif cid == "XYZI" and content >= 4 and pending:
                n = struct.unpack_from("<i", data, content_start)[0]
                voxels = []
                p = content_start + 4
                for _ in range(n):
                    if p + 4 > content_end:
                        break
                    x, y, z, i = data[p : p + 4]
                    voxels.append((x, y, z, i))
                    p += 4
                models.append({"size": pending, "voxels": voxels})
                pending = None
            if children:
                walk(content_end, children_end)
            offset = children_end

    main_content, main_children = struct.unpack_from("<ii", data, 12)
    walk(20 + main_content, 20 + main_content + main_children)
    if not models:
        raise SystemExit("vox: no model")
    return models[0]


def vox_to_ember(x: int, y: int, z: int) -> tuple[int, int, int]:
    return (x, z, y)


def ember_size(sx: int, sy: int, sz: int) -> tuple[int, int, int]:
    return (sx, sz, sy)


def main() -> int:
    errors: list[str] = []
    if not LANTERN_VOX.is_file():
        print(f"SKIP vox file missing: {LANTERN_VOX}")
        return 0
    model = parse_vox(LANTERN_VOX)
    sx, sy, sz = model["size"]
    es = ember_size(sx, sy, sz)
    if es[0] != sx or es[1] != sz or es[2] != sy:
        errors.append(f"ember_size mismatch {es} from vox {(sx, sy, sz)}")
    sample = model["voxels"][0]
    ex, ey, ez = vox_to_ember(*sample[:3])
    if (ex, ey, ez) != (sample[0], sample[2], sample[1]):
        errors.append(f"axis map wrong for {sample} -> {(ex, ey, ez)}")
    if ey > es[1] or ez > es[2]:
        errors.append(f"ember voxel out of ember size {es}")
    print(
        f"ok vox {LANTERN_VOX.name}: vox_size={(sx, sy, sz)} "
        f"ember_size={es} voxels={len(model['voxels'])}"
    )

    prefab = json.loads(LANTERN_JSON.read_text(encoding="utf-8"))
    inner = prefab.get("model") or {}
    if inner.get("emissiveCastsLight") is not True:
        errors.append("lantern json missing emissiveCastsLight")
    if inner.get("emissiveLightShadows") is not True:
        errors.append("lantern json missing emissiveLightShadows")
    print(
        f"ok lantern json range={inner.get('emissiveLightRange')} "
        f"shadows={inner.get('emissiveLightShadows')}"
    )

    town = json.loads(MAP_JSON.read_text(encoding="utf-8"))
    if town.get("id") != "fan_town":
        errors.append("fan_town id mismatch")
    props = town.get("voxelProps") or []
    lanterns = [p for p in props if str(p.get("modelId", "")).startswith("vox_fan_lantern")]
    if len(lanterns) < 3:
        errors.append(f"expected several lanterns, got {len(lanterns)}")
    print(f"ok fan_town voxelProps={len(props)} lanterns={len(lanterns)}")

    if errors:
        print("FAIL")
        for err in errors:
            print(" -", err)
        return 1
    print("PASS ember-godot pack contract")
    return 0


if __name__ == "__main__":
    sys.exit(main())
