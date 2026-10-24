#!/usr/bin/env python3
"""Build the outline geometry bundled with Fathom.

Downloads Natural Earth 1:50m cultural vectors (public domain), keeps a
recognizable landmass for each country and US state, projects every shape
with a local Lambert azimuthal equal-area projection, simplifies the rings,
and writes compact JSON.

The Natural Earth files are not committed. The generated JSON is.

Usage:
    python3 scripts/prepare_shapes.py
    python3 scripts/prepare_shapes.py --preview-dir /tmp/fathom-preview

Python 3.9+ standard library only. Shape previews are optional and use
Pillow when it is installed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CACHE = ROOT / "data" / "cache"
DEFAULT_OUT = ROOT / "Sources" / "FathomCore" / "Resources" / "regions.json"

COUNTRIES_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_admin_0_countries.geojson"
)
STATES_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_admin_1_states_provinces.geojson"
)

EARTH_RADIUS_M = 6_371_008.8
EARTH_RADIUS_KM = EARTH_RADIUS_M / 1000.0

# Polygons smaller than this cannot bridge two landmasses together.
MAJOR_MIN_KM2 = 2_000.0
# Distance under which two major landmasses join the same cluster.
BRIDGE_GAP_KM = 480.0
# Wider bridge for real archipelagos, where islands are the country.
WIDE_BRIDGE_GAP_KM = 950.0
# Coastal islets join a kept cluster when they sit this close.
ATTACH_GAP_KM = 260.0
# A separated landmass this large relative to the main one is still shown
# (peninsular Malaysia and Malaysian Borneo, for example).
SECONDARY_AREA_RATIO = 0.30
LONG_SIDE = 1000
MIN_AREA_KM2 = 20.0

# ADM0_A3 values whose geometry is folded into another feature before naming.
MERGE_ADM = {
    "CYN": "CYP",  # Northern Cyprus is drawn as part of Cyprus
    "SOL": "SOM",  # Somaliland is drawn as part of Somalia
}

INCLUDE_TYPES = {"Sovereign country", "Country", "Sovereignty"}
# Mapped territories that are separate Natural Earth features and belong in a
# country quiz. Antarctica and other non-countries are not in this set.
EXTRA_INCLUDE_ADM = {"KOS", "PSX", "SAH"}
EXCLUDE_ADM = {"ATA", "CYN", "SOL", "KAS"}

# Archipelagos that should absorb islands across wider water gaps.
WIDE_BRIDGE_ADM = {
    "IDN", "PHL", "JPN", "GRC", "FJI", "BHS", "SYC", "CPV", "KIR",
    "MHL", "SLB", "VUT", "TON", "WSM", "MDV", "COM", "SGS",
}

DISPLAY_OVERRIDES = {
    "USA": "United States",
    "COD": "DR Congo",
    "COG": "Republic of the Congo",
    "SWZ": "Eswatini",
    "PRK": "North Korea",
    "KOR": "South Korea",
    "LAO": "Laos",
    "FSM": "Micronesia",
    "CIV": "Côte d'Ivoire",
    "RUS": "Russia",
    "TZA": "Tanzania",
    "BHS": "Bahamas",
    "GMB": "Gambia",
    "CZE": "Czechia",
    "PSX": "Palestine",
    "PSE": "Palestine",
    "SAH": "Western Sahara",
    "ESH": "Western Sahara",
    "KOS": "Kosovo",
    "GBR": "United Kingdom",
    "BRN": "Brunei",
    "MMR": "Myanmar",
    "CPV": "Cabo Verde",
    "TLS": "Timor-Leste",
    "VNM": "Vietnam",
    "MDA": "Moldova",
    "BOL": "Bolivia",
    "VEN": "Venezuela",
    "IRN": "Iran",
    "SYR": "Syria",
    "MKD": "North Macedonia",
}

EXTRA_ALIASES = {
    "USA": ["United States of America", "USA", "US", "America"],
    "GBR": ["UK", "Britain", "Great Britain", "United Kingdom of Great Britain and Northern Ireland"],
    "RUS": ["Russian Federation"],
    "KOR": ["Republic of Korea", "ROK"],
    "PRK": ["DPRK", "Democratic People's Republic of Korea"],
    "ARE": ["UAE", "Emirates"],
    "CIV": ["Ivory Coast", "Cote d'Ivoire"],
    "CZE": ["Czech Republic"],
    "SWZ": ["Swaziland", "eSwatini"],
    "MMR": ["Burma"],
    "CPV": ["Cape Verde"],
    "TLS": ["East Timor"],
    "NLD": ["Holland"],
    "COD": ["DRC", "Democratic Republic of the Congo", "Congo-Kinshasa"],
    "COG": ["Congo", "Congo-Brazzaville"],
    "MKD": ["Macedonia"],
    "LAO": ["Lao PDR"],
    "MDA": ["Republic of Moldova"],
    "TZA": ["United Republic of Tanzania"],
    "VNM": ["Viet Nam"],
    "BOL": ["Plurinational State of Bolivia"],
    "VEN": ["Bolivarian Republic of Venezuela"],
    "SYR": ["Syrian Arab Republic"],
    "IRN": ["Islamic Republic of Iran"],
    "BRN": ["Brunei Darussalam"],
    "FSM": ["Federated States of Micronesia"],
    "BHS": ["The Bahamas"],
    "GMB": ["The Gambia"],
    "TUR": ["Turkey", "Türkiye", "Turkiye"],
    "CAF": ["CAR"],
    "MAC": ["Macau"],
    "HKG": ["Hong Kong SAR", "Hong Kong S.A.R."],
    "PSE": ["State of Palestine"],
    "PSX": ["State of Palestine"],
    "WSM": ["Western Samoa"],
    "STP": ["Sao Tome and Principe", "São Tomé and Príncipe"],
    "CUW": ["Curacao"],
}

US_STATES = {
    "AL": "Alabama",
    "AK": "Alaska",
    "AZ": "Arizona",
    "AR": "Arkansas",
    "CA": "California",
    "CO": "Colorado",
    "CT": "Connecticut",
    "DE": "Delaware",
    "FL": "Florida",
    "GA": "Georgia",
    "HI": "Hawaii",
    "ID": "Idaho",
    "IL": "Illinois",
    "IN": "Indiana",
    "IA": "Iowa",
    "KS": "Kansas",
    "KY": "Kentucky",
    "LA": "Louisiana",
    "ME": "Maine",
    "MD": "Maryland",
    "MA": "Massachusetts",
    "MI": "Michigan",
    "MN": "Minnesota",
    "MS": "Mississippi",
    "MO": "Missouri",
    "MT": "Montana",
    "NE": "Nebraska",
    "NV": "Nevada",
    "NH": "New Hampshire",
    "NJ": "New Jersey",
    "NM": "New Mexico",
    "NY": "New York",
    "NC": "North Carolina",
    "ND": "North Dakota",
    "OH": "Ohio",
    "OK": "Oklahoma",
    "OR": "Oregon",
    "PA": "Pennsylvania",
    "RI": "Rhode Island",
    "SC": "South Carolina",
    "SD": "South Dakota",
    "TN": "Tennessee",
    "TX": "Texas",
    "UT": "Utah",
    "VT": "Vermont",
    "VA": "Virginia",
    "WA": "Washington",
    "WV": "West Virginia",
    "WI": "Wisconsin",
    "WY": "Wyoming",
}

MUST_HAVE_COUNTRIES = {
    "FRA", "USA", "CHN", "RUS", "BRA", "AUS", "CAN", "IND", "MEX", "JPN",
    "DEU", "GBR", "ITA", "ESP", "ZAF", "EGY", "ARG", "GRL", "NZL", "FJI",
    "ISL", "NOR", "SWE", "CHL", "IDN", "PHL", "GRC", "TUR", "KOR", "VNM",
    "THA", "UKR", "POL", "MAR", "NGA", "KEN", "PER", "COL", "PAK", "ETH",
    "DZA", "SAU", "IRN", "KAZ", "MNG", "CUB", "IRL", "PRT", "NLD", "BEL",
    "CHE", "AUT", "CZE", "HUN", "ROU", "FIN", "DNK", "TWN", "CYP", "SOM",
    "MYS", "MDG",
}


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        print(f"cached {dest.name}")
        return
    print(f"downloading {url}")
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "fathom-shape-pipeline/1.0"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        dest.write_bytes(response.read())
    print(f"wrote {dest} ({dest.stat().st_size} bytes)")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def prop(properties: dict, *keys: str):
    lookup = {str(key).lower(): value for key, value in properties.items()}
    for key in keys:
        if key.lower() in lookup:
            return lookup[key.lower()]
    return None


def normalize_lon(lon: float) -> float:
    return (lon + 180.0) % 360.0 - 180.0


def largest_gap_cut(lons: list[float]) -> float:
    # Keep full precision. Rounding the cut up into the cluster wraps the
    # westernmost vertices by a full turn and stretches the shape across 360°.
    normed = sorted({normalize_lon(lon) for lon in lons})
    if not normed:
        return 0.0
    if len(normed) == 1:
        return normed[0]
    max_gap = -1.0
    cut = normed[0]
    for index, start in enumerate(normed):
        end = normed[(index + 1) % len(normed)]
        gap = (end - start) % 360.0
        if gap == 0:
            gap = 360.0
        if gap > max_gap:
            max_gap = gap
            cut = end
    return cut


def collapse_wrap(ring: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Pull back vertices that landed a full turn away from the rest of a ring."""
    lons = [lon for lon, _ in ring]
    if max(lons) - min(lons) <= 180:
        return ring
    order = sorted(range(len(ring)), key=lambda index: ring[index][0])
    max_gap = -1.0
    gap_end = None
    for index in range(len(order) - 1):
        left = ring[order[index]][0]
        right = ring[order[index + 1]][0]
        gap = right - left
        if gap > max_gap:
            max_gap = gap
            gap_end = right
    if max_gap <= 180 or gap_end is None:
        return ring
    return [(lon - 360.0, lat) if lon >= gap_end - 1e-8 else (lon, lat) for lon, lat in ring]


