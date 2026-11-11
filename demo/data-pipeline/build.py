"""Turn raw OSM data around the BU -> Rupatoli route into a compact 3D-ready data file.

Output coordinates are metres: x = east, y = north, origin near the middle of the route.
"""
import json, math, random, sys, zlib
from pathlib import Path
from shapely.geometry import LineString, Point, Polygon, MultiPolygon, GeometryCollection
from shapely.ops import unary_union, polygonize
from shapely import prepared

HERE = Path(__file__).parent
RAW = json.load(open(HERE / "osm" / "raw.json", encoding="utf-8"))
OUT = Path(sys.argv[1])

ROUTE_LL = [[90.363432,22.659971],[90.363348,22.66094],[90.362798,22.660775],[90.362487,22.660683],[90.361868,22.66049],[90.361729,22.660445],[90.361349,22.660322],[90.361223,22.660282],[90.361084,22.660535],[90.36091,22.660782],[90.360719,22.66099],[90.360577,22.661128],[90.360405,22.661274],[90.36018,22.661418],[90.359981,22.661539],[90.359662,22.661688],[90.358864,22.662005],[90.357975,22.662343],[90.3571,22.662688],[90.351026,22.665027],[90.35079,22.665119],[90.350308,22.665298],[90.349812,22.665459],[90.349257,22.665602],[90.348536,22.665762],[90.347529,22.665975],[90.3471,22.666071],[90.346994,22.666074],[90.346606,22.666142],[90.346304,22.666189],[90.346309,22.666229],[90.346363,22.666649],[90.346419,22.667085],[90.346444,22.66729],[90.346472,22.667525],[90.346579,22.668407],[90.346658,22.668938],[90.34668,22.669094],[90.346767,22.669814],[90.346786,22.669996],[90.346818,22.67036],[90.346841,22.670943],[90.346846,22.67114],[90.346848,22.671291],[90.346851,22.671633],[90.34686,22.671986],[90.34683,22.672353],[90.346845,22.672867],[90.346847,22.673058],[90.346847,22.673417],[90.34685,22.673763],[90.346854,22.674081],[90.346857,22.674277],[90.346839,22.675168],[90.346828,22.676167],[90.346839,22.676546],[90.346835,22.676869],[90.346833,22.676983],[90.346836,22.677411],[90.346851,22.677796],[90.346895,22.678055]]

LAT0, LNG0 = 22.669, 90.3549
KX = math.cos(math.radians(LAT0)) * 111320
KY = 110574
def P(lng, lat): return ((lng - LNG0) * KX, (lat - LAT0) * KY)

R_CORR = 175     # half-width of the diorama strip
LANE = 2.4       # lane centre offset from the road centre line
KEY_R = 10.0     # turning loop radius at each end

route = LineString([P(*c) for c in ROUTE_LL])

# ---------- snap the routed line onto today's OSM roads ----------
# The public router's road data is older than the map tiles; along the N8 it sits ~10 m west of the
# current highway. Pull every point onto the current road centre line from the same OSM data the map shows.
from shapely.ops import nearest_points
def _ways(classes):
    ls = [LineString([P(g["lon"], g["lat"]) for g in e["geometry"]]) for e in RAW["elements"]
          if e["type"] == "way" and e.get("tags", {}).get("highway") in classes and len(e.get("geometry", [])) >= 2]
    return unary_union(ls)
TRUNK = _ways({"trunk", "trunk_link"})
ANYROAD = _ways({"trunk", "trunk_link", "primary", "secondary", "tertiary", "unclassified", "residential", "service", "living_street"})
def snap_line(line, rules, step=2.0):
    """rules(d) -> list of (network, max_distance) to try for the point at distance d along the line."""
    n = max(2, int(line.length / step) + 1)
    out = []
    for i in range(n):
        d = i * line.length / (n - 1)
        p = line.interpolate(d)
        for net, maxd in rules(d):
            if net.distance(p) <= maxd:
                q = nearest_points(net, p)[0]; out.append((q.x, q.y)); break
        else:
            out.append((p.x, p.y))
    return LineString(out)
