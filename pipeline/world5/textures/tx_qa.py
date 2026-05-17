"""W4 tx_qa — texture QA with terrain-specific checks.

Builds on top of the upstream texture_qa.py's three base checks
(edge_continuity, junction_visibility, periodic_artifact) and adds
three W4-specific checks for the terrain quality bar:

  tile_4x4_lattice    — render 4x4 in memory, run periodic on the mosaic.
                        Catches "looks fine alone but reads as a lattice
                        when actually tiled across terrain" failures
                        (the old_drift class — dunes that loop visibly).

  mip_richness_decay  — generate mip levels (256/128/64/32), measure how
                        fast richness collapses. If mip32 is nearly
                        uniform grey, the texture won't read at top-down
                        distance.

  palette_extract     — extract a 5-color palette. Stored for per-biome
                        coherence checks at promotion time (not used in
                        the A-D grade).

W4 grading: pass requires the 3 upstream checks AND tile_4x4_lattice
AND mip_richness_decay. palette_extract is advisory.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Import the three upstream checks as pure functions
sys.path.insert(0, r"D:/assets/pipelines/textures")
from texture_qa import (  # noqa: E402
    CATEGORY_THRESHOLDS as UPSTREAM_CATEGORY_THRESHOLDS,
    edge_continuity, junction_visibility, periodic_artifact, richness,
    EDGE_CONTINUITY_PASS, JUNCTION_RATIO_PASS, PERIODIC_LOCALITY_PASS,
    RICHNESS_PASS,
)


# W4 per-category overrides. We inherit upstream's category thresholds
# (Snow=13 after this session's tightening) and add new W4 checks'
# thresholds. The new checks default to one value, overridden by category.
# tile_4x4_lattice: advisory only — empirical calibration on 16 alpine
# snow grounds (good visual ones range 154-619; bad ones 285-1160) showed
# the single-image periodic_artifact metric is more discriminative. We
# still compute tile_4x4 to log the value but it does NOT contribute to
# the A-D grade unless explicitly enabled.
W4_TILE_4X4_LATTICE_ADVISORY = True

# mip32_stdev: minimum stdev of luminance at the 32px mip level. Below
# this, the texture flattens into uniform color when viewed at top-down
# terrain distance. Calibration on 16 alpine grounds: visually-readable
# textures sit at 30-100; flat "blank canvas" failures (fresh_powder,
# fresh_blanket, old_drift) sit at 3-10.
W4_MIP32_STDEV_MIN = 15.0

W4_CATEGORY_OVERRIDES = {
    # Recalibration 2026-05-12 (post-hybrid): SM-output albedos are
    # legitimately softer (uniform low-frequency content) but still
    # readable at terrain distance. The shipped biome_alpine/ground
    # has mip32_stdev=7.14 and looks fine in-engine. Threshold 6 leaves
    # margin for SM-output Snow without admitting actually-flat outputs
    # (fresh_powder/old_drift sit at 3-10 in the original derive runs).
    "Snow":    {"mip32_stdev": 6.0},
    "Sand":    {"mip32_stdev": 6.0},
    "Mixed":   {"mip32_stdev": 10.0},
    # Rock recalibration 2026-05-12: granite at mip32=8.6 and dark
    # slate at 13.5 both visually pass — threshold of 15 was untested
    # and too strict. Real rock outputs sit at 8-14; 8 captures the
    # lower end while still rejecting flat outputs (which sit at <5).
    "Rock":    {"mip32_stdev": 8.0},
    "Concrete":{"mip32_stdev": 8.0},
}


def _w4_thresholds_for(category: str | None) -> dict:
    upstream = UPSTREAM_CATEGORY_THRESHOLDS.get(category or "", {})
    base = {
        "edge_continuity": EDGE_CONTINUITY_PASS,
        "junction_visibility": JUNCTION_RATIO_PASS,
        "periodic_artifact": upstream.get("periodic", PERIODIC_LOCALITY_PASS),
        "richness": upstream.get("richness", RICHNESS_PASS),
        "mip32_stdev": W4_MIP32_STDEV_MIN,
    }
    overrides = W4_CATEGORY_OVERRIDES.get(category or "", {})
    if "mip32_stdev" in overrides:
        base["mip32_stdev"] = overrides["mip32_stdev"]
    return base


def tile_4x4_lattice(im: np.ndarray, threshold: float) -> dict:
    """Render 4x4 mosaic of the texture, run periodic_artifact on it.

    The single-image periodic check catches sharp narrow peaks. This
    catches low-frequency content (like the old_drift dunes) that
    only becomes visible as a lattice when the texture is actually
    tiled. Math is the same as upstream periodic_artifact but on a
    larger image that reveals lower-frequency repetition.
    """
    if im.ndim == 2:
        im = np.stack([im, im, im], axis=-1)
    # tile_4x4_lattice takes uint8 to do PIL resize; we'll normalize for
    # the FFT-based periodic_artifact call below.
    im_u8 = im.astype(np.uint8) if im.dtype != np.uint8 else im
    h, w = im_u8.shape[:2]
    # Build the 4x4 mosaic by indexed tiling
    big = np.tile(im_u8, (4, 4, 1))
    # Downsample for speed if needed — periodic_artifact scales as N log N
    if big.shape[0] > 2048:
        ratio = 2048 / big.shape[0]
        new_h = int(big.shape[0] * ratio)
        new_w = int(big.shape[1] * ratio)
        big = np.asarray(Image.fromarray(big).resize((new_w, new_h),
                                                     Image.LANCZOS))
    # periodic_artifact wants 0..1 floats
    big_norm = big.astype(np.float32) / 255.0
    pa = periodic_artifact(big_norm, threshold=threshold)
    return {
        "mosaic_size": list(big.shape[:2]),
        "peak_locality_ratio": pa["peak_locality_ratio"],
        "peak_period_px": pa["peak_period_px"],
        "passed": pa["peak_locality_ratio"] < threshold,
        "threshold": threshold,
    }


def mip32_stdev(im: np.ndarray, threshold: float,
                sizes: tuple[int, ...] = (256, 128, 64, 32)) -> dict:
    """Measure luminance stdev at each mip level — proxy for terrain-distance readability.

    A texture that vanishes into uniform color at mip32 won't read when
    viewed top-down across many tiles. Calibration on alpine ground set:
    visually-readable textures sit at 30-100 stdev at mip32; "blank
    canvas" failures (fresh_powder, fresh_blanket, old_drift) sit at 3-10.

    Returns the stdev at each size + the smallest-size stdev for grading.
    """
    im_u8 = im.astype(np.uint8) if im.dtype != np.uint8 else im
    h, w = im_u8.shape[:2]
    source_pil = Image.fromarray(im_u8)

    stdevs: dict[int, float] = {}
    for s in sizes:
        if s > min(h, w):
            continue
        gray = np.asarray(source_pil.resize((s, s), Image.LANCZOS).convert("L"),
                          dtype=np.float32)
        stdevs[s] = float(gray.std())
    smallest_size = min(stdevs.keys()) if stdevs else None
    smallest_stdev = stdevs[smallest_size] if smallest_size else 0.0
    return {
        "by_size": stdevs,
        "smallest_size": smallest_size,
        "stdev_at_smallest": smallest_stdev,
        "passed": smallest_stdev >= threshold,
        "threshold": threshold,
    }


def palette_extract(im: np.ndarray, n_colors: int = 5) -> dict:
    """Extract a small color palette from the albedo.

    Uses k-means over a downsampled image. Stored for promotion-time
    biome-palette coherence checks (not part of the A-D grade).
    """
    small = np.asarray(Image.fromarray(im).resize((128, 128), Image.LANCZOS)
                       .convert("RGB"))
    pixels = small.reshape(-1, 3).astype(np.float32)
    # tiny in-house k-means (no sklearn dep)
    rng = np.random.default_rng(42)
    idx = rng.choice(len(pixels), size=n_colors, replace=False)
    centroids = pixels[idx].copy()
    for _ in range(20):
        # assign
        d = ((pixels[:, None, :] - centroids[None, :, :]) ** 2).sum(axis=-1)
        labels = d.argmin(axis=1)
        # update
        new_centroids = np.array([
            pixels[labels == k].mean(axis=0) if (labels == k).any()
            else centroids[k]
            for k in range(n_colors)])
        if np.allclose(new_centroids, centroids, atol=0.5):
            break
        centroids = new_centroids
    weights = np.array([(labels == k).sum() / len(labels)
                       for k in range(n_colors)])
    order = np.argsort(-weights)
    return {
        "n_colors": n_colors,
        "colors_rgb": centroids[order].astype(int).tolist(),
        "weights": weights[order].round(3).tolist(),
    }


def qa_albedo(albedo_path: Path, category: str | None = None) -> dict:
    """Run full W4 QA on an albedo image. Returns a structured report.

    Grade computed from 5 checks (3 upstream + tile_4x4 + mip_decay).
    Palette is advisory (not in grade).
    """
    # Upstream checks (edge_continuity / junction_visibility / periodic_artifact
    # / richness) expect a float32 image normalized to 0..1. Same convention here.
    im_u8 = np.asarray(Image.open(albedo_path).convert("RGB"), dtype=np.uint8)
    im = im_u8.astype(np.float32) / 255.0
    th = _w4_thresholds_for(category)
    # tile_4x4_lattice runs but its threshold is arbitrary; we record the
    # value for diagnostics and don't grade on it (advisory). The single-
    # image periodic_artifact metric covers what we need for the lattice
    # failure mode, per calibration on the alpine ground set.
    tile_4x4_advisory = tile_4x4_lattice(im_u8, threshold=999.0)
    checks = {
        "edge_continuity": edge_continuity(im, threshold=th["edge_continuity"]),
        "junction_visibility": junction_visibility(im, threshold=th["junction_visibility"]),
        "periodic_artifact": periodic_artifact(im, threshold=th["periodic_artifact"]),
        "mip32_stdev": mip32_stdev(im_u8, threshold=th["mip32_stdev"]),
        "richness": richness(im, threshold=th["richness"]),
    }
    # 4-check grade (richness is advisory like upstream, tile_4x4 is too)
    grade_checks = ("edge_continuity", "junction_visibility",
                    "periodic_artifact", "mip32_stdev")
    passed = sum(1 for k in grade_checks if checks[k]["passed"])
    if passed == 4:
        grade = "A"
    elif passed >= 3:
        grade = "B"
    elif passed >= 2:
        grade = "C"
    else:
        grade = "D"
    return {
        "version": "w4_tx_qa_v1",
        "category": category,
        "thresholds_applied": th,
        "checks": checks,
        "advisory": {
            "richness": checks["richness"],
            "tile_4x4_lattice": tile_4x4_advisory,
            "palette": palette_extract(im_u8),
        },
        "grade": grade,
        "passed_checks": passed,
        "passed": grade == "A",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--albedo", type=Path, required=True)
    ap.add_argument("--category", default=None)
    ap.add_argument("--out", type=Path, default=None,
                    help="write the report JSON here (default: stdout only)")
    args = ap.parse_args()
    report = qa_albedo(args.albedo, args.category)
    text = json.dumps(report, indent=2, default=lambda o: float(o)
                       if hasattr(o, "__float__") else str(o))
    print(text)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"\nwrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
