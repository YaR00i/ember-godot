"""Generate Ember's isolated 1 km heightfield and metre-space placement recipe.

Python 3, NumPy, Pillow. Coordinates are [x,z] metres, origin at the first
image pixel. Later zones win on overlaps. Source PNG black/white map to the
CLI height range. A generated PNG round-trips using its manifest extrema.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import secrets
import shutil
import tempfile

import numpy as np
from PIL import Image

SIZE = 1000
PIXELS = 1024
STEP = SIZE / PIXELS
TYPES = {"tree": 2.3, "birch": 1.8, "rock": 2.0, "house": 6.0, "crate": 0.85, "lamp": 0.65}
KINDS = ("village", "forest", "meadow", "rocks", "lake", "mountain")
COLORS = {"meadow": (132, 157, 84), "forest": (86, 127, 70), "rocks": (129, 135, 99),
          "lake": (122, 149, 99), "mountain": (131, 135, 104), "village": (153, 155, 100)}


def smooth(t):
    t = np.clip(t, 0, 1)
    return t*t*(3-2*t)


def random_field(rng, nx, nz):
    """Smooth noise on the whole domain, including the final partial interval."""
    grid = rng.uniform(-1, 1, (nz + 1, nx + 1)).astype("f4")
    px = np.arange(PIXELS) * nx / PIXELS
    pz = np.arange(PIXELS) * nz / PIXELS
    ix, iz = px.astype(int), pz.astype(int)
    fx, fz = smooth(px-ix)[None, :], smooth(pz-iz)[:, None]
    a = grid[iz[:, None], ix] * (1-fx) + grid[iz[:, None], ix+1] * fx
    b = grid[iz[:, None]+1, ix] * (1-fx) + grid[iz[:, None]+1, ix+1] * fx
    return (a*(1-fz)+b*fz).astype("f4")


def zone_distance(z, x, y):
    dx, dz = abs(x-z["cx"])/z["rx"], abs(y-z["cz"])/z["rz"]
    return np.maximum(dx, dz) if z["shape"] == "box" else np.hypot(dx, dz)


def check_recipe(recipe):
    zones = recipe["zones"]
    if not isinstance(zones, list) or not zones or len(zones) > 250:
        raise ValueError("Expected 1 to 250 zones")
    if not math.isfinite(recipe["water_y"]):
        raise ValueError("water_y must be finite")
    names = set()
    for z in zones:
        if not isinstance(z["name"], str) or not z["name"] or z["name"] in names:
            raise ValueError("Every zone needs a unique name")
        names.add(z["name"])
        if z["kind"] not in KINDS or z["shape"] not in ("box", "ellipse"):
            raise ValueError(f"Unknown zone kind or shape: {z['name']}")
        for c,r in [("cx","rx"),("cz","rz")]:
            if not (0 < z[r] <= SIZE and z[r] <= z[c] <= SIZE-z[r]):
                raise ValueError(f"Zone lies outside world: {z['name']}")
        if not all(0 <= z[k] <= 256 for k in ("grass","flowers")):
            raise ValueError("Vegetation density must be in [0,256]/mВІ")
        for k,v in z["props"].items():
            if k not in TYPES or type(v) is not int or not 0 <= v <= 20000:
                raise ValueError(f"Invalid count for {z['name']}/{k}")
    # Each of the test's six destinations has a named job. Zero its counts to
    # disable its contents without changing the traversal/landmark contract.
    if set(KINDS) != {z["kind"] for z in zones}:
        raise ValueError("The kilometre test needs at least one zone of every kind")


def procedural_height(zones, rng, x, z, water):
    low = random_field(rng, 5, 5)
    mid = random_field(rng, 14, 14)
    detail = random_field(rng, 39, 39)
    height = water + 18 + 10*low + 4*mid + detail
    for region in zones:
        if region["kind"] != "mountain":
            continue
        # A chain of asymmetric summits with seeded saddles and ridges.
        for i in range(5):
            cx = region["cx"] + region["rx"] * (i-2)*0.36 + rng.uniform(-24,24)
            cz = region["cz"] + rng.uniform(-0.40,0.40)*region["rz"]
            sx = rng.uniform(0.32,0.60)*region["rx"]
            sz = rng.uniform(0.40,0.75)*region["rz"]
            nx = (x-cx + mid*12)/sx
            nz = (z-cz + low*18)/sz
            height += rng.uniform(32,67)*np.exp(-(nx*nx+nz*nz))
    for region in zones:
        kind = region["kind"]
        if kind == "village":
            fade = 1-smooth((zone_distance(region,x,z)-0.94)/0.42)
            height = height*(1-fade) + (water+15+0.005*(x-region["cx"]))*fade
        if kind == "lake":
            cx, cz, rx, rz = (region[k] for k in ("cx","cz","rx","rz"))
            shore = np.hypot((x-cx)/(rx*0.74),(z-cz)/(rz*0.68)) + 0.12*mid
            bed = water + 9*(shore**2-1)
            height = np.minimum(height, bed)
            # Downstream section joins the submerged basin and exits the south edge.
            t = (z-cz)/max(1,SIZE-cz)
            phase = rng.uniform(0, 6.28)
            axis = cx + rx*(0.42*t + 0.32*np.sin(7*t+phase)-0.32*np.sin(phase))
            channel = water + 2.2*(((x-axis)/max(5,rx*0.07))**2 - 1)
            height = np.where(t>=0, np.minimum(height,channel), height)
    return height.astype("<f4")


def read_height(path, minimum, maximum):
    if not math.isfinite(minimum) or not math.isfinite(maximum) or minimum >= maximum:
        raise ValueError("Height import needs a finite increasing metre range")
    with Image.open(path) as src:
        if src.format != "PNG" or src.mode not in ("L","I;16","I;16B","I;16L","I"):
            raise ValueError("Heightmap must be an 8- or 16-bit grayscale PNG")
        if min(src.size) < 2:
            raise ValueError("Heightmap must be at least 2 pixels in each dimension")
        denom = 255 if src.mode == "L" else 65535
        samples = np.asarray(src, dtype=np.float32)
        if samples.min() < 0 or samples.max() > denom:
            raise ValueError("Invalid grayscale sample")
        resized = Image.fromarray(samples).resize((PIXELS,PIXELS), Image.Resampling.BILINEAR)
        return (minimum+np.asarray(resized)*(maximum-minimum)/denom).astype("<f4")


def streets(zones,x,z):
    road = np.full((PIXELS,PIXELS), np.inf, dtype="f4")
    for area in zones:
        if area["kind"] != "village":
            continue
        dx,dz = x-area["cx"],z-area["cz"]
        # One through-road and two side streets. Values are metres to road edge.
        across = np.maximum(abs(dz)-3.1,abs(dx)-area["rx"]*1.30)
        main = np.maximum(abs(dx)-3.5,abs(dz)-area["rz"]*1.25)
        side = np.maximum(abs(dx-0.51*area["rx"])-2.4,abs(dz)-area["rz"]*0.9)
        road = np.minimum(road,np.minimum(main,np.minimum(side,across)))
    return road


def destinations(zones, height, slope, water):
    dry = (height>water+1) & (slope<0.55)
    landmarks = {}
    y,x = np.ogrid[:PIXELS,:PIXELS]
    for kind in KINDS:
        area = next(a for a in zones if a["kind"]==kind)
        eligible = dry & (zone_distance(area,x*STEP,y*STEP) <= 1.0)
        if not eligible.any():
            # An imported map may have submerged an entire prescribed zone.
            eligible = dry
        if not eligible.any():
            raise ValueError("No dry walkable spawn on the supplied heightmap")
        if kind == "mountain":
            score = -height
        else:
            score = (x*STEP-area["cx"])**2+(y*STEP-area["cz"])**2
        j,i = np.unravel_index(np.where(eligible,score,np.inf).argmin(),height.shape)
        landmarks[kind]=[round(i*STEP,3),round(j*STEP,3)]
    return landmarks


def place_props(zones,height,slope,region_id,road,water,marks,seed):
    result, counts, buckets = [], {}, defaultdict(list)
    cell = 16.0
    for index,area in enumerate(zones):
        counts[area["name"]] = {}
        for kind,wanted in area["props"].items():
            # Changing flower density, or reordering a different model list,
            # doesn't reseed the candidates for this layer.
            key = f"{seed}/{area['name']}/{kind}".encode()
            rng = np.random.default_rng(int.from_bytes(hashlib.sha256(key).digest()[:8],"little"))
            count = 0
            for _ in range(wanted*160):
                if count==wanted: break
                scale = rng.uniform(0.83,1.18)
                radius = TYPES[kind]*scale
                x = rng.uniform(area["cx"]-area["rx"],area["cx"]+area["rx"])
                z = rng.uniform(area["cz"]-area["rz"],area["cz"]+area["rz"])
                if not radius<=x<SIZE-radius or not radius<=z<SIZE-radius:continue
                i,j = int(x/STEP),int(z/STEP)
                if region_id[j,i]!=index or slope[j,i] > (0.14 if kind in ("house","crate","lamp") else 0.62):
                    continue
                if kind in ("house","lamp") and road[j,i] > radius + (12 if kind=="house" else 3):
                    continue
                if road[j,i]<radius+0.9 or any(math.hypot(x-mx,z-mz)<radius+3 for mx,mz in marks.values()):
                    continue
                span = max(1,math.ceil(radius/STEP))
                samples = height[max(0,j-span):min(PIXELS,j+span+1),max(0,i-span):min(PIXELS,i+span+1)]
                if samples.min()<=water+0.6 or (kind=="house" and np.ptp(samples)>0.9):
                    continue
                gx,gz = int(x/cell),int(z/cell)
                neighbors = (obj for bx in range(gx-1,gx+2) for bz in range(gz-1,gz+2) for obj in buckets[(bx,bz)])
                if any(math.hypot(x-px,z-pz)<radius+r+0.4 for px,pz,r in neighbors):
                    continue
                buckets[gx,gz].append((x,z,radius))
                yaw = rng.uniform(-math.pi,math.pi)
                if kind=="house": yaw = round(yaw/(math.pi/2))*(math.pi/2)
                result.append({"type":kind,"zone":area["name"],"x":round(x,3),"z":round(z,3),
                               "y":round(float(height[j,i]),3),"yaw":round(yaw,5),"scale":round(scale,4)})
                count+=1
            counts[area["name"]][kind]=count
    return result, counts


def build(args,out):
    recipe = json.loads(args.recipe.read_text(encoding="utf-8-sig"))
    check_recipe(recipe)
    zones, water = recipe["zones"],float(recipe["water_y"])
    seed = args.seed if args.seed is not None else secrets.randbits(31)
    if not 0<=seed<=2**63-1:raise ValueError("seed must be in [0,2^63)")
    rng=np.random.default_rng(seed)
    z,x=np.ogrid[:PIXELS,:PIXELS]; x,z=x*STEP,z*STEP
    height = read_height(args.heightmap,args.min_height,args.max_height) if args.heightmap else procedural_height(zones,rng,x,z,water)
    lo,hi = float(height.min()),float(height.max())
    height.astype("<f4").tofile(out/"height.f32")
    norm = np.rint((height.astype(np.float64)-lo)*(65535/(hi-lo))).astype("uint16") if hi>lo else np.zeros_like(height,dtype="uint16")
    Image.fromarray(norm).save(out/"height.png")
    dz,dx=np.gradient(height,STEP);slope=np.hypot(dx,dz)
    road=streets(zones,x,z)
    regions=np.full((PIXELS,PIXELS),-1,dtype=np.int16)
    colors=np.empty((PIXELS,PIXELS,3),dtype=np.float32);colors[:]=[137,152,90]
    noise=random_field(rng,33,33)
    for idx,area in enumerate(zones):
        dist=zone_distance(area,x,z)
        regions[dist<=1]=idx
        weight=smooth((1-dist)/0.17)[...,None]
        colors=colors*(1-weight)+np.array(COLORS[area["kind"]])*weight
    steep=smooth((slope-0.48)/0.55)[...,None]
    colors=colors*(1-steep)+np.array([153,144,130])*steep
    shore=smooth((water+1.8-height)/2.3)[...,None]
    colors=colors*(1-shore)+np.array([172,161,120])*shore
    road_mix=smooth(0.8-road)[...,None]*(height>water+0.4)[...,None]
    rock_weight = steep[...,0].copy()
    for area in zones:
        if area["kind"] == "rocks":
            rock_weight = np.maximum(rock_weight, smooth((1-zone_distance(area,x,z))/0.32)*(0.72+0.23*noise))
    sand_weight = np.maximum(shore[...,0],road_mix[...,0])
    layers = np.stack([rock_weight, sand_weight, np.zeros_like(sand_weight)],axis=-1)
    Image.fromarray(np.rint(np.clip(layers,0,1)*255).astype("uint8")).save(out/"surface.png")
    colors=colors*(1-road_mix)+np.array([171,149,121])*road_mix
    colors+=noise[...,None]*8
    Image.fromarray(np.clip(colors,0,255).astype("uint8")).save(out/"color.png")
    marks=destinations(zones,height,slope,water)
    props,counts=place_props(zones,height,slope,regions,road,water,marks,seed)
    shade = np.clip(1.0+0.5*dx+0.35*dz,0.55,1.45)
    preview = np.clip(colors*shade[...,None],0,255).astype("uint8")
    preview[height<water] = (67,130,146)
    for prop in props:
        px,pz = int(prop["x"]/STEP),int(prop["z"]/STEP)
        pigment = {"tree":(57,91,54),"birch":(76,109,65),"rock":(118,112,102),
                   "house":(164,83,53),"crate":(123,85,48),"lamp":(237,189,86)}[prop["type"]]
        extent = 4 if prop["type"]=="house" else 1
        preview[max(pz-extent,0):pz+extent+1,max(px-extent,0):px+extent+1] = pigment
    Image.fromarray(preview).save(out/"overview.png")
    valid=smooth((height-water-0.35)/0.7)*smooth((0.78-slope)/0.32)*smooth((road-0.55)/0.9)
    for obj in props:
        if obj["type"] not in ("house","rock","crate","lamp"):continue
        radius=TYPES[obj["type"]]*obj["scale"]
        x0=max(0,int((obj["x"]-radius)/STEP));x1=min(PIXELS,math.ceil((obj["x"]+radius)/STEP)+1)
        z0=max(0,int((obj["z"]-radius)/STEP));z1=min(PIXELS,math.ceil((obj["z"]+radius)/STEP)+1)
        distance=np.hypot(x[:,x0:x1]-obj["x"],z[z0:z1]-obj["z"])
        valid[z0:z1,x0:x1]*=smooth((distance-radius*0.75)/max(0.25,radius*0.25))
    mask=np.zeros((PIXELS,PIXELS,3),dtype=np.uint8)
    grass_max=max(area["grass"] for area in zones)
    flowers_max=max(area["flowers"] for area in zones)
    if grass_max:
        mask[...,0][regions<0] = np.rint(255*min(7.0/grass_max,1.0)*valid[regions<0]*(0.76+0.24*noise[regions<0]))
    for idx,area in enumerate(zones):
        sel=regions==idx
        if area["grass"]>0:mask[...,0][sel]=np.rint(255*area["grass"]/grass_max*valid[sel]*(0.76+0.24*noise[sel]))
        if area["flowers"]>0:mask[...,1][sel]=np.rint(255*area["flowers"]/flowers_max*valid[sel]*smooth((noise[sel]+0.3)/0.85))
    Image.fromarray(mask).save(out/"foliage.png")
    manifest={"version":1,"size_m":SIZE,"pixels":PIXELS,"seed":seed,"water_y":water,
              "height_min_m":lo,"height_max_m":hi,"source":"import" if args.heightmap else "procedural",
              "grass_max_per_m2":grass_max,"flowers_max_per_m2":flowers_max,
              "zones":zones,"landmarks":marks,"props":props,"placed":counts}
    # Local bounds let the renderer cull a meadow tile independently of the far mountain.
    manifest["tile_height_bounds"] = []
    for z0 in range(0,SIZE,16):
        row = []
        for x0 in range(0,SIZE,16):
            patch = height[max(0,int(z0/STEP)-1):math.ceil((z0+16)/STEP)+2,
                           max(0,int(x0/STEP)-1):math.ceil((x0+16)/STEP)+2]
            row.append([round(float(patch.min()),3),round(float(patch.max()),3)])
        manifest["tile_height_bounds"].append(row)
    manifest["shortfalls"] = {zone["name"]:{k:n-counts[zone["name"]][k] for k,n in zone["props"].items()
                              if n != counts[zone["name"]][k]} for zone in zones}
    if args.heightmap:
        manifest["source_sha256"] = hashlib.sha256(args.heightmap.read_bytes()).hexdigest()
        manifest["import_range_m"] = [args.min_height,args.max_height]
        shutil.copyfile(args.heightmap,out/"source.png")
    (out/"world.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf8")
    return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipe",type=Path,default=Path(__file__).with_name("default.json"))
    parser.add_argument("--output",type=Path,help="New directory (default: kilometre-output in the current directory)")
    parser.add_argument("--seed",type=int)
    parser.add_argument("--heightmap",type=Path)
    parser.add_argument("--min-height",type=float,default=0)
    parser.add_argument("--max-height",type=float,default=180)
    args=parser.parse_args()
    output=(args.output or Path("kilometre-output")).resolve()
    if output.exists():parser.error(f"Output already exists: {output}. Choose a new directory.")
    output.parent.mkdir(parents=True,exist_ok=True)
    try:
        # Publish only the completed directory. A failed import leaves no half-location.
        with tempfile.TemporaryDirectory(dir=output.parent,prefix=".kilometre-build-") as temp:
            work=Path(temp)/"world";work.mkdir()
            manifest=build(args,work)
            work.rename(output)
    except (ValueError,KeyError,TypeError,OSError) as exc:
        parser.exit(2,f"Generation failed: {exc}\n")
    print(f"Generated {output} | seed {manifest['seed']} | {len(manifest['props'])} props | 1000 x 1000 m")
    for name, missing in manifest["shortfalls"].items():
        if missing:
            print(f"{name}: no suitable sites for {missing}")


if __name__=="__main__":
    main()
