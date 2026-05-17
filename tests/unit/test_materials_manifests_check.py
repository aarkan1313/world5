"""Tests for world5.world_contract.materials_manifests preflight check.

Validates that the check catches:
- Missing albedo for a declared variant
- Variants over the per-slot cap (8)
- region_size_m / edge_blend_m sanity
- Detail manifest references to undeclared tiles
- Detail weights out of [0, 1]
- Detail tile albedo missing on disk
- Malformed JSON
And does NOT trip on:
- Missing manifest entirely (legitimate pre-Phase-5.4 state)
- Empty slots / empty detail_tiles
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from world5.world_contract import materials_manifests


def _write_image(path: Path, color: tuple[int, int, int] = (128, 128, 128)) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (4, 4), color).save(path)


def _write_manifest(world: Path, manifest: dict) -> None:
    (world / "material_variants.json").write_text(json.dumps(manifest, indent=2))


def _valid_base_manifest() -> dict:
    return {
        "_schema_version": 1,
        "world_seed": 42,
        "region_size_m": 512.0,
        "edge_blend_m": 48.0,
        "max_variants_per_slot": 8,
        "max_total_variant_layers": 256,
        "slots": [],
    }


def _run(world: Path) -> list:
    # repo_root is unused for these checks; pass world's parent for shape
    return materials_manifests.run(world.parent, world, "high")


# --- non-failures ---


def _errors(issues: list) -> list:
    return [i for i in issues if i.severity.value == "error"]


def test_missing_manifest_is_not_an_error(tmp_path: Path) -> None:
    """Pre-Phase-5.4 walking demo legitimately has no manifest.
    (May warn about missing macro_albedo.json — that's expected too.)"""
    world = tmp_path / "world"
    world.mkdir()
    issues = _run(world)
    assert _errors(issues) == []


def test_world_path_none_is_noop(tmp_path: Path) -> None:
    issues = materials_manifests.run(tmp_path, None, "high")
    assert issues == []


def test_empty_slots_no_error(tmp_path: Path) -> None:
    world = tmp_path / "world"
    world.mkdir()
    _write_manifest(world, _valid_base_manifest())
    issues = _run(world)
    assert _errors(issues) == []


def test_existing_albedo_passes(tmp_path: Path) -> None:
    world = tmp_path / "world"
    world.mkdir()
    _write_image(world / "materials" / "biome_alpine" / "ground" / "albedo.png")
    m = _valid_base_manifest()
    m["slots"] = [
        {"biome": "alpine", "slot": "ground", "variants": [
            {"id": "default", "source": "ground", "weight": 1.0}
        ]}
    ]
    _write_manifest(world, m)
    issues = _run(world)
    assert _errors(issues) == [], f"expected no errors; got {_errors(issues)}"


# --- material_variants failures ---


def test_missing_albedo_is_error_when_source_dir_exists(tmp_path: Path) -> None:
    # Source dir present but albedo absent = half-written promote state.
    # Must be a hard error so it can't ship.
    world = tmp_path / "world"
    source_dir = world / "materials" / "biome_alpine" / "ground"
    source_dir.mkdir(parents=True)
    # Write some other map but NOT albedo, so the dir exists
    _write_image(source_dir / "normal.png")
    m = _valid_base_manifest()
    m["slots"] = [
        {"biome": "alpine", "slot": "ground", "variants": [
            {"id": "default", "source": "ground", "weight": 1.0}
        ]}
    ]
    _write_manifest(world, m)
    issues = _run(world)
    codes = [i.code for i in issues]
    assert "materials_manifests.variant_albedo_missing" in codes


def test_missing_albedo_is_warning_when_source_dir_absent(tmp_path: Path) -> None:
    # Whole source dir missing = legitimate "not promoted yet" state.
    # Must NOT be a hard error or the walking demo can't ship before
    # Phase 5.4 runs.
    world = tmp_path / "world"
    (world / "materials").mkdir(parents=True)  # no biome subdirs
    m = _valid_base_manifest()
    m["slots"] = [
        {"biome": "alpine", "slot": "ground", "variants": [
            {"id": "default", "source": "ground", "weight": 1.0}
        ]}
    ]
    _write_manifest(world, m)
    issues = _run(world)
    codes = [i.code for i in issues]
    severities = {i.code: i.severity.value for i in issues}
    assert "materials_manifests.variant_albedo_missing" not in codes
    assert "materials_manifests.variant_not_yet_promoted" in codes
    assert severities["materials_manifests.variant_not_yet_promoted"] == "warning"


def test_variants_over_cap(tmp_path: Path) -> None:
    world = tmp_path / "world"
    world.mkdir()
    variants = [{"id": f"v{i}", "source": "x", "weight": 1.0} for i in range(10)]
    m = _valid_base_manifest()
    m["slots"] = [{"biome": "a", "slot": "g", "variants": variants}]
    _write_manifest(world, m)
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.variants_over_slot_cap" in codes


def test_region_size_zero(tmp_path: Path) -> None:
    world = tmp_path / "world"
    world.mkdir()
    m = _valid_base_manifest()
    m["region_size_m"] = 0.0
    _write_manifest(world, m)
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.region_size_invalid" in codes


def test_edge_blend_too_large(tmp_path: Path) -> None:
    world = tmp_path / "world"
    world.mkdir()
    m = _valid_base_manifest()
    m["region_size_m"] = 100.0
    m["edge_blend_m"] = 50.0  # > region_size/4 = 25
    _write_manifest(world, m)
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.edge_blend_too_large" in codes


def test_invalid_json_is_error(tmp_path: Path) -> None:
    world = tmp_path / "world"
    world.mkdir()
    (world / "material_variants.json").write_text("{not json")
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.material_variants_unparseable" in codes


# --- detail_array failures ---


def test_detail_dir_missing_is_warning(tmp_path: Path) -> None:
    # detail/ dir missing entirely = whole biome's detail not yet
    # promoted. Warning, not error.
    world = tmp_path / "world"
    biome_dir = world / "materials" / "biome_alpine"
    biome_dir.mkdir(parents=True)
    (biome_dir / "detail_array.json").write_text(json.dumps({
        "biome": "alpine",
        "detail_tiles": ["wet"],
        "slot_blends": {},
    }))
    issues = _run(world)
    codes = [i.code for i in issues]
    assert "materials_manifests.detail_tile_albedo_missing" not in codes
    assert "materials_manifests.detail_dir_not_yet_promoted" in codes


def test_detail_tile_missing_when_dir_exists_is_error(tmp_path: Path) -> None:
    world = tmp_path / "world"
    detail_dir = world / "materials" / "biome_alpine" / "detail"
    detail_dir.mkdir(parents=True)
    # Write some unrelated file so the dir is non-empty
    _write_image(detail_dir / "moss_albedo.png")
    biome_dir = world / "materials" / "biome_alpine"
    (biome_dir / "detail_array.json").write_text(json.dumps({
        "biome": "alpine",
        "detail_tiles": ["wet", "moss"],  # wet missing from disk
        "slot_blends": {},
    }))
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.detail_tile_albedo_missing" in codes


def test_detail_unknown_tile_ref(tmp_path: Path) -> None:
    world = tmp_path / "world"
    detail_dir = world / "materials" / "biome_alpine" / "detail"
    _write_image(detail_dir / "wet_albedo.png")
    biome_dir = world / "materials" / "biome_alpine"
    (biome_dir / "detail_array.json").write_text(json.dumps({
        "biome": "alpine",
        "detail_tiles": ["wet"],
        "slot_blends": {
            "ground": {"wet": 0.5, "lichen": 0.3},  # lichen not declared
        },
    }))
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.detail_unknown_tile_ref" in codes


def test_detail_weight_out_of_range(tmp_path: Path) -> None:
    world = tmp_path / "world"
    detail_dir = world / "materials" / "biome_alpine" / "detail"
    _write_image(detail_dir / "wet_albedo.png")
    biome_dir = world / "materials" / "biome_alpine"
    (biome_dir / "detail_array.json").write_text(json.dumps({
        "biome": "alpine",
        "detail_tiles": ["wet"],
        "slot_blends": {"ground": {"wet": 1.5}},
    }))
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.detail_weight_out_of_range" in codes


# --- macro_albedo (spec 23 §line 43-47; audit S2) ---


def test_missing_macro_albedo_json_is_warning(tmp_path: Path) -> None:
    """Bundle without macro_albedo.json warns (spec 23 wants it
    REQUIRED for visibility > 2km, but renderer gracefully falls back
    so this is a warning, not an error)."""
    world = tmp_path / "world"
    world.mkdir()
    _write_manifest(world, _valid_base_manifest())
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.macro_albedo_json_missing" in codes


def test_macro_albedo_json_present_no_warning(tmp_path: Path) -> None:
    world = tmp_path / "world"
    world.mkdir()
    _write_manifest(world, _valid_base_manifest())
    _write_image(world / "materials" / "biome_alpine" / "ground" / "macro_albedo.png")
    (world / "macro_albedo.json").write_text(json.dumps({
        "world_min_xz": [-1024.0, -1024.0],
        "world_max_xz": [1024.0, 1024.0],
        "texture": "res://materials/biome_alpine/ground/macro_albedo.png",
    }))
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.macro_albedo_json_missing" not in codes
    assert "materials_manifests.macro_albedo_texture_missing" not in codes


def test_macro_albedo_texture_missing_is_error(tmp_path: Path) -> None:
    """Manifest points at a texture file that doesn't exist = broken
    promote state; renderer logs a warn and uses fallback color."""
    world = tmp_path / "world"
    world.mkdir()
    _write_manifest(world, _valid_base_manifest())
    (world / "macro_albedo.json").write_text(json.dumps({
        "world_min_xz": [-1024.0, -1024.0],
        "world_max_xz": [1024.0, 1024.0],
        "texture": "res://materials/biome_alpine/ground/macro_albedo.png",
    }))
    # Note: no macro_albedo.png written
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.macro_albedo_texture_missing" in codes


def test_macro_albedo_json_unparseable_is_error(tmp_path: Path) -> None:
    world = tmp_path / "world"
    world.mkdir()
    _write_manifest(world, _valid_base_manifest())
    (world / "macro_albedo.json").write_text("{not json")
    codes = [i.code for i in _run(world)]
    assert "materials_manifests.macro_albedo_json_unparseable" in codes


def test_real_walking_demo_passes(tmp_path: Path) -> None:
    # Sanity: the actual checked-in walking_demo bundle must pass the
    # preflight, otherwise the engine refuses to render it. This is
    # the most important regression-guard for this check.
    walking = Path(__file__).resolve().parents[2] / "engine" / "worlds" / "walking_demo"
    if not walking.exists():
        return  # if path layout changes, skip rather than misfire
    issues = materials_manifests.run(walking.parent, walking, "high")
    fatal = [i for i in issues if i.severity.value == "error"]
    assert not fatal, f"walking_demo must pass preflight; errors: {fatal}"
