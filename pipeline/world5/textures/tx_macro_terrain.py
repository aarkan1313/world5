"""Build terrain macro-albedo companions from shipped detail tiles.

W5 Phase 5.1 port from W4. Per-biome PURPOSE_PRESETS still
hardcoded in this file; Phase 5.4.b will extract them to per-biome
YAML alongside the <biome>.yaml authoring configs.

The close-detail terrain textures are still useful; this derives a
separate world-scale albedo companion from each biome ground tile
so the renderer can blend distance terrain against larger forms
instead of sampling only the detail tile's averaged mip color.

Outputs land at the world bundle:

    engine/worlds/<world>/macro_albedo.png + macro_albedo.json
    engine/worlds/<world>/captures/macro_albedo_sheet.png

No source material is overwritten.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


# W5 layout — defaults point at walking_demo since it's the v1
# reference world. Callers override via CLI for other worlds.
W5_ROOT = Path(__file__).resolve().parents[3]
ENGINE_ROOT = W5_ROOT / "engine"
DEFAULT_WORLD = ENGINE_ROOT / "worlds" / "walking_demo"
DEFAULT_CATALOG = DEFAULT_WORLD / "biome_catalog.json"
DEFAULT_SHEET = DEFAULT_WORLD / "captures" / "macro_albedo_sheet.png"
DEFAULT_CANDIDATE_DIR = W5_ROOT / "pipeline" / "textures" / "candidates" / "macro_terrain_v1"
DEFAULT_COMPARE_SHEET = DEFAULT_WORLD / "captures" / "macro_albedo_compare.png"
DEFAULT_TILED_SHEET = DEFAULT_WORLD / "captures" / "macro_albedo_compare_tiled.png"

# Aliases for code paths that referenced W4 names. GODOT_ROOT in W4
# was the inner Godot project dir; in W5 the engine root contains
# `worlds/` directly (no inner Godot project — the demo/ project
# pulls engine/ in via the addons junction). Keeping the alias
# pointing at ENGINE_ROOT so res://-style path resolution still
# works for the macro builder's catalog walk.
PROJECT_ROOT = W5_ROOT
GODOT_ROOT = ENGINE_ROOT


PURPOSE_PRESETS = {
    "alpine": {
        "label": "broad snowfields, wind-slab shadows, sparse exposed stone",
        "palette": [
            (0.86, 0.90, 0.90),
            (0.98, 0.98, 0.93),
            (0.58, 0.62, 0.61),
            (0.70, 0.80, 0.88),
        ],
    },
    "desert": {
        "label": "dune sheets, sand-wash bands, dry clay patches",
        "palette": [
            (0.76, 0.52, 0.26),
            (0.92, 0.68, 0.34),
            (0.58, 0.40, 0.23),
            (0.82, 0.61, 0.39),
        ],
    },
    "rocky": {
        "label": "large talus fields, bedrock slabs, dusty grey scree",
        "palette": [
            (0.42, 0.41, 0.40),
            (0.58, 0.56, 0.53),
            (0.31, 0.32, 0.32),
            (0.52, 0.50, 0.46),
        ],
    },
    "wetland": {
        "label": "moss mats, dark peat flats, muted reed islands",
        "palette": [
            (0.10, 0.13, 0.05),
            (0.20, 0.30, 0.10),
            (0.08, 0.06, 0.03),
            (0.32, 0.26, 0.12),
        ],
    },
}


def _res_path_to_disk(path: str) -> Path:
    if path.startswith("res://"):
        return GODOT_ROOT / path.removeprefix("res://")
    return GODOT_ROOT / path


def _wrapped_blur(img: Image.Image, radius: float) -> Image.Image:
    w, h = img.size
    tiled = Image.new("RGB", (w * 3, h * 3))
    for ty in range(3):
        for tx in range(3):
            tiled.paste(img, (tx * w, ty * h))
    blurred = tiled.filter(ImageFilter.GaussianBlur(radius=radius))
    return blurred.crop((w, h, w * 2, h * 2))


def _tileable_noise(size: int, grid: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    low = rng.random((grid, grid), dtype=np.float32)
    low = np.tile(low, (3, 3))
    low_img = Image.fromarray(np.uint8(np.clip(low * 255.0, 0, 255)), "L")
    up = low_img.resize((size * 3, size * 3), Image.Resampling.BICUBIC)
    crop = up.crop((size, size, size * 2, size * 2))
    arr = np.asarray(crop, dtype=np.float32) / 255.0
    return (arr - float(arr.mean())) / max(float(arr.std()), 1e-5)


def _normalize01(arr: np.ndarray) -> np.ndarray:
    lo = float(arr.min())
    hi = float(arr.max())
    return (arr - lo) / max(hi - lo, 1e-5)


def _smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-5), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _fbm_tileable(size: int, seed: int, grids: tuple[int, ...] = (3, 5, 9, 17)) -> np.ndarray:
    total = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    amp_sum = 0.0
    for idx, grid in enumerate(grids):
        total += _tileable_noise(size, grid, seed + idx * 7919) * amp
        amp_sum += amp
        amp *= 0.55
    return total / max(amp_sum, 1e-5)


def _wave_field(size: int, seed: int, terms: int = 5) -> np.ndarray:
    rng = np.random.default_rng(seed)
    coords = np.linspace(0.0, math.tau, size, endpoint=False, dtype=np.float32)
    xx, yy = np.meshgrid(coords, coords)
    field = np.zeros((size, size), dtype=np.float32)
    for _ in range(terms):
        kx = int(rng.integers(1, 5))
        ky = int(rng.integers(0, 4))
        if kx == 0 and ky == 0:
            kx = 1
        phase = float(rng.random() * math.tau)
        field += np.sin(xx * kx + yy * ky + phase).astype(np.float32)
    return field / max(float(terms), 1.0)


def _match_source_mean(src: Image.Image, macro: np.ndarray, strength: float = 0.72) -> np.ndarray:
    src_arr = np.asarray(src.convert("RGB"), dtype=np.float32) / 255.0
    src_mean = src_arr.mean(axis=(0, 1), keepdims=True)
    macro_mean = macro.mean(axis=(0, 1), keepdims=True)
    shifted = macro * (src_mean / np.maximum(macro_mean, 1e-4))
    return np.clip(macro * (1.0 - strength) + shifted * strength, 0.0, 1.0)


def _edge_wrap_mse(arr: np.ndarray) -> float:
    left_right = np.mean((arr[:, 0, :] - arr[:, -1, :]) ** 2)
    top_bottom = np.mean((arr[0, :, :] - arr[-1, :, :]) ** 2)
    return round(float((left_right + top_bottom) * 0.5), 8)


def _purpose_macro_array(biome: str, src: Image.Image, seed: int) -> np.ndarray:
    size = src.size[0]
    preset = PURPOSE_PRESETS.get(biome, PURPOSE_PRESETS["rocky"])
    colors = np.asarray(preset["palette"], dtype=np.float32)
    large = _normalize01(_fbm_tileable(size, seed, (3, 5, 9)))
    medium = _normalize01(_fbm_tileable(size, seed + 101, (7, 13, 23)))
    waves = _normalize01(_wave_field(size, seed + 202, 6))
    fine = _normalize01(_fbm_tileable(size, seed + 303, (17, 31)))

    if biome == "alpine":
        stone = _smoothstep(0.68, 0.88, large + (medium - 0.5) * 0.20)
        ice = _smoothstep(0.62, 0.88, waves + (fine - 0.5) * 0.14)
        snow = colors[0] * (0.86 + waves[..., None] * 0.18)
        macro = snow
        macro = macro * (1.0 - stone[..., None] * 0.34) + colors[2] * stone[..., None] * 0.34
        macro = macro * (1.0 - ice[..., None] * 0.18) + colors[3] * ice[..., None] * 0.18
        macro += (fine[..., None] - 0.5) * 0.025
    elif biome == "desert":
        dune = _smoothstep(0.22, 0.80, waves * 0.72 + medium * 0.28)
        wash = _smoothstep(0.64, 0.84, large)
        clay = _smoothstep(0.22, 0.40, large)
        macro = colors[0] * (1.0 - dune[..., None]) + colors[1] * dune[..., None]
        macro = macro * (1.0 - wash[..., None] * 0.24) + colors[2] * wash[..., None] * 0.24
        macro = macro * (1.0 - clay[..., None] * 0.18) + colors[3] * clay[..., None] * 0.18
        macro += (fine[..., None] - 0.5) * 0.022
    elif biome == "wetland":
        peat = _smoothstep(0.58, 0.82, large)
        moss = _smoothstep(0.42, 0.74, medium + (waves - 0.5) * 0.20)
        reeds = _smoothstep(0.70, 0.88, waves + (fine - 0.5) * 0.10)
        macro = colors[0] * (1.0 - moss[..., None]) + colors[1] * moss[..., None]
        macro = macro * (1.0 - peat[..., None] * 0.38) + colors[2] * peat[..., None] * 0.38
        macro = macro * (1.0 - reeds[..., None] * 0.24) + colors[3] * reeds[..., None] * 0.24
        macro += (fine[..., None] - 0.5) * 0.018
    else:
        slabs = _smoothstep(0.58, 0.84, large)
        dark = _smoothstep(0.66, 0.88, medium)
        dust = _smoothstep(0.18, 0.42, waves)
        macro = colors[0] * (1.0 - slabs[..., None]) + colors[1] * slabs[..., None]
        macro = macro * (1.0 - dark[..., None] * 0.28) + colors[2] * dark[..., None] * 0.28
        macro = macro * (1.0 - dust[..., None] * 0.20) + colors[3] * dust[..., None] * 0.20
        macro += (fine[..., None] - 0.5) * 0.025

    return _match_source_mean(src, np.clip(macro, 0.0, 1.0))


def build_purpose_macro_albedo(
        biome: str,
        src_path: Path,
        out_path: Path,
        *,
        seed: int = 42) -> dict:
    src = Image.open(src_path).convert("RGB")
    if src.size[0] != src.size[1]:
        raise ValueError(f"expected square texture: {src_path}")
    macro = _purpose_macro_array(biome, src, seed)
    out = Image.fromarray(np.uint8(np.round(np.clip(macro, 0.0, 1.0) * 255.0)), "RGB")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out.save(out_path)
    return {
        "biome": biome,
        "source": str(src_path),
        "output": str(out_path),
        "kind": "purpose_macro_v1",
        "label": PURPOSE_PRESETS.get(biome, PURPOSE_PRESETS["rocky"])["label"],
        "seed": seed,
        "size": src.size[0],
        "source_mean_rgb": [round(float(v), 4) for v in np.asarray(src, dtype=np.float32).mean(axis=(0, 1)) / 255.0],
        "macro_mean_rgb": [round(float(v), 4) for v in macro.mean(axis=(0, 1))],
        "macro_std_luma": round(float(macro.mean(axis=2).std()), 4),
        "edge_wrap_mse": _edge_wrap_mse(macro),
    }


def derive_macro_albedo(
        src_path: Path,
        out_path: Path,
        *,
        blur_radius: float = 24.0,
        noise_grid: int = 9,
        noise_strength: float = 0.11,
        contrast: float = 1.08,
        seed: int = 42) -> dict:
    src = Image.open(src_path).convert("RGB")
    size = src.size[0]
    if src.size[0] != src.size[1]:
        raise ValueError(f"expected square texture: {src_path}")

    base = np.asarray(_wrapped_blur(src, blur_radius), dtype=np.float32) / 255.0
    noise_a = _tileable_noise(size, noise_grid, seed)
    noise_b = _tileable_noise(size, max(3, noise_grid // 2), seed + 101)

    luma = base.mean(axis=2, keepdims=True)
    base = luma + (base - luma) * contrast

    value = 1.0 + noise_a[..., None] * noise_strength
    warm_cool = noise_b[..., None] * noise_strength * 0.22
    tint = np.concatenate([
        1.0 + warm_cool,
        np.ones_like(warm_cool),
        1.0 - warm_cool,
    ], axis=2)
    macro = np.clip(base * value * tint, 0.0, 1.0)

    out = Image.fromarray(np.uint8(np.round(macro * 255.0)), "RGB")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out.save(out_path)

    return {
        "source": str(src_path),
        "output": str(out_path),
        "size": size,
        "blur_radius": blur_radius,
        "noise_grid": noise_grid,
        "noise_strength": noise_strength,
        "contrast": contrast,
        "seed": seed,
        "source_mean_rgb": [round(float(v), 4) for v in np.asarray(src, dtype=np.float32).mean(axis=(0, 1)) / 255.0],
        "macro_mean_rgb": [round(float(v), 4) for v in macro.mean(axis=(0, 1))],
        "macro_std_luma": round(float(macro.mean(axis=2).std()), 4),
        "edge_wrap_mse": _edge_wrap_mse(macro),
    }


def _catalog_ground_layers(catalog_path: Path) -> Iterable[tuple[str, Path, Path]]:
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    for biome in catalog.get("biomes", []):
        name = str(biome["name"])
        kit_dir = str(biome["kit_dir"])
        src = _res_path_to_disk(f"res://{kit_dir}/ground/albedo.png")
        out = _res_path_to_disk(f"res://{kit_dir}/ground/macro_albedo.png")
        yield name, src, out


def _make_sheet(entries: list[dict], sheet_path: Path, thumb: int = 256) -> None:
    if not entries:
        return
    font = ImageFont.load_default()
    cols = 2
    rows = len(entries)
    label_h = 28
    pad = 12
    cell_w = thumb * 2 + pad * 3
    cell_h = thumb + label_h + pad * 2
    sheet = Image.new("RGB", (cell_w * cols, cell_h * math.ceil(rows / cols)), (26, 28, 30))
    draw = ImageDraw.Draw(sheet)
    for idx, entry in enumerate(entries):
        col = idx % cols
        row = idx // cols
        x = col * cell_w + pad
        y = row * cell_h + pad
        src = Image.open(entry["source"]).convert("RGB").resize((thumb, thumb), Image.Resampling.LANCZOS)
        macro = Image.open(entry["output"]).convert("RGB").resize((thumb, thumb), Image.Resampling.LANCZOS)
        sheet.paste(src, (x, y + label_h))
        sheet.paste(macro, (x + thumb + pad, y + label_h))
        draw.text((x, y), f"{entry['biome']} detail -> macro", fill=(230, 230, 230), font=font)
    sheet_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(sheet_path)


def _make_compare_sheet(entries: list[dict], sheet_path: Path, thumb: int = 224) -> None:
    if not entries:
        return
    font = ImageFont.load_default()
    rows = len(entries)
    label_h = 42
    pad = 12
    cols = 3
    cell_w = thumb * cols + pad * (cols + 1)
    cell_h = thumb + label_h + pad * 2
    sheet = Image.new("RGB", (cell_w, cell_h * rows), (24, 26, 28))
    draw = ImageDraw.Draw(sheet)
    headers = ("detail", "derived", "purpose")
    for row, entry in enumerate(entries):
        x0 = pad
        y0 = row * cell_h + pad
        paths = (entry["source"], entry["derived"], entry["purpose"])
        for col, path in enumerate(paths):
            img = Image.open(path).convert("RGB").resize((thumb, thumb), Image.Resampling.LANCZOS)
            x = x0 + col * (thumb + pad)
            sheet.paste(img, (x, y0 + label_h))
            draw.text((x, y0), headers[col], fill=(210, 210, 210), font=font)
        label = "%s: %s" % (entry["biome"], entry.get("purpose_label", "purpose macro"))
        draw.text((x0, y0 + 16), label, fill=(235, 235, 235), font=font)
    sheet_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(sheet_path)


def _make_tiled_sheet(entries: list[dict], sheet_path: Path, thumb: int = 160) -> None:
    if not entries:
        return
    font = ImageFont.load_default()
    cols = 2
    rows = len(entries)
    label_h = 32
    pad = 12
    tile_w = thumb * 2
    cell_w = tile_w * cols + pad * (cols + 1)
    cell_h = tile_w + label_h + pad * 2
    sheet = Image.new("RGB", (cell_w, cell_h * rows), (24, 26, 28))
    draw = ImageDraw.Draw(sheet)
    headers = ("derived 2x2", "purpose 2x2")
    for row, entry in enumerate(entries):
        y0 = row * cell_h + pad
        for col, key in enumerate(("derived", "purpose")):
            src = Image.open(entry[key]).convert("RGB").resize((thumb, thumb), Image.Resampling.LANCZOS)
            tiled = Image.new("RGB", (tile_w, tile_w))
            for ty in range(2):
                for tx in range(2):
                    tiled.paste(src, (tx * thumb, ty * thumb))
            x = pad + col * (tile_w + pad)
            sheet.paste(tiled, (x, y0 + label_h))
            draw.text((x, y0), headers[col], fill=(220, 220, 220), font=font)
            draw.text((x, y0 + 14), entry["biome"], fill=(235, 235, 235), font=font)
    sheet_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(sheet_path)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Derive terrain macro albedo companions.")
    ap.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    ap.add_argument("--sheet", type=Path, default=DEFAULT_SHEET)
    ap.add_argument("--blur-radius", type=float, default=24.0)
    ap.add_argument("--noise-grid", type=int, default=9)
    ap.add_argument("--noise-strength", type=float, default=0.11)
    ap.add_argument("--contrast", type=float, default=1.08)
    ap.add_argument("--seed", type=int, default=42042)
    ap.add_argument("--purpose-candidates", action="store_true",
                    help="Also build purpose-made macro candidates and a comparison sheet.")
    ap.add_argument("--candidate-dir", type=Path, default=DEFAULT_CANDIDATE_DIR)
    ap.add_argument("--compare-sheet", type=Path, default=DEFAULT_COMPARE_SHEET)
    ap.add_argument("--tiled-sheet", type=Path, default=DEFAULT_TILED_SHEET)
    ap.add_argument("--promote-purpose", action="store_true",
                    help="Copy purpose candidates to ground/macro_albedo.png after comparison.")
    args = ap.parse_args(argv)

    entries: list[dict] = []
    purpose_entries: list[dict] = []
    compare_entries: list[dict] = []
    for idx, (biome, src, out) in enumerate(_catalog_ground_layers(args.catalog)):
        if not src.exists():
            print(f"[tx_macro_terrain] skip missing {biome}: {src}")
            continue
        derived_out = out
        if args.purpose_candidates and args.promote_purpose:
            derived_out = args.candidate_dir / biome / "derived_albedo.png"
        entry = derive_macro_albedo(
            src, derived_out,
            blur_radius=args.blur_radius,
            noise_grid=args.noise_grid,
            noise_strength=args.noise_strength,
            contrast=args.contrast,
            seed=args.seed + idx * 1009)
        entry["biome"] = biome
        entries.append(entry)
        print(f"[tx_macro_terrain] {biome}: {src.name} -> {derived_out}")

        if args.purpose_candidates:
            purpose_out = args.candidate_dir / biome / "purpose_albedo.png"
            purpose_entry = build_purpose_macro_albedo(
                biome,
                src,
                purpose_out,
                seed=args.seed + idx * 2003 + 17)
            purpose_entries.append(purpose_entry)
            compare_entries.append({
                "biome": biome,
                "source": str(src),
                "derived": str(derived_out),
                "purpose": str(purpose_out),
                "purpose_label": purpose_entry["label"],
            })
            if args.promote_purpose:
                Image.open(purpose_out).convert("RGB").save(out)
                purpose_entry["promoted_to"] = str(out)
                print(f"[tx_macro_terrain] promoted purpose {biome}: {purpose_out} -> {out}")

    manifest = {
        "version": "w4_macro_albedo_derived_v1",
        "catalog": str(args.catalog),
        "entries": entries,
        "purpose_entries": purpose_entries,
        "promote_purpose": bool(args.promote_purpose),
    }
    manifest_path = args.sheet.with_suffix(".json")
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    _make_sheet(entries, args.sheet)
    if compare_entries:
        compare_manifest_path = args.compare_sheet.with_suffix(".json")
        compare_manifest = {
            "version": "w4_macro_albedo_compare_v1",
            "catalog": str(args.catalog),
            "entries": compare_entries,
            "purpose_entries": purpose_entries,
        }
        compare_manifest_path.write_text(json.dumps(compare_manifest, indent=2), encoding="utf-8")
        _make_compare_sheet(compare_entries, args.compare_sheet)
        _make_tiled_sheet(compare_entries, args.tiled_sheet)
        print(f"[tx_macro_terrain] wrote {args.compare_sheet}")
        print(f"[tx_macro_terrain] wrote {compare_manifest_path}")
        print(f"[tx_macro_terrain] wrote {args.tiled_sheet}")
    print(f"[tx_macro_terrain] wrote {args.sheet}")
    print(f"[tx_macro_terrain] wrote {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