def rebase(lon: float, cut: float) -> float:
    normalized = normalize_lon(lon)
    return cut + (normalized - cut) % 360.0


def ring_area_km2(ring: list[tuple[float, float]]) -> float:
    """Spherical polygon area. Longitudes must already be unwrapped."""
    if len(ring) < 3:
        return 0.0
    points = ring
    if points[0] != points[-1]:
        points = points + [points[0]]
    total = 0.0
    for (lon1, lat1), (lon2, lat2) in zip(points, points[1:]):
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        d_lam = math.radians(lon2 - lon1)
        total += d_lam * (math.sin(phi1) + math.sin(phi2))
    return abs(total) * (EARTH_RADIUS_KM ** 2) / 2.0


def bbox_of(ring: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    lons = [lon for lon, _ in ring]
    lats = [lat for _, lat in ring]
    return min(lons), min(lats), max(lons), max(lats)


def combine_bbox(boxes: list[tuple[float, float, float, float]]) -> tuple[float, float, float, float]:
    return (
        min(box[0] for box in boxes),
        min(box[1] for box in boxes),
        max(box[2] for box in boxes),
        max(box[3] for box in boxes),
    )


def gap_km(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    if a[2] < b[0]:
        d_lon = b[0] - a[2]
    elif b[2] < a[0]:
        d_lon = a[0] - b[2]
    else:
        d_lon = 0.0
    if a[3] < b[1]:
        d_lat = b[1] - a[3]
    elif b[3] < a[1]:
        d_lat = a[1] - b[3]
    else:
        d_lat = 0.0
    if d_lon == 0.0 and d_lat == 0.0:
        return 0.0
    lat = ((a[1] + a[3]) / 2.0 + (b[1] + b[3]) / 2.0) / 2.0
    dx = d_lon * 111.32 * math.cos(math.radians(lat))
    dy = d_lat * 110.57
    return math.hypot(dx, dy)


class UnionFind:
    def __init__(self, size: int) -> None:
        self.parent = list(range(size))
        self.rank = [0] * size

    def find(self, item: int) -> int:
        while self.parent[item] != item:
            self.parent[item] = self.parent[self.parent[item]]
            item = self.parent[item]
        return item

    def union(self, left: int, right: int) -> None:
        left_root = self.find(left)
        right_root = self.find(right)
        if left_root == right_root:
            return
        if self.rank[left_root] < self.rank[right_root]:
            self.parent[left_root] = right_root
        elif self.rank[left_root] > self.rank[right_root]:
            self.parent[right_root] = left_root
        else:
            self.parent[right_root] = left_root
            self.rank[left_root] += 1


def iter_polygons(geometry: dict) -> list[list[list[list[float]]]]:
    if not geometry:
        return []
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates") or []
    if kind == "Polygon":
        return [coordinates]
    if kind == "MultiPolygon":
        return list(coordinates)
    if kind == "GeometryCollection":
        polygons = []
        for piece in geometry.get("geometries") or []:
            polygons.extend(iter_polygons(piece))
        return polygons
    return []


def clean_ring(raw: list) -> list[tuple[float, float]] | None:
    points: list[tuple[float, float]] = []
    for point in raw:
        if not isinstance(point, (list, tuple)) or len(point) < 2:
            continue
        lon = float(point[0])
        lat = float(point[1])
        if not math.isfinite(lon) or not math.isfinite(lat):
            continue
        if lat < -90 or lat > 90:
            continue
        if points and abs(points[-1][0] - lon) < 1e-10 and abs(points[-1][1] - lat) < 1e-10:
            continue
        points.append((lon, lat))
    if len(points) >= 2 and points[0] == points[-1]:
        points = points[:-1]
    if len(points) < 3:
        return None
    return points


def load_polygons(geometry: dict, cut: float | None = None) -> list[dict]:
    """Return polygon dicts in unwrapped longitude space."""
    raw_polygons = []
    all_lons: list[float] = []
    for polygon in iter_polygons(geometry):
        rings = []
        for raw_ring in polygon:
            ring = clean_ring(raw_ring)
            if ring is None:
                continue
            rings.append(ring)
            all_lons.extend(lon for lon, _ in ring)
        if rings:
            raw_polygons.append(rings)
    if not raw_polygons:
        return []
    if cut is None:
        cut = largest_gap_cut(all_lons)
    prepared = []
    for rings in raw_polygons:
        unwrapped = [collapse_wrap([(rebase(lon, cut), lat) for lon, lat in ring]) for ring in rings]
        exterior = unwrapped[0]
        holes = unwrapped[1:]
        box = bbox_of(exterior)
        # A ring that still covers more than a hemisphere of longitude is a
        # broken antimeridian edge, not a landmass we can draw.
        if box[2] - box[0] > 220:
            continue
        area = ring_area_km2(exterior) - sum(ring_area_km2(hole) for hole in holes)
        if area < 1.0:
            continue
        prepared.append({
            "rings": unwrapped,
            "area": area,
            "bbox": bbox_of(exterior),
        })
    return prepared


def cluster_indices(polygons: list[dict], indexes: list[int], gap_limit: float) -> list[list[int]]:
    if not indexes:
        return []
    finder = UnionFind(len(indexes))
    for left in range(len(indexes)):
        for right in range(left + 1, len(indexes)):
            if gap_km(polygons[indexes[left]]["bbox"], polygons[indexes[right]]["bbox"]) <= gap_limit:
                finder.union(left, right)
    groups: dict[int, list[int]] = defaultdict(list)
    for local, index in enumerate(indexes):
        groups[finder.find(local)].append(index)
    return list(groups.values())


def cluster_area(polygons: list[dict], indexes: list[int]) -> float:
    return sum(polygons[index]["area"] for index in indexes)


def cluster_bbox(polygons: list[dict], indexes: list[int]) -> tuple[float, float, float, float]:
    return combine_bbox([polygons[index]["bbox"] for index in indexes])


def select_polygons(polygons: list[dict], wide: bool) -> list[dict]:
    if not polygons:
        return []
    bridge = WIDE_BRIDGE_GAP_KM if wide else BRIDGE_GAP_KM
    major_indexes = [index for index, polygon in enumerate(polygons) if polygon["area"] >= MAJOR_MIN_KM2]
    minor_indexes = [index for index in range(len(polygons)) if index not in set(major_indexes)]
    allow_secondary = True
    if not major_indexes:
        major_indexes = list(range(len(polygons)))
        minor_indexes = []
        allow_secondary = False

    groups = cluster_indices(polygons, major_indexes, bridge)
    groups.sort(key=lambda group: cluster_area(polygons, group), reverse=True)
    main = groups[0]
    main_area = cluster_area(polygons, main)
    main_box = cluster_bbox(polygons, main)
    chosen = set(main)
    for group in groups[1:]:
        if not allow_secondary:
            break
        area = cluster_area(polygons, group)
        if area >= main_area * SECONDARY_AREA_RATIO:
            chosen.update(group)
            continue
        # A sizable neighbor of the main landmass (Corsica-scale and up is
        # already inside the bridge; this catches a near miss).
        if area >= main_area * 0.08 and gap_km(main_box, cluster_bbox(polygons, group)) <= bridge:
            chosen.update(group)

    # Minors may chain (Maui reaches Oahu, Oahu reaches Kauai) but they are
    # never allowed to bridge two major landmasses together.
    remaining = set(minor_indexes)
    while remaining:
        kept_boxes = [polygons[index]["bbox"] for index in chosen]
        attached = [
            index for index in remaining
            if any(gap_km(polygons[index]["bbox"], box) <= ATTACH_GAP_KM for box in kept_boxes)
        ]
        if not attached:
            break
        chosen.update(attached)
        remaining.difference_update(attached)
    selected = [polygons[index] for index in sorted(chosen)]
    return selected


def laea_forward(lon: float, lat: float, lon0: float, lat0: float) -> tuple[float, float]:
    lam = math.radians(lon)
    phi = math.radians(lat)
    lam0 = math.radians(lon0)
    phi0 = math.radians(lat0)
    d_lam = lam - lam0
    cos_phi = math.cos(phi)
    sin_phi = math.sin(phi)
    cos_c = math.sin(phi0) * sin_phi + math.cos(phi0) * cos_phi * math.cos(d_lam)
    cos_c = max(-1.0, min(1.0, cos_c))
    denom = 1.0 + cos_c
    if denom < 1e-8:
        raise ValueError("point is opposite the projection center")
    k = math.sqrt(2.0 / denom)
    x = EARTH_RADIUS_M * k * cos_phi * math.sin(d_lam)
    y = EARTH_RADIUS_M * k * (
        math.cos(phi0) * sin_phi - math.sin(phi0) * cos_phi * math.cos(d_lam)
    )
    return x, y


def laea_inverse(x: float, y: float, lon0: float, lat0: float) -> tuple[float, float]:
    lam0 = math.radians(lon0)
    phi0 = math.radians(lat0)
    rho = math.hypot(x, y)
    if rho < 1e-8:
        return lon0, lat0
    c = 2.0 * math.asin(min(1.0, rho / (2.0 * EARTH_RADIUS_M)))
    sin_c = math.sin(c)
    cos_c = math.cos(c)
    phi = math.asin(max(-1.0, min(1.0, cos_c * math.sin(phi0) + y * sin_c * math.cos(phi0) / rho)))
    lam = lam0 + math.atan2(
        x * sin_c,
        rho * math.cos(phi0) * cos_c - y * math.sin(phi0) * sin_c,
    )
    return math.degrees(lam), math.degrees(phi)


def project_rings(
    rings: list[list[tuple[float, float]]],
    lon0: float,
    lat0: float,
) -> list[list[tuple[float, float]]]:
    projected = []
    for ring in rings:
        points = []
        for lon, lat in ring:
            try:
                points.append(laea_forward(lon, lat, lon0, lat0))
            except ValueError:
                continue
        if len(points) >= 3:
            projected.append(points)
    return projected


def signed_area_centroid(ring: list[tuple[float, float]]) -> tuple[float, float, float]:
    points = ring
    if points[0] != points[-1]:
        points = points + [points[0]]
    cross_sum = 0.0
    cx = 0.0
    cy = 0.0
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        cross = x1 * y2 - x2 * y1
        cross_sum += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    area = cross_sum / 2.0
    if abs(area) < 1e-6:
        return 0.0, 0.0, 0.0
    return area, cx / (6.0 * area), cy / (6.0 * area)


def projected_centroid(polygons: list[list[list[tuple[float, float]]]]) -> tuple[float, float]:
    total_area = 0.0
    sum_x = 0.0
    sum_y = 0.0
    for rings in polygons:
        if not rings:
            continue
        for ring in rings:
            area, cx, cy = signed_area_centroid(ring)
            total_area += area
            sum_x += cx * area
            sum_y += cy * area
    if abs(total_area) < 1e-6:
        xs = [point[0] for rings in polygons for ring in rings for point in ring]
        ys = [point[1] for rings in polygons for ring in rings for point in ring]
        return sum(xs) / len(xs), sum(ys) / len(ys)
    return sum_x / total_area, sum_y / total_area


def perp_distance(point, start, end) -> float:
    px, py = point
    x1, y1 = start
    x2, y2 = end
    dx = x2 - x1
    dy = y2 - y1
    length = math.hypot(dx, dy)
    if length < 1e-9:
        return math.hypot(px - x1, py - y1)
    return abs(dy * px - dx * py + x2 * y1 - y2 * x1) / length


def rdp(points: list[tuple[float, float]], epsilon: float) -> list[tuple[float, float]]:
    count = len(points)
    if count < 3:
        return points
    keep = [False] * count
    keep[0] = True
    keep[-1] = True
    stack = [(0, count - 1)]
    while stack:
        start, end = stack.pop()
        max_distance = 0.0
        index = None
        for cursor in range(start + 1, end):
            distance = perp_distance(points[cursor], points[start], points[end])
            if distance > max_distance:
                max_distance = distance
                index = cursor
        if index is not None and max_distance > epsilon:
            keep[index] = True
            stack.append((start, index))
            stack.append((index, end))
    return [point for point, flagged in zip(points, keep) if flagged]


def count_points(polygons: list[list[list[tuple[float, float]]]]) -> int:
    return sum(len(ring) for rings in polygons for ring in rings)


def simplify_polygons(
    polygons: list[list[list[tuple[float, float]]]],
    budget: int,
) -> list[list[list[tuple[float, float]]]]:
    original = count_points(polygons)
    if original == 0:
        return []
    xs = [point[0] for rings in polygons for ring in rings for point in ring]
    ys = [point[1] for rings in polygons for ring in rings for point in ring]
    diagonal = math.hypot(max(xs) - min(xs), max(ys) - min(ys))
    min_eps = max(1_200.0, diagonal * 0.0025)
    max_eps = max(min_eps * 2, min(80_000.0, diagonal * 0.08))

    def apply(epsilon: float) -> list[list[list[tuple[float, float]]]]:
        simplified = []
        for rings in polygons:
            next_rings = []
            for ring_index, ring in enumerate(rings):
                reduced = rdp(ring, epsilon)
                if len(reduced) >= 3:
                    # Keep a hole only when it still has area after simplification.
                    if ring_index == 0 or abs(signed_area_centroid(reduced)[0]) > 1e6:
                        next_rings.append(reduced)
            if next_rings and len(next_rings[0]) >= 3:
                simplified.append(next_rings)
        return simplified

    if original <= budget:
        return apply(min_eps)
    best = apply(max_eps)
    low, high = min_eps, max_eps
    for _ in range(18):
        mid = (low + high) / 2.0
        candidate = apply(mid)
        if count_points(candidate) > budget:
            low = mid
        else:
            best = candidate
            high = mid
    return best


def normalize_pixels(polygons: list[list[list[tuple[float, float]]]]) -> tuple[int, int, list[list[list[int]]]]:
    xs = [point[0] for rings in polygons for ring in rings for point in ring]
    ys = [point[1] for rings in polygons for ring in rings for point in ring]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    span_x = max(max_x - min_x, 1.0)
    span_y = max(max_y - min_y, 1.0)
    long_span = max(span_x, span_y)
    scale = LONG_SIDE / long_span
    width = max(1, int(round(span_x * scale)))
    height = max(1, int(round(span_y * scale)))
    encoded = []
    for rings in polygons:
        encoded_rings = []
        for ring in rings:
            flat: list[int] = []
            last = None
            for x, y in ring:
                px = int(round((x - min_x) * scale))
                # Projected y grows north; pixel y grows south.
                py = int(round((max_y - y) * scale))
                px = max(0, min(width, px))
                py = max(0, min(height, py))
                if last == (px, py):
                    continue
                flat.extend((px, py))
                last = (px, py)
            if len(flat) >= 6:
                encoded_rings.append(flat)
        if encoded_rings:
            encoded.append(encoded_rings)
    return width, height, encoded


def preliminary_center(polygons: list[dict]) -> tuple[float, float]:
    box = combine_bbox([polygon["bbox"] for polygon in polygons])
    return (box[0] + box[2]) / 2.0, (box[1] + box[3]) / 2.0


def build_geometry(polygons: list[dict], point_budget: int) -> dict | None:
    if not polygons:
        return None
    lon0, lat0 = preliminary_center(polygons)
    first_pass = []
    largest_area = -1.0
    largest_index = 0
    for index, polygon in enumerate(polygons):
        projected = project_rings(polygon["rings"], lon0, lat0)
        if not projected:
            continue
        first_pass.append(projected)
        if polygon["area"] > largest_area:
            largest_area = polygon["area"]
            largest_index = len(first_pass) - 1
    if not first_pass:
        return None
    total_area = sum(polygon["area"] for polygon in polygons)
    main_share = polygons[max(range(len(polygons)), key=lambda item: polygons[item]["area"])]["area"] / total_area
    if main_share >= 0.65 and largest_index < len(first_pass):
        cx, cy = projected_centroid([first_pass[largest_index]])
    else:
        cx, cy = projected_centroid(first_pass)
    center_lon, center_lat = laea_inverse(cx, cy, lon0, lat0)
    center_lon = normalize_lon(center_lon)
    reprojected = []
    for polygon in polygons:
        projected = project_rings(polygon["rings"], center_lon, center_lat)
        if projected:
            reprojected.append(projected)
    if not reprojected:
        return None
    simplified = simplify_polygons(reprojected, point_budget)
    if not simplified:
        return None
    width, height, encoded = normalize_pixels(simplified)
    if not encoded or width < 2 or height < 2:
        return None
    displayed_box = combine_bbox([polygon["bbox"] for polygon in polygons])
    return {
        "lat": round(center_lat, 5),
        "lon": round(center_lon, 5),
        "w": width,
        "h": height,
        "polygons": encoded,
        "span": (displayed_box[2] - displayed_box[0], displayed_box[3] - displayed_box[1]),
        "area": round(total_area, 1),
    }


def abbreviated(name: str) -> bool:
    if not name:
        return True
    if "." in name:
        return True
    lowered = name.lower()
    if lowered.endswith(" rep") or " rep." in lowered:
        return True
    return False


def normalize_name(value: str) -> str:
    import unicodedata

    text = value.strip().lower().replace("ø", "o").replace("ł", "l").replace("đ", "d")
    text = text.replace("æ", "ae").replace("œ", "oe").replace("ß", "ss")
    text = unicodedata.normalize("NFD", text)
    text = "".join(char for char in text if unicodedata.category(char) != "Mn")
    cleaned = []
    for char in text:
        if char.isalnum():
            cleaned.append(char)
        elif char in {"'", "’", "`"}:
            continue
        else:
            cleaned.append(" ")
    words = "".join(cleaned).split()
    if words and words[0] == "the":
        words = words[1:]
    words = ["saint" if word in {"st", "ste"} else word for word in words]
    return " ".join(words)


def choose_display_name(properties: dict, iso: str) -> str:
    if iso in DISPLAY_OVERRIDES:
        return DISPLAY_OVERRIDES[iso]
    candidates = [
        prop(properties, "NAME"),
        prop(properties, "NAME_LONG"),
        prop(properties, "ADMIN"),
        prop(properties, "NAME_EN"),
    ]
    for candidate in candidates:
        if isinstance(candidate, str) and candidate.strip() and not abbreviated(candidate):
            return candidate.strip()
    for candidate in candidates:
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()
    return iso


def collect_aliases(properties: dict, iso: str, display: str) -> list[str]:
    found = []
    for key in ("NAME", "NAME_LONG", "ADMIN", "NAME_EN", "FORMAL_EN", "NAME_SORT", "GEOUNIT", "BRK_NAME"):
        value = prop(properties, key)
        if isinstance(value, str) and value.strip():
            found.append(value.strip())
    found.extend(EXTRA_ALIASES.get(iso, []))
    display_key = normalize_name(display)
    unique = []
    seen = {display_key}
    for alias in found:
        if abbreviated(alias) and alias not in EXTRA_ALIASES.get(iso, []):
            continue
        # Natural Earth stores a few reversed catalog labels ("Bahamas, The").
        if "," in alias or "(" in alias:
            continue
        key = normalize_name(alias)
        if not key or key in seen:
            continue
        if any(len(word) == 1 for word in key.split()):
            continue
        seen.add(key)
        unique.append(alias)
    unique.sort(key=lambda item: normalize_name(item))
    return unique


def feature_id(properties: dict) -> str | None:
    iso = prop(properties, "ISO_A3")
    adm = prop(properties, "ADM0_A3")
    if isinstance(iso, str) and len(iso) == 3 and iso != "-99":
        return iso
    if isinstance(adm, str) and len(adm) == 3 and adm != "-99":
        return adm
    return None


def adm_code(properties: dict) -> str | None:
    adm = prop(properties, "ADM0_A3")
    if isinstance(adm, str) and adm not in {"", "-99"}:
        return adm
    return feature_id(properties)


def prepare_countries(path: Path) -> list[dict]:
    collection = json.loads(path.read_text())
    by_adm: dict[str, dict] = {}
    for feature in collection["features"]:
        properties = feature["properties"]
        code = adm_code(properties)
        if not code:
            continue
        by_adm[code] = feature

    for source, target in MERGE_ADM.items():
        extra = by_adm.get(source)
        parent = by_adm.get(target)
        if not extra or not parent:
            continue
        parent_polys = iter_polygons(parent["geometry"])
        extra_polys = iter_polygons(extra["geometry"])
        parent["geometry"] = {"type": "MultiPolygon", "coordinates": parent_polys + extra_polys}

    regions = []
    skipped = []
    for feature in collection["features"]:
        properties = feature["properties"]
        code = adm_code(properties)
        if not code or code in EXCLUDE_ADM or code in MERGE_ADM:
            continue
        kind = prop(properties, "TYPE") or ""
        if kind not in INCLUDE_TYPES and code not in EXTRA_INCLUDE_ADM:
            continue
        iso = feature_id(properties)
        if not iso:
            skipped.append((code, "no id"))
            continue
        polygons = load_polygons(feature["geometry"])
        selected = select_polygons(polygons, wide=code in WIDE_BRIDGE_ADM or iso in WIDE_BRIDGE_ADM)
        geometry = build_geometry(selected, point_budget=360)
        if geometry is None:
            skipped.append((iso, "empty geometry"))
            continue
        if geometry["area"] < MIN_AREA_KM2:
            skipped.append((iso, f"small {geometry['area']:.0f} km2"))
            continue
        name = choose_display_name(properties, iso)
        region = {
            "id": iso,
            "name": name,
            "aliases": collect_aliases(properties, iso, name),
            "lat": geometry["lat"],
            "lon": geometry["lon"],
            "w": geometry["w"],
            "h": geometry["h"],
            "polygons": geometry["polygons"],
        }
        region["_span"] = geometry["span"]
        region["_area"] = geometry["area"]
        regions.append(region)

    if skipped:
        print("skipped countries:")
        for iso, reason in skipped:
            print(f"  {iso}: {reason}")
    return regions


def prepare_states(path: Path) -> list[dict]:
    collection = json.loads(path.read_text())
    found = {}
    for feature in collection["features"]:
        properties = feature["properties"]
        if prop(properties, "iso_a2") != "US" and prop(properties, "adm0_a3") != "USA":
            continue
        postal = prop(properties, "postal")
        name = prop(properties, "name")
        if postal not in US_STATES:
            continue
        if name != US_STATES[postal]:
            raise SystemExit(f"{postal} is named {name!r}, expected {US_STATES[postal]!r}")
        polygons = load_polygons(feature["geometry"])
        # Alaska and Hawaii are their own outlines; a slightly wider bridge
        # keeps each island chain together without pulling in noise.
        wide = postal in {"AK", "HI"}
        selected = select_polygons(polygons, wide=wide)
        geometry = build_geometry(selected, point_budget=420 if postal in {"AK", "CA", "FL", "MI", "TX"} else 280)
        if geometry is None:
            raise SystemExit(f"no geometry for {name}")
        found[postal] = {
            "id": postal,
            "name": name,
            "aliases": [],
            "lat": geometry["lat"],
            "lon": geometry["lon"],
            "w": geometry["w"],
            "h": geometry["h"],
            "polygons": geometry["polygons"],
            "_span": geometry["span"],
            "_area": geometry["area"],
        }
    missing = sorted(set(US_STATES) - set(found))
    if missing:
        raise SystemExit(f"missing states: {missing}")
    return [found[postal] for postal in sorted(found)]


def assert_unique_names(regions: list[dict], label: str) -> None:
    owners: dict[str, str] = {}
    for region in regions:
        keys = [normalize_name(region["name"])] + [normalize_name(alias) for alias in region["aliases"]]
        for key in keys:
            other = owners.get(key)
            if other and other != region["id"]:
                if key == normalize_name(region["name"]):
                    raise SystemExit(f"{label} name collision {key!r} between {other} and {region['id']}")
                print(f"drop alias {key!r} from {region['id']} (owned by {other})")
                region["aliases"] = [
                    alias for alias in region["aliases"] if normalize_name(alias) != key
                ]
            else:
                owners[key] = region["id"]


def check_regions(countries: list[dict], states: list[dict]) -> None:
    ids = {region["id"] for region in countries}
    missing = sorted(MUST_HAVE_COUNTRIES - ids)
    if missing:
        raise SystemExit(f"missing required countries: {missing}")
    if not (160 <= len(countries) <= 210):
        raise SystemExit(f"unexpected country count: {len(countries)}")
    if len(states) != 50:
        raise SystemExit(f"expected 50 states, found {len(states)}")

    def aspect(region: dict) -> float:
        return max(region["w"], region["h"]) / max(1, min(region["w"], region["h"]))

    problems = []
    for region in countries + states:
        if aspect(region) > 18:
            problems.append(f"{region['id']} aspect {aspect(region):.1f}")
        span_lon, span_lat = region["_span"]
        if span_lon > 200 or span_lat > 80:
            problems.append(f"{region['id']} span lon {span_lon:.1f} lat {span_lat:.1f}")
        for polygon in region["polygons"]:
            for ring in polygon:
                if len(ring) < 6 or len(ring) % 2:
                    problems.append(f"{region['id']} bad ring")
                    break
                for index in range(0, len(ring), 2):
                    if not (0 <= ring[index] <= region["w"] and 0 <= ring[index + 1] <= region["h"]):
                        problems.append(f"{region['id']} point outside box")
                        break
    expectations = {
        "FRA": lambda r: 41 <= r["lat"] <= 51 and -6 <= r["lon"] <= 10,
        "USA": lambda r: 30 <= r["lat"] <= 50 and -125 <= r["lon"] <= -70,
        "RUS": lambda r: 50 <= r["lat"] <= 75 and 40 <= r["lon"] <= 140 and aspect(r) < 8,
        "FJI": lambda r: -22 <= r["lat"] <= -12 and abs(r["lon"]) > 170 and aspect(r) < 5,
        "AUS": lambda r: -44 <= r["lat"] <= -10 and 112 <= r["lon"] <= 155,
        "BRA": lambda r: -25 <= r["lat"] <= 5 and -75 <= r["lon"] <= -35,
        "ZAF": lambda r: -35 <= r["lat"] <= -22 and 16 <= r["lon"] <= 33,
        "JPN": lambda r: 30 <= r["lat"] <= 46 and 128 <= r["lon"] <= 146,
        "GBR": lambda r: 50 <= r["lat"] <= 60 and -9 <= r["lon"] <= 2,
        "ITA": lambda r: 36 <= r["lat"] <= 47 and 6 <= r["lon"] <= 19,
        "ESP": lambda r: 36 <= r["lat"] <= 44 and -10 <= r["lon"] <= 5,
        "NOR": lambda r: 58 <= r["lat"] <= 72 and 4 <= r["lon"] <= 32,
        "CHL": lambda r: -50 <= r["lat"] <= -20 and -76 <= r["lon"] <= -66 and r["h"] > r["w"],
        "IDN": lambda r: -11 <= r["lat"] <= 6 and 95 <= r["lon"] <= 141,
        "NZL": lambda r: -48 <= r["lat"] <= -34 and 165 <= r["lon"] <= 179,
        "GRL": lambda r: 60 <= r["lat"] <= 84 and -75 <= r["lon"] <= -10,
        "CYP": lambda r: 34.4 <= r["lat"] <= 35.8 and 32 <= r["lon"] <= 35,
        "SOM": lambda r: -2 <= r["lat"] <= 12 and 40 <= r["lon"] <= 52,
        "MYS": lambda r: 0 <= r["lat"] <= 8 and 99 <= r["lon"] <= 120,
    }
    by_id = {region["id"]: region for region in countries}
    for iso, rule in expectations.items():
        region = by_id[iso]
        if not rule(region):
            problems.append(
                f"{iso} centroid {region['lat']:.2f},{region['lon']:.2f} "
                f"box {region['w']}x{region['h']} span {region['_span']}"
            )
    state_rules = {
        "AK": lambda r: 55 <= r["lat"] <= 72 and -170 <= r["lon"] <= -130 and aspect(r) < 8,
        "HI": lambda r: 18 <= r["lat"] <= 23 and -161 <= r["lon"] <= -154,
        "FL": lambda r: 25 <= r["lat"] <= 31 and -88 <= r["lon"] <= -79,
        "CA": lambda r: 33 <= r["lat"] <= 42 and -125 <= r["lon"] <= -114,
        "MI": lambda r: 41 <= r["lat"] <= 48 and -91 <= r["lon"] <= -82,
        "NY": lambda r: 40 <= r["lat"] <= 45 and -80 <= r["lon"] <= -72,
    }
    by_state = {region["id"]: region for region in states}
    for postal, rule in state_rules.items():
        region = by_state[postal]
        if not rule(region):
            problems.append(
                f"{postal} centroid {region['lat']:.2f},{region['lon']:.2f} "
                f"box {region['w']}x{region['h']} span {region['_span']}"
            )
    if problems:
        print("GEOMETRY CHECKS FAILED")
        for problem in problems:
            print(" ", problem)
        raise SystemExit(1)


def strip_private(regions: list[dict]) -> list[dict]:
    cleaned = []
    for region in regions:
        cleaned.append({key: value for key, value in region.items() if not key.startswith("_")})
    cleaned.sort(key=lambda region: region["id"])
    return cleaned


def self_check() -> None:
    cut = largest_gap_cut([179.0, -179.0, 178.0, -178.5])
    rebased = sorted(rebase(lon, cut) for lon in (179.0, -179.0, 178.0, -178.5))
    if max(rebased) - min(rebased) > 5:
        raise SystemExit(f"antimeridian unwrap failed: {rebased}")
    samples = [(2.35, 48.86), (-149.9, 61.2), (179.2, -16.6), (-179.4, -16.8), (133.0, -25.0)]
    for lon, lat in samples:
        x, y = laea_forward(lon, lat, 10.0, 20.0)
        lon2, lat2 = laea_inverse(x, y, 10.0, 20.0)
        if abs(lat - lat2) > 1e-6 or abs(normalize_lon(lon - lon2)) > 1e-6:
            raise SystemExit(f"LAEA roundtrip failed for {lon},{lat} -> {lon2},{lat2}")
    area = ring_area_km2([(0, 0), (1, 0), (1, 1), (0, 1)])
    if not 10_000 <= area <= 14_000:
        raise SystemExit(f"area formula looks wrong: {area}")
    if normalize_name("Côte d'Ivoire") != "cote divoire":
        raise SystemExit("normalize failed for Cote d'Ivoire")
    if normalize_name("The Bahamas") != "bahamas":
        raise SystemExit("normalize failed for The Bahamas")
    if normalize_name("St. Kitts and Nevis") != "saint kitts and nevis":
        raise SystemExit("normalize failed for Saint Kitts")


def render_previews(document: dict, directory: Path) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Pillow is not installed; skipping previews")
        return
    directory.mkdir(parents=True, exist_ok=True)
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    font = ImageFont.truetype(font_path, 14) if Path(font_path).exists() else ImageFont.load_default()
    small = ImageFont.truetype(font_path, 11) if Path(font_path).exists() else font

    def draw_region(region: dict, size: int, label: str | None) -> Image.Image:
        canvas = Image.new("RGB", (size, size if label is None else size + 22), (244, 241, 234))
        draw = ImageDraw.Draw(canvas)
        pad = 10
        avail = size - pad * 2
        scale = min(avail / region["w"], avail / region["h"])
        drawn_w = region["w"] * scale
        drawn_h = region["h"] * scale
        origin_x = pad + (avail - drawn_w) / 2
        origin_y = pad + (avail - drawn_h) / 2
        ink = (26, 46, 42)
        for polygon in region["polygons"]:
            if not polygon:
                continue
            exterior = polygon[0]
            points = [
                (origin_x + exterior[index] * scale, origin_y + exterior[index + 1] * scale)
                for index in range(0, len(exterior), 2)
            ]
            draw.polygon(points, fill=ink)
            for hole in polygon[1:]:
                hole_points = [
                    (origin_x + hole[index] * scale, origin_y + hole[index + 1] * scale)
                    for index in range(0, len(hole), 2)
                ]
                if len(hole_points) >= 3:
                    draw.polygon(hole_points, fill=(244, 241, 234))
        if label:
            draw.text((6, size + 3), label, fill=(40, 36, 32), font=small)
        return canvas

    def sheet(regions: list[dict], columns: int, cell: int, name: str) -> None:
        label_h = 22
        rows = math.ceil(len(regions) / columns)
        image = Image.new("RGB", (columns * cell, rows * (cell + label_h)), (255, 255, 255))
        for index, region in enumerate(regions):
            tile = draw_region(region, cell, f"{region['id']} {region['name']}")
            x = (index % columns) * cell
            y = (index // columns) * (cell + label_h)
            image.paste(tile, (x, y))
        path = directory / name
        image.save(path, optimize=True)
        print(f"preview {path}")

    countries = document["countries"]
    states = document["states"]
    sheet(countries, 12, 150, "countries.png")
    sheet(states, 10, 160, "states.png")
    focus_ids = [
        "USA", "FRA", "RUS", "FJI", "NOR", "ESP", "IDN", "MYS",
        "GBR", "AUS", "CHL", "NZL", "JPN", "GRC", "PHL", "CAN",
        "ZAF", "BRA", "ITA", "CHN", "GRL", "CYP", "SOM", "IND",
    ]
    by_country = {region["id"]: region for region in countries}
    focus = [by_country[iso] for iso in focus_ids if iso in by_country]
    sheet(focus, 4, 280, "focus-countries.png")
    focus_states = ["AK", "HI", "FL", "MI", "CA", "NY", "LA", "MD", "WA", "TX", "ME", "NC"]
    by_state = {region["id"]: region for region in states}
    sheet([by_state[postal] for postal in focus_states], 4, 280, "focus-states.png")


def build(cache: Path, out: Path, preview_dir: Path | None) -> None:
    self_check()
    countries_path = cache / "ne_50m_admin_0_countries.geojson"
    states_path = cache / "ne_50m_admin_1_states_provinces.geojson"
    download(COUNTRIES_URL, countries_path)
    download(STATES_URL, states_path)
    countries = prepare_countries(countries_path)
    states = prepare_states(states_path)
    assert_unique_names(countries, "country")
    assert_unique_names(states, "state")
    check_regions(countries, states)
    print(f"countries {len(countries)}  states {len(states)}")
    print("sample centroids:")
    watch = ["FRA", "USA", "RUS", "FJI", "NOR", "ESP", "IDN", "MYS", "GBR", "AUS", "CHL", "NZL", "JPN", "CYP", "SOM", "GRL"]
    by_id = {region["id"]: region for region in countries}
    for iso in watch:
        region = by_id[iso]
        print(
            f"  {iso:4} {region['name']:28} {region['lat']:7.2f},{region['lon']:8.2f}  "
            f"{region['w']}x{region['h']}  span {region['_span'][0]:.1f}° x {region['_span'][1]:.1f}°"
        )
    print("states of interest:")
    by_state = {region["id"]: region for region in states}
    for postal in ["AK", "HI", "FL", "MI", "CA", "NY", "RI", "CO"]:
        region = by_state[postal]
        print(
            f"  {postal:4} {region['name']:16} {region['lat']:7.2f},{region['lon']:8.2f}  "
            f"{region['w']}x{region['h']}  span {region['_span'][0]:.1f}° x {region['_span'][1]:.1f}°"
        )
    document = {
        "algorithm": "fathom-shapes-v1",
        "attribution": "Made with Natural Earth. Free vector and raster map data at naturalearthdata.com.",
        "license": "Public domain",
        "projection": "Per-shape spherical Lambert azimuthal equal-area, centered on the outline used for distance.",
        "coordinates": "Integer pixel pairs in each ring, x then y, y growing south, inside a w by h box.",
        "sources": [
            {"url": COUNTRIES_URL, "sha256": sha256_file(countries_path), "bytes": countries_path.stat().st_size},
            {"url": STATES_URL, "sha256": sha256_file(states_path), "bytes": states_path.stat().st_size},
        ],
        "countries": strip_private(countries),
        "states": strip_private(states),
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":"))
    out.write_text(encoded + "\n")
    print(f"wrote {out} ({out.stat().st_size} bytes)")
    if preview_dir:
        render_previews(document, preview_dir)


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare Fathom outline geometry from Natural Earth.")
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--preview-dir", type=Path, default=None)
    args = parser.parse_args()
    try:
        build(args.cache, args.out, args.preview_dir)
    except urllib.error.URLError as error:
        raise SystemExit(f"download failed: {error}") from error


if __name__ == "__main__":
    main()