# first ~338 m are campus roads, the rest is the Dhaka-Patuakhali Highway (N8)
route = snap_line(route, lambda d: [(ANYROAD, 12)] if d < 330 else [] if d < 350 else [(TRUNK, 30)])
L = route.length

# ---------- smooth centre line (Gaussian over 1 m samples, ends pinned) ----------
def resample(line, step):
    n = max(2, int(line.length / step) + 1)
    return [line.interpolate(i * line.length / (n - 1)).coords[0] for i in range(n)]

def gauss_smooth(pts, sigma, closed=False, pin=True):
    k = int(sigma * 3)
    w = [math.exp(-(i * i) / (2 * sigma * sigma)) for i in range(-k, k + 1)]
    n = len(pts); out = []
    for i in range(n):
        sx = sy = sw = 0.0
        for j, wj in zip(range(i - k, i + k + 1), w):
            if closed: p = pts[j % n]
            else:
                if j < 0: p = (2 * pts[0][0] - pts[-j][0], 2 * pts[0][1] - pts[-j][1])
                elif j >= n: m = 2 * (n - 1) - j; p = (2 * pts[-1][0] - pts[m][0], 2 * pts[-1][1] - pts[m][1])
                else: p = pts[j]
            sx += p[0] * wj; sy += p[1] * wj; sw += wj
        out.append((sx / sw, sy / sw))
    if pin and not closed: out[0] = pts[0]; out[-1] = pts[-1]
    return out

smooth = LineString(gauss_smooth(resample(route, 1.0), 7.0))

# ---------- the diorama strip ----------
corridor = route.buffer(R_CORR + 20, quad_segs=16).buffer(-20, quad_segs=16).simplify(0.8)
corr_prep = prepared.prep(corridor)

# ---------- OSM elements ----------
def way_coords(e): return [P(g["lon"], g["lat"]) for g in e.get("geometry", [])]

water_polys, buildings, roads, greens, campus_polys, bridge_lines = [], [], [], [], [], []
ROAD_W = {"trunk": 10, "trunk_link": 7, "primary": 9, "secondary": 8, "tertiary": 7, "unclassified": 5.5,
          "residential": 4.5, "living_street": 4, "service": 3.5, "track": 3}
GREEN_KIND = {"farmland": "farm", "meadow": "grass", "grass": "grass", "recreation_ground": "grass", "park": "park",
              "playground": "park", "wood": "wood", "forest": "wood", "scrub": "wood", "grassland": "grass", "wetland": "wet"}

for e in RAW["elements"]:
    t = e.get("tags", {})
    if e["type"] == "way":
        cs = way_coords(e)
        if len(cs) < 2: continue
        closed = len(cs) >= 4 and cs[0] == cs[-1]
        if "building" in t and closed:
            poly = Polygon(cs).buffer(0)
            if poly.area > 8: buildings.append((e["id"], poly, t))
        elif "highway" in t:
            w = ROAD_W.get(t["highway"])
            if w: roads.append((LineString(cs), w))
            if t.get("bridge") and t["highway"] == "trunk": bridge_lines.append(LineString(cs))
        elif (t.get("natural") == "water" or t.get("waterway") == "riverbank") and closed:
            water_polys.append(Polygon(cs).buffer(0))
        elif closed and (t.get("landuse") in GREEN_KIND or t.get("leisure") in GREEN_KIND or t.get("natural") in GREEN_KIND):
            kind = GREEN_KIND.get(t.get("landuse")) or GREEN_KIND.get(t.get("leisure")) or GREEN_KIND.get(t.get("natural"))
            greens.append((kind, Polygon(cs).buffer(0)))
        elif t.get("amenity") == "university" and closed:
            campus_polys.append(Polygon(cs).buffer(0))
    elif e["type"] == "relation":
        outers = [LineString([P(g["lon"], g["lat"]) for g in m["geometry"]]) for m in e.get("members", []) if m.get("role") == "outer" and m.get("geometry")]
        inners = [LineString([P(g["lon"], g["lat"]) for g in m["geometry"]]) for m in e.get("members", []) if m.get("role") == "inner" and m.get("geometry")]
        poly = unary_union(list(polygonize(unary_union(outers))))
        if inners: poly = poly.difference(unary_union(list(polygonize(unary_union(inners)))))
        if t.get("natural") == "water" or t.get("waterway") == "riverbank": water_polys.append(poly)
        elif "building" in t and not poly.is_empty: buildings.append((e["id"], poly, t))
        elif t.get("amenity") == "university": campus_polys.append(poly)

