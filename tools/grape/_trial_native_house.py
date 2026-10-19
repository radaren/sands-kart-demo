"""Throwaway probe: how many triangles does a native flat-roof parapet building cost?
Writes nothing into the project; run with MAGICLOMIX_PYTHON.
"""
import sys

import numpy as np

import grape

b = grape.kits.buildings


def triangle_count(dt: grape.Detail) -> int:
    total = 0
    for prim in dt.primOffsets():
        total += max(0, len(dt.primPoints(prim)) - 2)
    return total


footprint = [(0.0, 0.0), (8.0, 0.0), (8.0, 7.0), (0.0, 7.0)]

for name, kwargs in [
    ("lowrise", dict(style=b.BuildingStylePreset.LowriseResidential, height=4.6)),
    ("basic", dict(style=b.BuildingStylePreset.Basic, height=4.6)),
]:
    asset = b.makeBuildingAsset(
        footprint,
        front_direction=[0, 1],
        seed=7,
        detail=b.BuildingDetailLevel.Exterior,
        **kwargs,
    )
    dt = asset.toDetail()
    packed = dt.primCount()
    grape.unpack(dt)
    tris = triangle_count(dt)
    xs = np.array([p for p in dt.pointPositions()])
    lo, hi = xs.min(axis=0), xs.max(axis=0)
    print(
        f"{name:14s} tris={tris:6d} prims={dt.primCount():5d} (packed before unpack={packed}) "
        f"size={np.round(hi - lo, 2)} min={np.round(lo, 2)} max={np.round(hi, 2)} "
        f"mats={grape.listMaterialNames(dt)}"
    )


def build_explicit(height: float, bay_pitch: float, window_fraction, ground: float) -> grape.Detail:
    corners = [
        b.BuildingCorner(id=b.BuildingId(f"c:{i}"), position=np.array([x, z]))
        for i, (x, z) in enumerate(footprint)
    ]
    document = b.makeBuildingMassing(corners, b.BuildingMassingOptions(height=height, seed=11))
    facade = b.BuildingFacadeSettings(
        bay_pitch=bay_pitch,
        window_fraction=window_fraction,
        window_recess=0.12,
        ground_floor_height=ground,
        floor_bands=False,
        facade_accents=False,
        opening_interiors=False,
        windows=b.BuildingWindowRecipe.Window,
        ground_floor=b.BuildingGroundFloor.Entrance,
    )
    roof = b.FlatRoofSettings(edge=b.FlatRoofEdge.Parapet, parapet_height=0.65, parapet_width=0.22)
    document = b.makeBuildingRecipe(
        document,
        facade=facade,
        roof=roof,
        material=document.materials[0].id,
    )
    asset = b.BuildingCompiler().compileAsset(document)
    dt = asset.toDetail()
    grape.unpack(dt)
    return dt


for name, args in [
    ("flat_parapet", (4.6, 3.5, (0.30, 0.22), 2.9)),
    ("flat_tall", (5.5, 4.0, (0.28, 0.20), 3.0)),
]:
    dt = build_explicit(*args)
    xs = dt.pointPositions()
    lo, hi = xs.min(axis=0), xs.max(axis=0)
    print(
        f"{name:14s} tris={triangle_count(dt):6d} prims={dt.primCount():5d} "
        f"size={np.round(hi - lo, 2)} min={np.round(lo, 2)} max={np.round(hi, 2)} "
        f"mats={len(grape.listMaterialNames(dt))}"
    )