water = unary_union(water_polys).intersection(corridor).buffer(0)
land = corridor.difference(water).buffer(0)
campus = unary_union(campus_polys) if campus_polys else Polygon()

# ---------- bridge range along the route ----------
br = unary_union(bridge_lines)
bd = sorted(route.project(Point(c)) for g in getattr(br, "geoms", [br]) for c in (g.coords[0], g.coords[-1]))
B0, B1 = bd[0], bd[-1]
B_RAMP = min(90.0, (B1 - B0) / 3)
B_H = 5.0
def smoothstep(x): x = max(0.0, min(1.0, x)); return x * x * (3 - 2 * x)
def bridge_h(d): return B_H * smoothstep((d - B0) / B_RAMP) * smoothstep((B1 - d) / B_RAMP)

# ---------- driving loop: campus turnaround, lane A (to Rupatoli), roundabout, lane B (to campus) ----------
def unit(vx, vy): m = math.hypot(vx, vy) or 1; return vx / m, vy / m
CAMPUS_LANE = 1.8
def keyhole(E, u, R=KEY_R, lead=9.0, lane=LANE):
    """Points of a turning loop beyond point E, facing direction u. Arrive at v=+lane, leave at v=-lane."""
    v = (-u[1], u[0])
    W = lambda a, b: (E[0] + u[0] * a + v[0] * b, E[1] + u[1] * a + v[1] * b)
    pts = [W(lead * 0.45, lane + 0.4)]
    cx = R + lead
    for k in range(0, 25):
        ang = math.radians(140 - k * (280 / 24))
        pts.append(W(cx + R * math.cos(ang), R * math.sin(ang)))
    pts += [W(lead * 0.45, -lane - 0.4)]
    return pts

from shapely.ops import substring
def osrm_line(name):
    return LineString([P(*c) for c in json.load(open(HERE / name, encoding="utf-8"))["routes"][0]["geometry"]["coordinates"]])
def osrm_coords(name):
    return list(snap_line(osrm_line(name), lambda d: [(ANYROAD, 15)], step=1.5).coords)

# Each direction is routed on its own: where the N8 is a divided highway (Kathaltola to Rupatoli)
# the two directions use different carriageways.
TRUNK_WAYS = [(LineString([P(g["lon"], g["lat"]) for g in e["geometry"]]), e["tags"].get("oneway") == "yes")
              for e in RAW["elements"] if e["type"] == "way" and e.get("tags", {}).get("highway") in ("trunk", "trunk_link")]
def lane_offset_at(p):
    """Left-lane offset from the centre line: 1.3 m on a one-way carriageway, 2.4 m on a two-way highway, 1.8 m elsewhere."""
    best = min(TRUNK_WAYS, key=lambda w: w[0].distance(p))
    if best[0].distance(p) > 6: return CAMPUS_LANE
    return 1.3 if best[1] else LANE
def lane_of(pts, sigma=4.0, fixed=None):
    """Smooth a road centre line and return the left-hand lane (Bangladesh drives on the left).
    Offsets each point along its own left normal, which stays in one piece on tight corners."""
    c = gauss_smooth(resample(LineString(pts), 1.0), sigma)
    offs = [fixed if fixed is not None else lane_offset_at(Point(q)) for q in c]
    if fixed is None and len(offs) > 8:                                       # ease between lane widths
        offs = [o[0] for o in gauss_smooth([(o, 0) for o in offs], min(10.0, (len(offs) - 1) / 3.5))]
    out = []
    for i in range(len(c)):
        a, b = c[max(0, i - 2)], c[min(len(c) - 1, i + 2)]
        tx, ty = unit(b[0] - a[0], b[1] - a[1])
        out.append((c[i][0] - ty * offs[i], c[i][1] + tx * offs[i]))
    return out

rb = osrm_line("route_back.json")
route_back = snap_line(rb, lambda d: [(TRUNK, 30)] if d < rb.length - 350 else [] if d < rb.length - 330 else [(ANYROAD, 12)])
smooth_back = LineString(gauss_smooth(resample(route_back, 1.0), 7.0))
corner_d = smooth.project(Point(P(90.363348, 22.66094)))
A = lane_of(list(substring(smooth, corner_d, smooth.length).coords), sigma=1.0)   # corner -> Rupatoli
B = lane_of(list(smooth_back.coords), sigma=1.0)                                  # Rupatoli -> campus stop

# Rupatoli: real turnaround via the roundabout on the Dhaka-Patuakhali Highway (routed by OSRM)
TURN_R = lane_of(osrm_coords("turn_rupa.json"))
# Campus: carry on south past the stop, turn into the road to the Administrative Building,
# turn round in a small bulb at its dead end, come back and head north to where the route turns west.
camp = osrm_coords("loop_campus.json")
_steps = json.load(open(HERE / "loop_campus.json", encoding="utf-8"))["routes"][0]["legs"][0]["steps"]
_u = next(s["maneuver"]["location"] for s in _steps if s["maneuver"].get("modifier") == "uturn")
iD = min(range(len(camp)), key=lambda i: Point(camp[i]).distance(Point(P(*_u))))
out_full, back_full = LineString(camp[:iD + 1]), camp[iD:]
J = camp[1]                                        # junction where the admin-building road leaves the campus road
dJ = out_full.project(Point(J))
TURN_AT = dJ + 25.0                                # turn round 25 m in, well clear of Administrative Building 2
out_leg = list(substring(out_full, 0, TURN_AT).coords)
C = out_leg[-1]
pre = out_full.interpolate(TURN_AT - 3).coords[0]
iJ = min(range(len(back_full)), key=lambda i: Point(back_full[i]).distance(Point(J)))
back_leg = [C] + list(reversed(substring(out_full, dJ, TURN_AT).coords))[1:] + back_full[iJ + 1:]
KH_C = keyhole(C, unit(C[0] - pre[0], C[1] - pre[1]), R=8.0, lead=5.0, lane=CAMPUS_LANE)
CAMPUS_LOOP = lane_of(out_leg, fixed=CAMPUS_LANE)[:-2] + KH_C + lane_of(back_leg, fixed=CAMPUS_LANE)[2:]
KH_R = TURN_R

segments = [("TC", CAMPUS_LOOP), ("A", A), ("TR", TURN_R), ("B", B)]
raw_loop, tags = [], []
for name, pts in segments:
    dense = resample(LineString(pts), 1.0)
    raw_loop += dense; tags += [name] * len(dense)
# smooth joints, then resample evenly at 1 m
loop_s = gauss_smooth(raw_loop, 3.0, closed=True)
ring = LineString(loop_s + [loop_s[0]])
N = int(ring.length)
path, path_tag = [], []
tag_line = [(LineString(resample(LineString(p), 1.0)), n) for n, p in segments]
for i in range(N):
    p = ring.interpolate(i * ring.length / N)
    d_route = route.project(p)
    path.append((round(p.x, 2), round(p.y, 2), round(bridge_h(d_route), 2)))
    # tag by nearest segment
    path_tag.append(min(tag_line, key=lambda tl: tl[0].distance(p))[1])
LOOP_LEN = ring.length
# Where two lanes run side by side the nearest-segment tag can flip for a metre or two; absorb such blips.
i = 0
while i < len(path_tag):
    j = i
    while j < len(path_tag) and path_tag[j] == path_tag[i]: j += 1
    if j - i < 6 and i > 0:
        for k in range(i, j): path_tag[k] = path_tag[i - 1]
    i = j

# ---------- stops ----------
STOPS = [
    ("campus", "University of Barishal", "বরিশাল বিশ্ববিদ্যালয়", (90.363432, 22.659971), True),
    ("karna", "Karnakathi Junction", "কর্ণকাঠী", (90.36116, 22.6602), False),
    ("saown", "Saown Filling Station", "সাওন ফিলিং স্টেশন", (90.34653, 22.66734), False),
    ("kathal", "Kathaltola", "কাঠালতলা", (90.34692, 22.67428), False),
    ("rupa", "Rupatoli", "রূপাতলী", (90.346895, 22.678055), True),
]
stops_out = []
step = LOOP_LEN / N
for sid, name, bn, ll, term in STOPS:
    sp = Point(P(*ll))
    d_route = route.project(sp)
    centre = route.interpolate(d_route)
    entry = {"id": sid, "name": name, "bn": bn, "terminal": term, "x": round(centre.x, 1), "y": round(centre.y, 1), "stops": []}
    for lane in ("A", "B"):
        if sid == "campus" and lane == "A": continue
        if sid == "rupa" and lane == "B": continue
        idx = [i for i, tg in enumerate(path_tag) if tg == lane]
        best = min(idx, key=lambda i: Point(path[i][0], path[i][1]).distance(centre))
        if term:  # terminals: stop at the last point of the lane before the turning loop
            best = idx[-1] - 3
        i0, i1 = (best - 3) % N, (best + 3) % N
        hx, hy = unit(path[i1][0] - path[i0][0], path[i1][1] - path[i0][1])
        lx, ly = -hy, hx  # left of travel
        entry["stops"].append({"lane": lane, "s": round(best * step, 1),
                               "shelter": [round(path[best][0] + lx * 5.6, 2), round(path[best][1] + ly * 5.6, 2)],
                               "heading": round(math.atan2(hy, hx), 3)})
    stops_out.append(entry)

# ---------- roads ----------
road_geoms = [ln.buffer(w / 2, quad_segs=4) for ln, w in roads]
road_geoms += [route.buffer(5.2, quad_segs=8), smooth.buffer(5.2, quad_segs=8), smooth_back.buffer(5.2, quad_segs=8),
               LineString(TURN_R).buffer(4.5), LineString(CAMPUS_LOOP).buffer(4.0),
               Polygon(KH_C).buffer(0).buffer(-1)]
roads_u = unary_union(road_geoms)
roads_land = roads_u.intersection(land).buffer(0).simplify(0.3)
route_zone = unary_union([smooth.buffer(7.5), smooth_back.buffer(7.5), LineString(TURN_R).buffer(6), LineString(CAMPUS_LOOP).buffer(6), Polygon(KH_C).buffer(6)])

# ---------- buildings ----------
def est_levels(bid, poly, t):
    """Floors from OSM when tagged; most buildings here are not, so estimate from footprint size (stable per building)."""
    rnd = random.Random(bid); a = poly.area
    try: return max(1, min(12, int(float(t.get("building:levels")))))
    except (TypeError, ValueError):
        if a < 70: return 1 if rnd.random() < 0.75 else 2
        if a < 200: return rnd.choice([1, 2, 2, 3])
        if a < 600: return rnd.choice([2, 3, 4, 5])
        return rnd.choice([3, 4, 5, 6])
inner = prepared.prep(corridor.buffer(-6))
road_prep = prepared.prep(unary_union([roads_u.buffer(0.6), route_zone]))
water_prep = prepared.prep(water)
campus_prep = prepared.prep(campus)
houses, blocks = [], []
for bid, poly, t in buildings:
    if poly.geom_type != "Polygon": poly = max(getattr(poly, "geoms", [poly]), key=lambda g: g.area)
    c = poly.centroid
    if not inner.contains(poly) or road_prep.intersects(poly) or water_prep.intersects(poly): continue
    rnd = random.Random(bid)
    a = poly.area
    levels = est_levels(bid, poly, t)
    is_campus = campus_prep.contains(c)
    if a < 110 and levels == 1 and not is_campus:
        rect = poly.minimum_rotated_rectangle
        rc = list(rect.exterior.coords)
        e1 = (rc[1][0] - rc[0][0], rc[1][1] - rc[0][1]); e2 = (rc[2][0] - rc[1][0], rc[2][1] - rc[1][1])
        l1, l2 = math.hypot(*e1), math.hypot(*e2)
        long_e, lng_len, sh_len = (e1, l1, l2) if l1 >= l2 else (e2, l2, l1)
        ang = math.atan2(long_e[1], long_e[0])
        houses.append([round(c.x, 1), round(c.y, 1), round(lng_len, 1), round(sh_len, 1), round(ang, 3), rnd.randrange(6)])
    else:
        ext = poly.simplify(0.35).exterior.coords[:-1]
        if len(ext) < 3: continue
        flat = [round(v, 1) for xy in ext for v in xy]
        blocks.append([levels, 1 if is_campus else 0, rnd.randrange(8)] + flat)

# ---------- trees (Barishal is very green: coconut palms and leafy trees between houses) ----------
greens_c = [(k, g.intersection(land)) for k, g in greens]
wood_prep = prepared.prep(unary_union([g for k, g in greens_c if k == "wood"]) if greens_c else Polygon())
farm_prep = prepared.prep(unary_union([g for k, g in greens_c if k in ("farm", "wet")]) if greens_c else Polygon())
bld_u = unary_union([p for _, p, _ in buildings]).buffer(1.8)
block_prep = prepared.prep(unary_union([bld_u, roads_u.buffer(2.2), water.buffer(1.5), route_zone.buffer(2)]))
land_in = prepared.prep(land.buffer(-4))
rnd = random.Random(7)
trees = []
minx, miny, maxx, maxy = corridor.bounds
SP = 9.0
y = miny
while y < maxy:
    x = minx
    while x < maxx:
        px, py = x + rnd.uniform(-3.5, 3.5), y + rnd.uniform(-3.5, 3.5)
        p = Point(px, py)
        if land_in.contains(p) and not block_prep.contains(p):
            dens = 0.85 if wood_prep.contains(p) else 0.08 if farm_prep.contains(p) else 0.42
            if rnd.random() < dens:
                kind = 1 if rnd.random() < 0.32 else 0  # 1 = coconut palm, 0 = leafy tree
                trees.append([round(px, 1), round(py, 1), round(rnd.uniform(0.75, 1.3), 2), kind, round(rnd.uniform(0, 6.283), 2)])
        x += SP
    y += SP

# ---------- boats on the Kirtankhola ----------
boats = []
big_water = max(getattr(water, "geoms", [water]), key=lambda g: g.area)
bw_in = prepared.prep(big_water.buffer(-12))
bridge_zone = smooth.buffer(30)
tries = 0
while len(boats) < 6 and tries < 5000:
    tries += 1
    bx0, by0, bx1, by1 = big_water.bounds
    p = Point(rnd.uniform(bx0, bx1), rnd.uniform(by0, by1))
    if bw_in.contains(p) and not bridge_zone.contains(p) and all(math.hypot(p.x - b[0], p.y - b[1]) > 40 for b in boats):
        boats.append([round(p.x, 1), round(p.y, 1), round(rnd.uniform(0, 6.283), 2)])

# ---------- bridge piers ----------
piers = []
d = B0 + 12
while d < B1 - 12:
    c = route.interpolate(d)
    if water.contains(c): piers.append([round(c.x, 1), round(c.y, 1), round(bridge_h(d), 2), round(d, 1)])
    d += 26

# ---------- raised buildings for the 3D street map ----------
# A few roadside shops are drawn in OSM over the edge of the N8. Leave those flat (the map still shows
# their footprint) so the bus never drives through a raised wall.
loop_line = LineString([(p[0], p[1]) for p in path] + [(path[0][0], path[0][1])])
bus_sweep = prepared.prep(loop_line.buffer(1.9))
near_route = prepared.prep(unary_union([route.buffer(650), route_back.buffer(650)]))
map_bld, flattened = [], 0
for bid, poly, t in buildings:
    if poly.geom_type != "Polygon": poly = max(getattr(poly, "geoms", [poly]), key=lambda g: g.area)
    if not near_route.contains(poly.centroid): continue
    if bus_sweep.intersects(poly): flattened += 1; continue
    ext = poly.simplify(0.3).exterior.coords[:-1]
    if len(ext) < 3: continue
    map_bld.append([round(est_levels(bid, poly, t) * 3.2, 1)] + [round(v, 1) for xy in ext for v in xy])

# ---------- polygon export helpers ----------
def polys_of(g):
    if g.is_empty: return []
    if g.geom_type == "Polygon": return [g]
    return [p for p in getattr(g, "geoms", []) if p.geom_type == "Polygon"]
def export_poly(p, tol=0.3):
    p = p.simplify(tol)
    if p.is_empty or p.geom_type != "Polygon" or p.area < 1: return None
    ring = lambda r: [round(v, 1) for xy in list(r.coords)[:-1] for v in xy]
    return [ring(p.exterior)] + [ring(h) for h in p.interiors if Polygon(h).area > 2]

out = {
    "origin": [LNG0, LAT0], "routeLen": round(L, 1), "loopLen": round(LOOP_LEN, 2),
    "route": [[round(x, 1), round(y, 1)] for x, y in resample(smooth, 4.0)],
    "routeHeights": [round(bridge_h(route.project(Point(x, y))), 2) for x, y in resample(smooth, 4.0)],
    "routeBack": [[round(x, 1), round(y, 1)] for x, y in resample(smooth_back, 4.0)],
    "mapBld": map_bld,
    "path": [v for p in path for v in p],
    "pathTag": "".join({"A": "a", "B": "b", "TR": "r", "TC": "c"}[t] for t in path_tag),
    "land": [e for e in (export_poly(p, 0.6) for p in polys_of(land)) if e],
    "water": [e for e in (export_poly(p, 0.6) for p in polys_of(water)) if e],
    "roads": [e for e in (export_poly(p, 0.25) for p in polys_of(roads_land)) if e],
    "greens": [[k] + e for k, g in greens_c for e in (export_poly(p, 0.6) for p in polys_of(g)) if e],
    "campus": [e for e in (export_poly(p, 0.6) for p in polys_of(campus.intersection(land))) if e],
    "houses": houses, "blocks": blocks, "trees": trees, "boats": boats, "piers": piers,
    "bridge": {"d0": round(B0, 1), "d1": round(B1, 1), "ramp": round(B_RAMP, 1), "h": B_H},
    "stops": stops_out,
}
OUT.write_text("/* Generated from OpenStreetMap data (c) OpenStreetMap contributors, ODbL. */\nwindow.CORRIDOR = " +
               json.dumps(out, ensure_ascii=False, separators=(",", ":")) + ";\n", encoding="utf-8")
print("map buildings", len(map_bld), "flattened", flattened)
print("route", round(L), "loop", round(LOOP_LEN), "bridge", round(B0), round(B1), "piers", len(piers))
print("houses", len(houses), "blocks", len(blocks), "trees", len(trees), "boats", len(boats))
print("land", len(out["land"]), "water", len(out["water"]), "roads", len(out["roads"]), "greens", len(out["greens"]), "campus", len(out["campus"]))
print("stops", [(s["id"], [x["s"] for x in s["stops"]]) for s in stops_out])
print("size KB", round(OUT.stat().st_size / 1024))
